#!/usr/bin/env python3

import re
import subprocess
import sys
import os
from pathlib import Path


SEMVER_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)([-+].+)?$")
PGVECTO_RE = re.compile(r"^pg(\d+)-v(\d+)\.(\d+)\.(\d+)([-+].+)?$")
IMAGE_RE = re.compile(r"^\s*image:\s*['\"]?([^'\"\s]+)['\"]?\s*$")


def run(cmd):
    return subprocess.run(cmd, check=False, capture_output=True, text=True)


def parse_image_ref(ref):
    without_digest = ref.split("@", 1)[0]
    parts = without_digest.split("/")
    first = parts[0]

    if "." in first or ":" in first or first == "localhost":
        registry = first
        remainder = "/".join(parts[1:])
    else:
        registry = "docker.io"
        remainder = without_digest

    if ":" in remainder.rsplit("/", 1)[-1]:
        repo, tag = remainder.rsplit(":", 1)
    else:
        repo, tag = remainder, "latest"

    if registry == "docker.io" and "/" not in repo:
        repo = f"library/{repo}"

    return registry, repo, tag


def semver_key(tag):
    m = SEMVER_RE.match(tag)
    if not m:
        m2 = PGVECTO_RE.match(tag)
        if not m2:
            return None
        pg_major, major, minor, patch, suffix = m2.groups()
        return int(major), int(minor), int(patch), suffix or "", int(pg_major)
    major, minor, patch, suffix = m.groups()
    return int(major), int(minor), int(patch), suffix or "", None


def extract_images(result_dir):
    images = set()
    root = Path(result_dir).resolve()
    for dirpath, _, filenames in os.walk(root, followlinks=True):
        for filename in filenames:
            if not (filename.endswith(".yaml") or filename.endswith(".yml")):
                continue
            path = Path(dirpath) / filename
            try:
                text = path.read_text()
            except UnicodeDecodeError:
                continue
            for line in text.splitlines():
                m = IMAGE_RE.match(line)
                if m:
                    images.add(m.group(1))
    return sorted(images)


def list_tags(registry_repo, cache):
    if registry_repo in cache:
        return cache[registry_repo]

    result = run(["nix", "run", "nixpkgs#crane", "--", "ls", registry_repo])
    if result.returncode != 0:
        cache[registry_repo] = None
        return None

    tags = [t.strip() for t in result.stdout.splitlines() if t.strip()]
    cache[registry_repo] = tags
    return tags


def newest_tag(current, tags):
    current_key = semver_key(current)
    if current_key is None:
        return None

    suffix = current_key[3]
    track = current_key[4]
    candidates = []
    for tag in tags:
        key = semver_key(tag)
        if key is None:
            continue
        if key[3] != suffix:
            continue
        if key[4] != track:
            continue
        candidates.append((key, tag))

    if not candidates:
        return None

    candidates.sort(key=lambda x: x[0])
    top_key, top_tag = candidates[-1]
    if top_key > current_key:
        return top_tag
    return None


def main():
    if len(sys.argv) != 2:
        print("Usage: check-images.py <result-dir>")
        return 2

    result_dir = Path(sys.argv[1])
    if not result_dir.exists():
        print(f"Result directory not found: {result_dir}")
        return 2

    images = extract_images(result_dir)
    if not images:
        print("No image references found in rendered manifests.")
        return 0

    cache = {}
    outdated = 0
    skipped = 0

    print(f"Found {len(images)} unique images in {result_dir}")
    print()

    for image in images:
        registry, repo, current_tag = parse_image_ref(image)
        registry_repo = f"{registry}/{repo}"

        if current_tag == "latest":
            skipped += 1
            print(f"SKIP  {image} (latest tag)")
            continue

        if semver_key(current_tag) is None:
            skipped += 1
            print(f"SKIP  {image} (non-semver tag)")
            continue

        tags = list_tags(registry_repo, cache)
        if tags is None:
            skipped += 1
            print(f"SKIP  {image} (failed to query tags)")
            continue

        newer = newest_tag(current_tag, tags)
        if newer is None:
            print(f"OK    {image}")
        else:
            outdated += 1
            print(f"OLD   {image} -> {registry_repo}:{newer}")

    print()
    print(f"Outdated: {outdated}")
    print(f"Skipped:  {skipped}")

    return 1 if outdated > 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
