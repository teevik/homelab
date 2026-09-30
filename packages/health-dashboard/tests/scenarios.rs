//! The 15 approved scenarios (teevik/homelab#71), rendered at the target 160x50.
//! Expected wording, counts and order come from the approved evidence.
mod common;

use common::*;
use health_dashboard::fixtures::Scenario;
use health_dashboard::palette::*;

/// The attention slot: rows 12-15, trailing space trimmed.
fn slot(s: &Screen) -> Vec<String> {
    (12..16).map(|y| s.line(y).trim_end().to_string()).collect()
}

/// The summary column, anchored right of the ATTENTION-wide status word.
fn summary(s: &Screen) -> String {
    (3..10)
        .map(|y| s.line(y).chars().skip(111).collect::<String>().trim().to_string())
        .filter(|l| !l.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

fn assert_all_clear(s: &Screen) {
    assert_eq!(status_colours(s), (OK, GROUND));
    assert_eq!(s.fg(s.at("every check passes")), TEXT);
    assert!(s.line(12).contains("Nothing needs attention."));
}

#[test]
fn every_scenario_is_console_safe() {
    for sc in Scenario::ALL {
        render(sc).assert_console_safe();
    }
}

#[test]
fn normal_reads_all_clear_with_complete_coverage() {
    let s = render(Scenario::Normal);
    assert_all_clear(&s);
    let sum = summary(&s);
    for line in ["16 of 16 endpoints respond", "18 of 18 apps synced and healthy", "no active alerts", "all sources current, oldest 21s"] {
        assert!(sum.contains(line), "{line:?} missing from\n{sum}");
    }
    assert_eq!(s.fg(s.at("all sources current")), META);
    assert!(s.line(0).starts_with(" HOMELAB  host health"));
    assert!(s.line(0).trim_end().ends_with("Wed 30 Sep  21:42"));
    assert!(s.line(49).starts_with(" Ctrl+C close, monitoring keeps running"));
    assert!(!s.contains("scroll services"));
    assert!(s.line(49).trim_end().ends_with("screen dark 23:00-08:00, in 1h 18m"));
    assert_eq!(s.fg(s.at("screen dark")), COOL);
}

#[test]
fn one_http_failure_is_one_signal_on_one_service() {
    let s = render(Scenario::OneHttp);
    assert_eq!(status_colours(&s), (TEXT, ALERT_GROUND));
    assert!(summary(&s).starts_with("1 signal on 1 service\n1 of 16 endpoints failing"));
    let row = &slot(&s)[0];
    assert!(row.starts_with("   ■ Reclip"), "{row}");
    assert!(row.contains("HTTP 502") && row.ends_with("since 3m"), "{row}");
    assert_eq!(s.fg(s.at("■ Reclip")), FAIL);
    // the failing ledger row keeps full strength on the attention ground
    let (x, y) = s.at("HTTP 502  ");
    assert_eq!(y, 12);
    let ledger = s.lines().iter().position(|l| l.contains("Reclip") && l.contains("for 3m")).unwrap() as u16;
    assert_eq!(s.bg((5, ledger)), ALERT_GROUND);
    assert_eq!(s.fg((24, ledger)), FAIL);
    let _ = x;
}

#[test]
fn mixed_signals_are_counted_tiered_and_ordered() {
    let s = render(Scenario::Mixed);
    assert!(summary(&s).starts_with("8 signals on 3 services"));
    assert!(summary(&s).contains("2 of 18 apps unhealthy, 1 out of sync"));
    assert!(summary(&s).contains("2 active alerts"));
    let rows = slot(&s);
    assert!(rows[0].starts_with("   ■ Changedetection"));
    assert!(rows[0].contains("timeout 3.0s  ·  app Progressing  ·  5 restarts / 1h  ·  alert KubePodCrashLooping"), "{}", rows[0]);
    assert!(rows[0].ends_with("since 12m"), "the oldest signal sets since: {}", rows[0]);
    assert!(rows[1].starts_with("   ■ Registry") && rows[1].contains("HTTP 503  ·  app Degraded  ·  alert KubeDeploymentReplicasMismatch"));
    assert!(rows[1].ends_with("since 5m"));
    assert!(rows[2].starts_with("   ▲ Paperless-ngx") && rows[2].contains("app OutOfSync  ·  endpoint ok"));
    assert_eq!(rows[3], "");
    // Degraded stays red; other deployment signals are mauve; alerts yellow
    assert_eq!(s.fg(s.at("app Degraded")), FAIL);
    assert_eq!(s.fg(s.at("app Progressing")), DEPLOY_HI);
    assert_eq!(s.fg(s.at("alert KubePodCrashLooping")), WARM);
    assert_eq!(s.fg(s.at("endpoint ok")), OK);
    assert_eq!(s.fg(s.at("▲ Paperless")), DEPLOY_HI);
}

#[test]
fn many_failures_show_three_rows_and_named_overflow() {
    let s = render(Scenario::ManyHttp);
    assert!(summary(&s).starts_with("9 signals on 8 services and the cluster"));
    let rows = slot(&s);
    for (row, name) in rows.iter().zip(["Glance", "Immich", "Grafana"]) {
        assert!(row.starts_with(&format!("   ■ {name}")), "{row}");
    }
    assert!(rows[3].starts_with("     +6 more:"), "{}", rows[3]);
    assert!(rows[3].contains("Paperless-ngx, AMP, ntfy, Immich Share, Reclip, cluster (highlighted below)"), "{}", rows[3]);
    assert_eq!(s.fg(s.at("+6 more")), WARM);
}

#[test]
fn deployment_problems_with_answering_endpoints_share_app_signals_once() {
    let s = render(Scenario::DeployOnly);
    assert!(summary(&s).starts_with("4 signals on 3 services"));
    let rows = slot(&s);
    assert!(rows[0].starts_with("   ▲ Immich ") && rows[0].contains("app Degraded  ·  2 restarts / 1h  ·  endpoint ok"), "{}", rows[0]);
    assert!(rows[1].starts_with("   ▲ Paperless-ngx"));
    assert!(rows[2].starts_with("   ▲ tailscale-operator") && rows[2].contains("app Progressing"));
    assert!(!rows[2].contains("endpoint ok"), "an app without an endpoint has no endpoint to answer");
    assert!(!s.text().contains("▲ Immich Share"), "immich's signals appear once, on its first endpoint");
}

#[test]
fn alerts_attach_to_their_app_or_stay_with_their_label() {
    let s = render(Scenario::Alerts);
    assert!(summary(&s).starts_with("2 signals on 1 service and the cluster"));
    let rows = slot(&s);
    assert!(rows[0].starts_with("   ! Immich") && rows[0].contains("alert KubePersistentVolumeFillingUp  ·  endpoint ok"));
    assert!(rows[0].ends_with("since 41m"));
    assert!(rows[1].starts_with("   ! cluster") && rows[1].contains("alert NodeClockNotSynchronising"));
    assert_eq!(s.fg(s.at("! Immich")), WARM);
}

#[test]
fn unavailable_monitoring_is_unknown_with_host_readings_current() {
    let s = render(Scenario::MonitoringDown);
    assert_eq!(status_colours(&s), (WARM, GROUND));
    assert_eq!(s.fg(s.at("cluster monitoring unavailable for 6m")), TEXT);
    let sum = summary(&s);
    for line in ["endpoints: no current results", "apps: no current status", "alerts: unknown, alertmanager unavailable", "host readings still current"] {
        assert!(sum.contains(line), "{line:?} missing from\n{sum}");
    }
    assert!(s.line(12).contains("No known problems, but health cannot be confirmed until every source is current."));
    assert!(s.line(17).contains("ENDPOINTS UNAVAILABLE 6m · last results"));
    // retained ok results lose their green
    let glance = s.at("Glance ");
    assert_eq!(s.fg(glance), META);
    assert_eq!(s.fg((24, glance.1)), META);
    assert_eq!(s.text().matches("cluster API rejected the collector credential (HTTP 401)").count(), 1, "one reason line per cause");
}

#[test]
fn a_known_failure_stays_attention_under_partial_coverage() {
    let s = render(Scenario::Partial);
    assert_eq!(s.bg((3, 2)), ALERT_GROUND);
    let sum = summary(&s);
    assert!(sum.starts_with("1 signal on 1 service"));
    assert!(sum.contains("alerts: unknown, alertmanager unavailable"));
    assert!(sum.contains("partial coverage: alerts unavailable"));
    assert!(slot(&s)[0].starts_with("   ■ Registry"));
}

#[test]
fn missing_inventory_is_a_coverage_gap_not_a_signal() {
    let s = render(Scenario::Missing);
    assert_eq!(status_colours(&s), (WARM, GROUND));
    let sum = summary(&s);
    assert!(sum.starts_with("inventory incomplete, health cannot be confirmed"), "{sum}");
    assert!(sum.contains("15 of 16 endpoints respond, 1 without a result"));
    assert!(sum.contains("not reported"));
    assert!(sum.contains("partial coverage: catalog entries without data"));
    let rows = slot(&s);
    assert!(rows[0].starts_with("   ? Reclip") && rows[0].contains("no check result") && rows[0].ends_with("expected by catalog"));
    assert!(rows[1].starts_with("   ? glance-agent") && rows[1].contains("not reported by argo cd"));
    assert!(!sum.contains("signal"));
}

#[test]
fn stale_samples_withhold_all_clear_and_dim_retained_results() {
    let s = render(Scenario::Stale);
    assert!(summary(&s).starts_with("http checks stale, newest sample 4m old"));
    assert!(s.line(17).contains("STALE · newest sample 4m old"));
    assert_eq!(s.fg(s.at("STALE")), WARM);
    assert_eq!(s.fg(s.at("Glance ")), META);
    assert!(s.line(12).contains("No known problems"));
}

#[test]
fn a_recent_recovery_is_listed_without_changing_status() {
    let s = render(Scenario::Recovered);
    assert_all_clear(&s);
    let row = s.line(13);
    assert!(row.starts_with("   · Registry"), "{row}");
    assert!(row.contains("recovered  ·  was HTTP 503 for 14m  ·  ok since 21:38"), "{row}");
}

#[test]
fn an_absent_temperature_sensor_is_neutral() {
    let s = render(Scenario::NoTemp);
    assert_all_clear(&s);
    assert!(s.contains("unavailable"));
    assert!(s.contains("No CPU package sensor was found."));
    assert!(s.contains("This does not affect service health."));
}

#[test]
fn cold_start_waits_without_inventing_zeroes() {
    let s = render(Scenario::ColdStart);
    let sum = summary(&s);
    assert!(sum.starts_with("starting, waiting for first readings (4s)"), "{sum}");
    for line in ["endpoints: waiting for the first check", "apps: waiting for argo cd", "alerts: waiting for alertmanager", "host readings current"] {
        assert!(sum.contains(line), "{line:?} missing from\n{sum}");
    }
    assert!(s.line(12).contains("Waiting for first readings. Nothing is known to need attention yet."));
    let cpu = s.lines().iter().position(|l| l.contains("measuring")).expect("cpu measuring");
    assert!(s.line(cpu as u16).contains("--"));
    assert!(s.contains("no history yet, it builds from now"));
    assert!(s.line(0).trim_end().ends_with("12:04"));
    assert!(s.line(49).trim_end().ends_with("in 10h 56m"));
}

#[test]
fn night_wake_shows_the_controllers_reported_state() {
    let s = render(Scenario::NightWake);
    assert!(s.line(0).trim_end().ends_with("Thu 1 Oct  02:14"));
    assert!(s.line(49).trim_end().ends_with("quiet hours until 08:00 · woken, dark again at 02:24 (in 10m)"));
    let s = render(Scenario::BedtimeWake);
    assert!(s.line(49).trim_end().ends_with("bedtime until 08:00 · woken, dark again at 22:16 (in 10m)"));
}
