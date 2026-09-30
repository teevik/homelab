//! Freshness, coverage and recovery boundaries through the same seam: catalog +
//! snapshot + explicit time in, status and frame out.
mod common;

use common::*;
use health_dashboard::contract::*;
use health_dashboard::fixtures::{self, Fixture, Scenario, ago, fail};
use health_dashboard::health::Status;
use jiff::{SignedDuration, Timestamp};

fn status(f: &Fixture, now: Timestamp) -> Status {
    dashboard(f).health(now).status
}

fn screen(f: &Fixture, now: Timestamp) -> Screen {
    draw(&mut dashboard(f), 160, 50, now)
}

fn normal() -> Fixture {
    fixtures::fixture(Scenario::Normal)
}

fn secs(n: i64) -> SignedDuration {
    SignedDuration::from_secs(n)
}

#[test]
fn a_source_exactly_three_minutes_old_is_current_and_older_is_stale() {
    let f = normal();
    // the http source's newest sample is 21s old at f.now
    let at_boundary = f.now + secs(180 - 21);
    let mut f = f;
    for src in [&mut f.snapshot.sources.host, &mut f.snapshot.sources.argo, &mut f.snapshot.sources.alerts] {
        src.newest_sample_at = f.snapshot.sources.http.newest_sample_at;
    }
    for e in f.snapshot.endpoints.values_mut() {
        e.observed_at = ago(f.now, 21);
    }
    for a in f.snapshot.apps.values_mut() {
        a.observed_at = ago(f.now, 21);
    }
    assert_eq!(status(&f, at_boundary), Status::AllClear);
    assert_eq!(status(&f, at_boundary + SignedDuration::from_nanos(1)), Status::Unknown);
    assert!(screen(&f, at_boundary + secs(1)).contains("STALE · newest sample 3m old"));
}

#[test]
fn a_failed_refresh_removes_all_clear_immediately() {
    let mut f = normal();
    f.snapshot.sources.argo.failure = Some(Failure { since: f.now, reason: "argo cd query returned HTTP 503".into() });
    assert_eq!(status(&f, f.now), Status::Unknown);
    let s = screen(&f, f.now);
    assert!(s.contains("argo cd unavailable for 0s"));
    assert!(s.contains("argo cd query returned HTTP 503"));
}

#[test]
fn a_valid_refresh_recovers_without_a_restart() {
    let mut f = normal();
    let mut d = dashboard(&f);
    let mut broken = f.snapshot.clone();
    broken.sources.http.failure = Some(Failure { since: f.now, reason: "probe query timed out".into() });
    d.set_snapshot(broken);
    assert_eq!(d.health(f.now).status, Status::Unknown);
    f.snapshot.sources.http.newest_sample_at = Some(f.now);
    d.set_snapshot(f.snapshot.clone());
    assert_eq!(d.health(f.now + secs(1)).status, Status::AllClear);
}

#[test]
fn an_old_expected_result_is_a_gap_even_when_its_source_is_fresh() {
    let mut f = normal();
    f.snapshot.endpoints.get_mut("reclip").unwrap().observed_at = ago(f.now, 250);
    f.snapshot.apps.get_mut("glance-agent").unwrap().observed_at = ago(f.now, 250);
    assert_eq!(status(&f, f.now), Status::Unknown);
    let s = screen(&f, f.now);
    assert!(s.line(12).contains("? Reclip") && s.line(12).contains("check result 4m old"), "{}", s.line(12));
    assert!(s.line(13).contains("? glance-agent") && s.line(13).contains("argo cd report 4m old"));
    let reclip = (19..50).find(|&y| s.line(y).contains(" Reclip ")).expect("ledger row");
    assert!(s.line(reclip).contains("4m old"));
    assert_eq!(s.fg((24, reclip)), health_dashboard::palette::META, "the old ok is retained, not green");
    assert!(!s.text().contains("signal"));
}

#[test]
fn coverage_gaps_never_count_as_signals() {
    let mut f = fixtures::fixture(Scenario::Missing);
    fail(&mut f, "glance", "HTTP 500", 60);
    let s = screen(&f, f.now);
    assert!(s.contains("1 signal on 1 service"));
    let h = dashboard(&f).health(f.now);
    assert_eq!((h.signals, h.gap_endpoints, h.gap_apps), (1, 1, 1));
}

#[test]
fn a_known_failure_stays_visible_through_an_outage() {
    let mut f = fixtures::fixture(Scenario::OneHttp);
    f.snapshot.sources.http.failure = Some(Failure { since: ago(f.now, 60), reason: "probe query timed out".into() });
    assert_eq!(status(&f, f.now), Status::Attention);
    let s = screen(&f, f.now);
    assert!(s.line(12).contains("■ Reclip") && s.line(12).contains("HTTP 502"));
    assert_eq!(s.fg(s.at("HTTP 502 ")), health_dashboard::palette::FAIL);
}

#[test]
fn losing_the_collector_keeps_known_failures_and_invents_no_recovery() {
    let f = fixtures::fixture(Scenario::OneHttp);
    let mut d = dashboard(&f);
    assert!(d.snapshot_lost(f.now, "collector snapshot unreadable: expected value at line 1"));
    let h = d.health(f.now + secs(5));
    assert_eq!(h.status, Status::Attention);
    assert!(h.recoveries.is_empty());
    let s = draw(&mut d, 160, 50, f.now + secs(5));
    assert!(s.line(12).contains("■ Reclip"));
    assert_eq!(s.text().matches("collector snapshot unreadable").count(), 1);
    // repeated failures keep their onset
    assert!(!d.snapshot_lost(f.now + secs(1), "collector snapshot unreadable: expected value at line 1"));
}

#[test]
fn a_lost_collector_never_leaves_a_frozen_all_clear() {
    let f = normal();
    let mut d = dashboard(&f);
    d.snapshot_lost(f.now, "no collector snapshot; is the collector running?");
    assert_eq!(d.health(f.now).status, Status::Unknown);
    let s = draw(&mut d, 160, 50, f.now);
    assert!(s.contains("every source unavailable for 0s"));
    assert!(s.contains("no source is current"));
}

#[test]
fn a_restarted_collector_is_shown_as_a_cold_start() {
    let f = normal();
    let mut d = dashboard(&f);
    d.snapshot_lost(f.now, "no collector snapshot; is the collector running?");
    let restarted = fixtures::cold_start(f.now + secs(30));
    d.set_snapshot(restarted.snapshot);
    let s = draw(&mut d, 160, 50, restarted.now);
    assert!(s.contains("starting, waiting for first readings (4s)"));
    assert!(!s.contains("no collector snapshot"));
}

#[test]
fn host_freshness_is_required_for_all_clear() {
    let mut f = normal();
    f.snapshot.sources.host.newest_sample_at = Some(ago(f.now, 200));
    assert_eq!(status(&f, f.now), Status::Unknown);
    assert!(screen(&f, f.now).contains("host readings stale, newest sample 3m old"));

    let mut f = normal();
    f.snapshot.sources.host = SourceReport::default();
    let s = screen(&f, f.now);
    assert!(s.contains("waiting for host readings"));
    assert!(s.contains("partial coverage: host waiting"));
}

#[test]
fn no_incomplete_coverage_ever_reads_all_clear() {
    let base = normal();
    let states: [fn(Timestamp) -> SourceReport; 3] = [
        |_| SourceReport::default(),
        |now| SourceReport { newest_sample_at: Some(ago(now, 181)), failure: None },
        |now| SourceReport { newest_sample_at: Some(ago(now, 5)), failure: Some(Failure { since: now, reason: "refused".into() }) },
    ];
    for which in 0..4 {
        for state in states {
            let mut f = normal();
            let s = &mut f.snapshot.sources;
            *[&mut s.host, &mut s.http, &mut s.argo, &mut s.alerts][which] = state(f.now);
            assert_eq!(status(&f, f.now), Status::Unknown, "source {which}");
        }
    }
    for id in base.snapshot.endpoints.keys() {
        let mut f = normal();
        f.snapshot.endpoints.remove(id);
        assert_eq!(status(&f, f.now), Status::Unknown, "endpoint {id}");
    }
    for id in base.snapshot.apps.keys() {
        let mut f = normal();
        f.snapshot.apps.remove(id);
        assert_eq!(status(&f, f.now), Status::Unknown, "app {id}");
    }
}

#[test]
fn an_absent_temperature_never_decides_status() {
    let mut f = normal();
    f.snapshot.host.temperature = Temperature::Waiting;
    f.snapshot.host.temperature_history = TemperatureHistory::default();
    assert_eq!(status(&f, f.now), Status::AllClear);
    assert!(screen(&f, f.now).contains("waiting for the first reading"));
}

#[test]
fn recoveries_show_for_fifteen_minutes_then_leave() {
    let mut f = fixtures::fixture(Scenario::Recovered);
    let fifteen = SignedDuration::from_mins(15);
    f.snapshot.recoveries[0].cleared_at = f.now - fifteen + secs(1);
    assert!(screen(&f, f.now).line(13).contains("Registry"));
    assert_eq!(dashboard(&f).next_redraw(f.now), f.now + secs(1), "the frame is redrawn when it leaves");
    f.snapshot.recoveries[0].cleared_at = f.now - fifteen;
    let later = screen(&f, f.now);
    assert!(!later.contains("recovered"));
    assert!(later.line(12).contains("Nothing needs attention."));
    // at most three, most recent first
    f.snapshot.recoveries[0].cleared_at = ago(f.now, 4 * 60);
    for (i, id) in ["glance", "immich", "amp"].into_iter().enumerate() {
        let now = f.now;
        f.snapshot.recoveries.push(Recovery { service: id.into(), problem: "HTTP 502".into(), began_at: ago(now, 600), cleared_at: ago(now, 60 * i as i64) });
    }
    let s = screen(&f, f.now);
    assert!(s.line(13).contains("Glance") && s.line(14).contains("Immich") && s.line(15).contains("AMP"));
    assert!((12..16).all(|y| !s.line(y).contains("Registry")), "the oldest of four is not shown");
}

#[test]
fn distinct_failure_causes_each_get_one_reason_line() {
    let mut f = normal();
    let s = &mut f.snapshot.sources;
    s.http.failure = Some(Failure { since: f.now, reason: "cluster API rejected the collector credential (HTTP 401)".into() });
    s.argo.failure = s.http.failure.clone();
    s.alerts.failure = Some(Failure { since: f.now, reason: "alertmanager request timed out (5s)".into() });
    let text = screen(&f, f.now).text();
    assert_eq!(text.matches("(HTTP 401)").count(), 1);
    assert_eq!(text.matches("timed out (5s)").count(), 1);
}

#[test]
fn a_signal_without_a_reported_onset_invents_none() {
    let mut f = normal();
    let now = f.now;
    let app = f.snapshot.apps.get_mut("registry").unwrap();
    app.health = "Degraded".into();
    app.health_since = None;
    let s = screen(&f, now);
    let row = s.line(12);
    assert!(row.contains("▲ Registry") && row.contains("app Degraded"), "{row}");
    assert!(!row.contains("since"), "no onset was reported: {row}");
    fixtures::alert(&mut f, "KubeDeploymentReplicasMismatch", Some("registry"), None, 300);
    assert!(screen(&f, now).line(12).trim_end().ends_with("since 5m"), "a reported onset still counts");
}

#[test]
fn unmatched_evidence_keeps_its_label() {
    let mut f = normal();
    let now = f.now;
    f.snapshot.workloads.push(WorkloadSignal { app: None, label: Some("kube-system".into()), problem: WorkloadProblem::Unready { count: 2 }, since: ago(now, 120) });
    f.snapshot.alerts.push(AlertSignal { name: "KubeletDown".into(), app: Some("not-in-catalog".into()), label: None, since: ago(now, 60) });
    let s = screen(&f, now);
    assert!(s.contains("2 signals on the cluster"));
    let rows: Vec<String> = (12..16).map(|y| s.line(y)).collect();
    assert!(rows[0].contains("! not-in-catalog") && rows[0].contains("alert KubeletDown"), "alert tier before deployment tier");
    assert!(rows[1].contains("▲ kube-system") && rows[1].contains("2 workloads unready"));
}
