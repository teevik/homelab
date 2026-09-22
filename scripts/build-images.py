#!/usr/bin/env python3
"""Build changed custom image sources locally without pushing to a registry."""

import argparse
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

import yaml


def plans(root):
    objects = []
    for directory, _, files in os.walk(root, followlinks=True):
        for filename in files:
            if filename.endswith((".yaml", ".yml")):
                objects.extend(
                    o
                    for o in yaml.safe_load_all(
                        (Path(directory) / filename).read_text()
                    )
                    if o
                )
    configmaps = {
        (o["metadata"].get("namespace", "default"), o["metadata"]["name"]): o
        for o in objects
        if o["kind"] == "ConfigMap"
    }
    result = {}
    for obj in objects:
        raw = (
            obj.get("metadata", {})
            .get("annotations", {})
            .get("homelab.teevik.dev/image-builds")
        )
        if raw is None:
            continue
        namespace = obj["metadata"].get("namespace", "default")
        pod = obj["spec"]["template"]["spec"]
        for build in json.loads(raw):
            files = None
            if build["context"] == "/workspace":
                volume_name = next(
                    m["name"]
                    for c in pod["containers"]
                    for m in c.get("volumeMounts", [])
                    if m["mountPath"] == "/workspace"
                )
                volume = next(v for v in pod["volumes"] if v["name"] == volume_name)
                files = configmaps[(namespace, volume["configMap"]["name"])]["data"]
            name = f"{namespace}/{build['image']}"
            if name in result:
                raise ValueError(f"duplicate build plan: {name}")
            result[name] = {"build": build, "files": files}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path)
    parser.add_argument(
        "--base", type=Path, help="Only build plans changed from these manifests"
    )
    parser.add_argument(
        "--list", action="store_true", help="Print changed image names as JSON"
    )
    parser.add_argument("--image", help="Build one image from the plan")
    args = parser.parse_args()
    candidate = plans(args.manifests)
    if not candidate:
        parser.error("no annotated image build plans found")
    base = plans(args.base) if args.base else {}
    changed = sorted(name for name, plan in candidate.items() if plan != base.get(name))
    if args.list:
        print(json.dumps(changed))
        return
    for name in [args.image] if args.image else changed:
        plan = candidate[name]
        build = plan["build"]
        if not re.fullmatch(r"[a-z0-9][a-z0-9._/-]*", build["image"]):
            parser.error(f"invalid image name: {build['image']}")
        with tempfile.TemporaryDirectory(prefix="homelab-image-") as directory:
            context = build["context"]
            if plan["files"] is not None:
                context = directory
                for filename, content in plan["files"].items():
                    if Path(filename).name != filename:
                        parser.error(
                            f"build context key must be a filename: {filename}"
                        )
                    (Path(directory) / filename).write_text(content)
            subprocess.run(
                [
                    "docker",
                    "buildx",
                    "build",
                    "--load",
                    "--progress=plain",
                    "--platform=linux/amd64",
                    "--tag",
                    f"homelab-ci/{build['image']}:{build['tag']}",
                    context,
                ],
                check=True,
            )


if __name__ == "__main__":
    main()
