#!/usr/bin/env python3
"""Verify that CI rebuilds changed sources, including unchanged image tags."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


class ImageBuildSelection(unittest.TestCase):
    def test_context_change_requires_build_even_with_unchanged_tag(self):
        with tempfile.TemporaryDirectory() as directory:
            base, candidate = Path(directory) / "base", Path(directory) / "candidate"
            base.mkdir()
            candidate.mkdir()
            job = {
                "apiVersion": "batch/v1",
                "kind": "Job",
                "metadata": {
                    "namespace": "app",
                    "name": "build",
                    "annotations": {
                        "homelab.teevik.dev/image-builds": json.dumps(
                            [
                                {
                                    "image": "app",
                                    "tag": "fixed",
                                    "context": "/workspace",
                                },
                            ]
                        ),
                    },
                },
                "spec": {
                    "template": {
                        "spec": {
                            "containers": [
                                {
                                    "name": "buildkit",
                                    "volumeMounts": [
                                        {"name": "context", "mountPath": "/workspace"},
                                    ],
                                }
                            ],
                            "volumes": [
                                {"name": "context", "configMap": {"name": "context"}}
                            ],
                        }
                    }
                },
            }
            context = {
                "apiVersion": "v1",
                "kind": "ConfigMap",
                "metadata": {
                    "namespace": "app",
                    "name": "context",
                },
                "data": {"Dockerfile": "FROM example:1\n"},
            }
            for root in (base, candidate):
                (root / "resources.yaml").write_text(yaml.safe_dump_all([job, context]))
            command = [
                sys.executable,
                str(Path(__file__).with_name("build-images.py")),
                str(candidate),
                "--base",
                str(base),
                "--list",
            ]
            unchanged = subprocess.run(
                command, capture_output=True, text=True, check=True
            )
            self.assertEqual(json.loads(unchanged.stdout), [])
            context["data"]["Dockerfile"] = "FROM example:2\n"
            (candidate / "resources.yaml").write_text(
                yaml.safe_dump_all([job, context])
            )
            changed = subprocess.run(
                command, capture_output=True, text=True, check=True
            )
            self.assertEqual(json.loads(changed.stdout), ["app/app"])


if __name__ == "__main__":
    unittest.main()
