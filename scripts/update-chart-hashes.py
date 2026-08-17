#!/usr/bin/env python3

import re
import subprocess
import sys
import tempfile
from pathlib import Path

FIELD_PATTERNS = {
    "repo": re.compile(r'^\s*repo\s*=\s*"([^"]+)";\s*$', re.MULTILINE),
    "chart": re.compile(r'^\s*chart\s*=\s*"([^"]+)";\s*$', re.MULTILINE),
    "version": re.compile(r'^\s*version\s*=\s*"([^"]+)";\s*$', re.MULTILINE),
    "chartHash": re.compile(r'^\s*chartHash\s*=\s*"([^"]+)";\s*$', re.MULTILINE),
}
HASH_LINE_RE = re.compile(
    r'^(?P<prefix>\s*chartHash\s*=\s*)"[^"]+";\s*$', re.MULTILINE
)
YAML_FIELDS = {
    "name": re.compile(r"^name:\s*['\"]?([^'\"\s]+)['\"]?\s*$", re.MULTILINE),
    "version": re.compile(r"^version:\s*['\"]?([^'\"\s]+)['\"]?\s*$", re.MULTILINE),
}


def read_field(text: str, field: str, path: Path) -> str:
    matches = FIELD_PATTERNS[field].findall(text)
    if len(matches) != 1:
        raise ValueError(f"{path}: expected exactly one {field} field, found {len(matches)}")
    return matches[0]


def chart_files(arguments: list[str]) -> list[Path]:
    roots = [Path(argument) for argument in arguments] or [Path("charts")]
    files: set[Path] = set()
    for root in roots:
        if root.is_file():
            files.add(root)
        elif root.is_dir():
            files.update(root.rglob("default.nix"))
        else:
            raise FileNotFoundError(root)
    if not files:
        raise ValueError("no chart default.nix files found")
    return sorted(files)


def archive_identity(chart_dir: Path) -> tuple[str, str]:
    metadata_path = chart_dir / "Chart.yaml"
    metadata = metadata_path.read_text()
    values = {}
    for field, pattern in YAML_FIELDS.items():
        match = pattern.search(metadata)
        if match is None:
            raise ValueError(f"{metadata_path}: missing top-level {field}")
        values[field] = match.group(1)
    return values["name"], values["version"]


def refreshed(path: Path) -> tuple[str, str, str]:
    text = path.read_text()
    repo = read_field(text, "repo", path)
    chart = read_field(text, "chart", path)
    version = read_field(text, "version", path)
    current_hash = read_field(text, "chartHash", path)

    with tempfile.TemporaryDirectory(prefix="helm-chart-") as temporary:
        directory = Path(temporary)
        subprocess.run(
            [
                "helm",
                "pull",
                chart,
                "--repo",
                repo,
                "--version",
                version,
                "--destination",
                str(directory),
                "--untar",
            ],
            check=True,
        )
        unpacked = directory / chart
        actual_chart, actual_version = archive_identity(unpacked)
        if actual_chart != chart or actual_version != version:
            raise ValueError(
                f"{path}: requested {chart} {version}, received "
                f"{actual_chart} {actual_version}"
            )
        chart_hash = subprocess.run(
            ["nix", "hash", "path", "--type", "sha256", "--sri", str(unpacked)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    if chart_hash == current_hash:
        return text, chart_hash, "current"

    updated, replacements = HASH_LINE_RE.subn(
        lambda match: f'{match.group("prefix")}"{chart_hash}";', text
    )
    if replacements != 1:
        raise ValueError(f"{path}: expected exactly one chartHash replacement")
    return updated, chart_hash, "updated"


def main() -> int:
    pending = []
    for path in chart_files(sys.argv[1:]):
        updated, chart_hash, state = refreshed(path)
        pending.append((path, updated, chart_hash, state))

    for path, updated, chart_hash, state in pending:
        if state == "updated":
            temporary = path.with_suffix(".nix.tmp")
            temporary.write_text(updated)
            temporary.replace(path)
        print(f"{state}: {path} ({chart_hash})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
