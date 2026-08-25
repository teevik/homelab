#!/usr/bin/env python3

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DASHBOARD = ROOT / "kubernetes/dashboards/homelab-overview.json"
VICTORIA_METRICS = ROOT / "kubernetes/victoriametrics.nix"


def panel_by_id(dashboard, panel_id):
    return next(panel for panel in dashboard["panels"] if panel["id"] == panel_id)


def target_by_ref(panel, ref_id):
    return next(target for target in panel["targets"] if target["refId"] == ref_id)


def require(condition, message, failures):
    if not condition:
        failures.append(message)


def main():
    dashboard = json.loads(DASHBOARD.read_text())
    victoria_metrics = VICTORIA_METRICS.read_text()
    failures = []

    for panel_id in (14, 15):
        expr = target_by_ref(panel_by_id(dashboard, panel_id), "A")["expr"]
        require('job="kubelet"' in expr, f"panel {panel_id} must select the kubelet job", failures)
        require(
            'metrics_path="/metrics/cadvisor"' in expr,
            f"panel {panel_id} must select only cAdvisor container metrics",
            failures,
        )

    for panel_id, ref_id in ((18, "A"), (26, "D")):
        expr = target_by_ref(panel_by_id(dashboard, panel_id), ref_id)["expr"]
        require(
            'kubelet_volume_stats_used_bytes{job="kubelet"}' in expr,
            f"panel {panel_id}/{ref_id} must filter used-byte metrics to the kubelet job",
            failures,
        )
        require(
            'kubelet_volume_stats_capacity_bytes{job="kubelet"}' in expr,
            f"panel {panel_id}/{ref_id} must filter capacity metrics to the kubelet job",
            failures,
        )

    alert_panel = panel_by_id(dashboard, 17)
    require(
        alert_panel["options"]["datasource"] == "${datasource}",
        "panel 17 must query alert rules through the selected metrics datasource",
        failures,
    )

    backup_panel = panel_by_id(dashboard, 6)
    never_backed_up = target_by_ref(backup_panel, "B")["expr"] if len(backup_panel["targets"]) > 1 else ""
    require(
        "unless on (pvc, pvc_namespace)" in never_backed_up,
        "panel 6 must report backup-enabled volumes that have never backed up",
        failures,
    )

    require(
        '--collector.hwmon.chip-exclude=^platform_asus_nb_wmi$' in victoria_metrics,
        "node-exporter must exclude the duplicate ASUS WMI hwmon chip",
        failures,
    )

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1

    print("Monitoring configuration checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
