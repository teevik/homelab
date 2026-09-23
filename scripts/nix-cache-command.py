"""Restricted SSH entry point and retained generations for the private cache."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time


STORE_PATH = re.compile(r"/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+")
GENERATION = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}")


def run(*args, input=None):
    return subprocess.check_output(args, text=True, input=input).strip()


def path_info(config, paths):
    info = json.loads(run(config["nix"], "path-info", "--recursive", "--json", "--stdin",
                          input="".join(path + "\n" for path in paths)))
    if isinstance(info, list):
        info = {entry["path"]: entry for entry in info}
    if not info or any(value is None for value in info.values()):
        raise ValueError("The complete closure must exist before publication")
    return info


def closure_digest(paths):
    return hashlib.sha256("".join(path + "\n" for path in sorted(paths)).encode()).hexdigest()


def check_space(config, incoming=0):
    fs = os.statvfs(config["storeDirectory"])
    available = fs.f_bavail * fs.f_frsize
    if available - incoming < config["minFreeBytes"]:
        raise ValueError("Cache upload refused: insufficient filesystem headroom")
    return available


def publish(config, host, generation, path):
    if host not in config["hosts"] or not GENERATION.fullmatch(generation) or generation == "latest":
        raise ValueError("Invalid host or generation")
    if not STORE_PATH.fullmatch(path) or not Path(path).name[33:].startswith(f"nixos-system-{host}-"):
        raise ValueError("Expected a NixOS system output for the selected host")
    roots = Path(config["rootsDirectory"])
    with (roots / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        check_space(config)
        directory = roots / host
        directory.mkdir(exist_ok=True)
        root = directory / generation
        if root.is_symlink() and os.readlink(root) != path:
            raise ValueError("This generation already identifies a different system")
        created = not root.is_symlink()
        if created:
            # Register before inspecting, so GC cannot collect the closure while
            # it is being verified. Missing paths must never trigger a build.
            run(config["nixStore"], "--realise", path, "--add-root", str(root),
                "--option", "substitute", "false", "--option", "max-jobs", "0")
        try:
            info = path_info(config, [path])
        except Exception:
            # Leave the previous latest generation protected on failure.
            if created:
                root.unlink(missing_ok=True)
            raise
        latest = directory / "latest"
        temporary = directory / ".latest-new"
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(path)
        os.replace(temporary, latest)
        # The newly published generation always survives, including a retry of
        # an older run. Other generations are pruned by publication time.
        os.utime(root, follow_symlinks=False)
        generations = sorted(
            (p for p in directory.iterdir() if not p.name.startswith(".") and p.name != "latest"),
            key=lambda p: (p.lstat().st_mtime_ns, p.name), reverse=True,
        )
        for old in generations[config["keepGenerations"]:]:
            old.unlink()
        retained = [str(p) for h in config["hosts"] for p in (roots / h).glob("*") if p.is_symlink()]
        retained_info = path_info(config, retained)
        retained_bytes = sum(p["narSize"] for p in retained_info.values())
        result = {
            "host": host, "generation": generation, "path": path,
            "closurePaths": len(info), "closureDigest": closure_digest(info),
            "closureBytes": sum(p["narSize"] for p in info.values()),
            "retainedBytes": retained_bytes,
            "overBudget": retained_bytes > config["budgetBytes"],
        }
        if result["overBudget"]:
            print("Cache retention exceeds its operating budget; review older generations", file=sys.stderr)
        return result


def dependency_roots(directory):
    return [str(path) for path in directory.rglob("root*") if path.is_symlink()]


def prune_dependencies(config, protected=None):
    """Expire build-only roots independently of successful system generations."""
    directory = Path(config["rootsDirectory"]) / "dependencies"
    batches = sorted((path for path in directory.glob("*/*/*") if path.is_dir()),
                     key=lambda path: path.stat().st_mtime)
    cutoff = time.time() - config["dependencyMaxAgeDays"] * 86400
    for batch in list(batches):
        if batch != protected and batch.stat().st_mtime < cutoff:
            shutil.rmtree(batch)
            batches.remove(batch)
    while batches:
        roots = dependency_roots(directory)
        info = path_info(config, roots) if roots else {}
        retained_bytes = sum(entry["narSize"] for entry in info.values())
        if retained_bytes <= config["dependencyBudgetBytes"]:
            return retained_bytes
        oldest = next((batch for batch in batches if batch != protected), None)
        if oldest is None:
            raise ValueError("One dependency batch exceeds the retention budget")
        shutil.rmtree(oldest)
        batches.remove(oldest)
    return 0


def retain_dependencies(config, group, generation, paths):
    if group not in config["dependencyGroups"] or not GENERATION.fullmatch(generation):
        raise ValueError("Invalid dependency group or generation")
    if not isinstance(paths, list) or not 1 <= len(paths) <= 20000:
        raise ValueError("Expected 1 to 20000 dependency outputs")
    if any(not isinstance(path, str) or not STORE_PATH.fullmatch(path) or path.endswith(".drv")
           for path in paths):
        raise ValueError("Expected store outputs, never derivations")
    paths = sorted(set(paths))
    roots = Path(config["rootsDirectory"])
    with (roots / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        check_space(config)
        batch = roots / "dependencies" / group / generation / closure_digest(paths)
        created = not batch.exists()
        batch.mkdir(parents=True, exist_ok=True)
        try:
            if created:
                for offset in range(0, len(paths), 128):
                    run(config["nixStore"], "--realise", *paths[offset:offset + 128],
                        "--add-root", str(batch / f"root-{offset}"),
                        "--option", "substitute", "false", "--option", "max-jobs", "0")
            info = path_info(config, paths)
            size = sum(entry["narSize"] for entry in info.values())
            if size > config["dependencyBudgetBytes"]:
                raise ValueError("One dependency batch exceeds the retention budget")
            os.utime(batch)
            retained_bytes = prune_dependencies(config, protected=batch)
        except Exception:
            if created:
                shutil.rmtree(batch)
            raise
        return {"group": group, "generation": generation,
                "closureDigest": closure_digest(info), "closurePaths": len(info),
                "closureBytes": size, "retainedBytes": retained_bytes}


def dispatch(config, command):
    if len(command) > 4096:
        raise ValueError("Command too long")
    args = shlex.split(command)
    if args == ["nix-store", "--serve", "--write"]:
        check_space(config)
        os.execv(config["nixStore"], [config["nixStore"], "--serve", "--write"])
    elif len(args) == 2 and args[0] == "cache-preflight" and re.fullmatch(r"[0-9]{1,15}", args[1]):
        return {"availableBytes": check_space(config, int(args[1]))}
    elif len(args) == 4 and args[0] == "cache-publish":
        return publish(config, *args[1:])
    elif len(args) == 3 and args[0] == "cache-retain":
        payload = sys.stdin.read(8 * 1024 * 1024 + 1)
        if len(payload) > 8 * 1024 * 1024:
            raise ValueError("Dependency manifest too large")
        return retain_dependencies(config, *args[1:], json.loads(payload))
    else:
        raise ValueError("Only Nix store transfer, preflight and generation publication are allowed")


def main():
    config = json.loads(Path(sys.argv[1]).read_text())
    # SSH does not accept client environment variables; also discard inherited
    # Nix overrides so this untrusted account always connects to the daemon.
    for name in list(os.environ):
        if name.startswith("NIX_"):
            del os.environ[name]
    os.environ["NIX_REMOTE"] = "daemon"
    try:
        # Local systemd maintenance only; this is not exposed over SSH.
        if sys.argv[2:] == ["--prune-dependencies"]:
            with (Path(config["rootsDirectory"]) / ".lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                prune_dependencies(config)
            return
        result = dispatch(config, os.environ.get("SSH_ORIGINAL_COMMAND", ""))
        print(json.dumps(result, sort_keys=True))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Cache request failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
