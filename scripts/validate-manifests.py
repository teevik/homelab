#!/usr/bin/env python3
"""Check deployment invariants in the complete nixidy output."""

import argparse
import json
import os
import sys
from pathlib import Path

import yaml


def resources(root):
    # nixidy's build output contains directory symlinks.
    for directory, _, files in os.walk(root, followlinks=True):
        for filename in sorted(files):
            if filename.endswith((".yaml", ".yml")):
                path = Path(directory) / filename
                for resource in yaml.safe_load_all(path.read_text()):
                    if resource is not None:
                        yield resource


def identity(resource):
    metadata = resource.get("metadata", {})
    return "/".join(
        (metadata.get("namespace", "default"), resource["kind"], metadata["name"])
    )


def annotations(resource):
    return resource.get("metadata", {}).get("annotations", {})


def pod_template(resource):
    if resource["kind"] == "Pod":
        return resource
    if resource.get("apiVersion", "").startswith("operator.victoriametrics.com/"):
        # These operator CRs expose pod overrides directly on spec.
        return resource
    if resource["kind"] == "CronJob":
        return resource["spec"]["jobTemplate"]["spec"]["template"]
    return resource.get("spec", {}).get("template", {})


def validate(objects, policy):
    errors = []
    indexed = {identity(resource): resource for resource in objects}
    if len(indexed) != len(objects):
        errors.append("duplicate resource identities")
    for name, expected in policy.get("persistentVolumes", {}).items():
        pvc = indexed.get(name)
        if pvc is None:
            errors.append(f"{name}: required persistent volume is missing or renamed")
            continue
        if pvc["spec"].get("storageClassName") != expected["storageClassName"]:
            errors.append(f"{name}: storageClassName changed")
        if expected.get("backup"):
            labels = pvc["metadata"].get("labels", {})
            for label in (
                "recurring-job.longhorn.io/source",
                "recurring-job-group.longhorn.io/backup",
            ):
                if labels.get(label) != "enabled":
                    errors.append(f"{name}: required backup label {label} is missing")
    for resource in objects:
        name = identity(resource)
        meta = annotations(resource)
        if (
            "homelab.teevik.dev/image-builds" in meta
            and meta.get("argocd.argoproj.io/hook") != "PreSync"
        ):
            errors.append(f"{name}: image build must run as a PreSync hook")
        exceptions = policy.get("exceptions", {})
        pod = pod_template(resource).get("spec", {})
        for field in ("hostNetwork", "hostPID", "hostIPC"):
            if pod.get(field) and name not in exceptions.get(field, []):
                errors.append(f"{name}: unexpected {field}")
        for volume in pod.get("volumes", []):
            path = volume.get("hostPath", {}).get("path")
            if path is not None and path not in exceptions.get("hostPaths", {}).get(
                name, []
            ):
                errors.append(f"{name}: unexpected hostPath {path}")
        for container in pod.get("containers", []) + pod.get("initContainers", []):
            container_name = f"{name}/{container['name']}"
            if container.get("securityContext", {}).get(
                "privileged"
            ) and container_name not in exceptions.get("privileged", []):
                errors.append(f"{container_name}: unexpected privileged container")
        if meta.get("tailscale.com/funnel") == "true" and name not in exceptions.get(
            "funnel", []
        ):
            errors.append(f"{name}: unexpected public Tailscale Funnel")
        if resource["kind"] == "Service":
            spec = resource["spec"]
            if (
                spec.get("externalIPs")
                or spec.get("type") == "NodePort"
                or (
                    spec.get("type") == "LoadBalancer"
                    and spec.get("loadBalancerClass") != "tailscale"
                )
            ):
                errors.append(f"{name}: unexpected externally exposed Service")
        hooks = {value.strip() for value in meta.get("helm.sh/hook", "").split(",")}
        if resource["kind"] == "Job" and hooks & {"pre-delete", "post-delete"}:
            errors.append(f"{name}: forbidden Helm pre-delete/post-delete hook")
        if (
            resource["kind"] == "Job"
            and meta.get("argocd.argoproj.io/hook") == "PreSync"
        ):
            namespace = resource["metadata"].get("namespace", "default")
            pod = pod_template(resource).get("spec", {})
            dependencies = set(policy.get("preSyncDependencies", {}).get(name, []))
            for volume in pod.get("volumes", []):
                if "configMap" in volume:
                    dependencies.add(
                        f"{namespace}/ConfigMap/{volume['configMap']['name']}"
                    )
            for container in pod.get("containers", []) + pod.get("initContainers", []):
                for env in container.get("env", []):
                    ref = env.get("valueFrom", {}).get("configMapKeyRef")
                    if ref:
                        dependencies.add(f"{namespace}/ConfigMap/{ref['name']}")
                for env in container.get("envFrom", []):
                    if "configMapRef" in env:
                        dependencies.add(
                            f"{namespace}/ConfigMap/{env['configMapRef']['name']}"
                        )
            for dependency in sorted(dependencies):
                other = indexed.get(dependency)
                if other is None:
                    errors.append(f"{name}: missing PreSync dependency {dependency}")
                elif annotations(other).get(
                    "argocd.argoproj.io/hook"
                ) != "PreSync" or int(
                    annotations(other).get("argocd.argoproj.io/sync-wave", "0")
                ) >= int(meta.get("argocd.argoproj.io/sync-wave", "0")):
                    errors.append(
                        f"{name}: {dependency} must be a PreSync hook in an earlier wave"
                    )
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path)
    parser.add_argument("--policy", required=True, type=Path)
    args = parser.parse_args()
    objects = list(resources(args.manifests))
    if not objects:
        parser.error("no manifests found")
    errors = validate(objects, json.loads(args.policy.read_text()))
    for error in errors:
        print(error)
    print(f"Checked {len(objects)} resources; {len(errors)} invariant failures")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
