#!/usr/bin/env python3
"""Exercise manifest validation through its command-line interface."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


class ManifestChecks(unittest.TestCase):
    def check(self, objects, policy=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "resources.yaml").write_text(yaml.safe_dump_all(objects))
            policy_path = root / "policy.json"
            policy_path.write_text(json.dumps(policy or {}))
            return subprocess.run(
                [
                    sys.executable,
                    str(Path(__file__).with_name("validate-manifests.py")),
                    str(root),
                    "--policy",
                    str(policy_path),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

    def test_rejects_destructive_helm_hook(self):
        result = self.check(
            [
                {
                    "apiVersion": "batch/v1",
                    "kind": "Job",
                    "metadata": {
                        "name": "renamed-cleanup",
                        "annotations": {"helm.sh/hook": "pre-delete"},
                    },
                    "spec": {"template": {"spec": {"containers": []}}},
                }
            ]
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("pre-delete", result.stdout)

    def test_protects_persistent_data_when_chart_drops_backup_labels(self):
        pvc = {
            "apiVersion": "v1",
            "kind": "PersistentVolumeClaim",
            "metadata": {"name": "documents", "namespace": "paperless-ngx"},
            "spec": {"storageClassName": "longhorn"},
        }
        policy = {
            "persistentVolumes": {
                "paperless-ngx/PersistentVolumeClaim/documents": {
                    "storageClassName": "longhorn",
                    "backup": True,
                }
            }
        }
        result = self.check([pvc], policy)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("backup", result.stdout)
        pvc["metadata"]["labels"] = {
            "recurring-job.longhorn.io/source": "enabled",
            "recurring-job-group.longhorn.io/backup": "enabled",
        }
        result = self.check([pvc], policy)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_build_context_must_exist_before_presync_job(self):
        job = {
            "apiVersion": "batch/v1",
            "kind": "Job",
            "metadata": {
                "namespace": "app",
                "name": "build",
                "annotations": {
                    "argocd.argoproj.io/hook": "PreSync",
                },
            },
            "spec": {
                "template": {
                    "spec": {
                        "containers": [],
                        "volumes": [
                            {"name": "workspace", "configMap": {"name": "context"}},
                        ],
                    }
                }
            },
        }
        configmap = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {
                "namespace": "app",
                "name": "context",
            },
        }
        for objects in ([job], [job, configmap]):
            result = self.check(objects)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("app/ConfigMap/context", result.stdout)
        configmap["metadata"]["annotations"] = {
            "argocd.argoproj.io/hook": "PreSync",
            "argocd.argoproj.io/sync-wave": "-1",
        }
        result = self.check([job, configmap])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        job["metadata"]["annotations"]["homelab.teevik.dev/image-builds"] = "[]"
        job["metadata"]["annotations"]["argocd.argoproj.io/hook"] = "Sync"
        result = self.check([job, configmap])
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("image build must run as a PreSync hook", result.stdout)

    def test_rejects_new_privilege_and_accepts_specific_infrastructure_exception(self):
        deployment = {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {"namespace": "app", "name": "web"},
            "spec": {
                "template": {
                    "spec": {
                        "containers": [
                            {
                                "name": "web",
                                "image": "example:1",
                                "securityContext": {"privileged": True},
                            },
                        ]
                    }
                }
            },
        }
        result = self.check([deployment])
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("privileged", result.stdout)
        policy = {"exceptions": {"privileged": ["app/Deployment/web/web"]}}
        result = self.check([deployment], policy)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        deployment["spec"]["template"]["spec"]["hostNetwork"] = True
        result = self.check([deployment], policy)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("hostNetwork", result.stdout)

    def test_rejects_direct_operator_host_network_override(self):
        # These CRDs all define pod overrides directly under spec.
        for kind, version in (
            ("VMAgent", "v1beta1"),
            ("VMAlert", "v1beta1"),
            ("VMAlertmanager", "v1beta1"),
            ("VMAuth", "v1beta1"),
            ("VMSingle", "v1beta1"),
            ("VLAgent", "v1"),
            ("VLSingle", "v1"),
            ("VTSingle", "v1"),
            ("VMAnomaly", "v1"),
        ):
            with self.subTest(kind=kind):
                resource = {
                    "apiVersion": f"operator.victoriametrics.com/{version}",
                    "kind": kind,
                    "metadata": {"namespace": "monitoring", "name": "metrics"},
                    "spec": {"hostNetwork": True},
                }
                name = f"monitoring/{kind}/metrics"
                result = self.check([resource])
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn(f"{name}: unexpected hostNetwork", result.stdout)
                policy = {"exceptions": {"hostNetwork": [name]}}
                result = self.check([resource], policy)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                resource["metadata"]["name"] = "another-agent"
                result = self.check([resource], policy)
                self.assertEqual(result.returncode, 1, result.stderr)
                resource["spec"]["hostNetwork"] = False
                result = self.check([resource])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rejects_direct_operator_volume_and_container_overrides(self):
        for field, override, message, exception in (
            (
                "volumes",
                {"name": "host", "hostPath": {"path": "/"}},
                "unexpected hostPath /",
                {"hostPaths": {"monitoring/VMAgent/metrics": ["/"]}},
            ),
            (
                "containers",
                {"name": "sidecar", "securityContext": {"privileged": True}},
                "metrics/sidecar: unexpected privileged container",
                {"privileged": ["monitoring/VMAgent/metrics/sidecar"]},
            ),
            (
                "initContainers",
                {"name": "init", "securityContext": {"privileged": True}},
                "metrics/init: unexpected privileged container",
                {"privileged": ["monitoring/VMAgent/metrics/init"]},
            ),
        ):
            with self.subTest(field=field):
                resource = {
                    "apiVersion": "operator.victoriametrics.com/v1beta1",
                    "kind": "VMAgent",
                    "metadata": {"namespace": "monitoring", "name": "metrics"},
                    "spec": {field: [override]},
                }
                result = self.check([resource])
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn(message, result.stdout)
                result = self.check([resource], {"exceptions": exception})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
