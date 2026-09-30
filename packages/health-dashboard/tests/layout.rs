//! Placement, overflow, fallbacks, fitting and redraw timing.
mod common;

use common::*;
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use health_dashboard::KeyOutcome;
use health_dashboard::contract::*;
use health_dashboard::fixtures::{self, Fixture, Scenario, ago, alert, fail};
use health_dashboard::palette::*;
use jiff::SignedDuration;

const SIZES: [(u16, u16); 9] = [(160, 50), (200, 60), (150, 45), (149, 45), (150, 44), (106, 33), (80, 25), (60, 20), (59, 19)];

fn key(code: KeyCode) -> KeyEvent {
    KeyEvent::from(code)
}

/// Twelve more host-only endpoints than today: the ledger no longer fits 160x50.
fn grown() -> Fixture {
    let mut f = fixtures::fixture(Scenario::Normal);
    for i in 1..=12 {
        let id = format!("extra-{i}");
        f.catalog.endpoints.push(CatalogEndpoint { id: id.clone(), name: format!("Extra {i}"), app: None });
        f.snapshot.endpoints.insert(id, EndpointResult { observed_at: ago(f.now, 21), check: Check::Ok { latency_ms: 5 } });
    }
    f
}

#[test]
fn every_scenario_at_every_size_is_console_safe() {
    for sc in Scenario::ALL {
        for (w, h) in SIZES {
            render_at(sc, w, h).assert_console_safe();
        }
    }
    for (w, h) in [(1, 1), (10, 2), (30, 5)] {
        render_at(Scenario::Mixed, w, h).assert_console_safe();
    }
}

#[test]
fn band_slot_rule_and_bars_stay_in_place() {
    for sc in Scenario::ALL {
        let s = render(sc);
        let ground = s.bg((0, 2));
        assert!((2..=10).all(|y| s.bg((0, y)) == ground && s.bg((159, y)) == ground), "{sc:?} status band rows 2-10");
        assert_eq!(s.bg((0, 11)), GROUND);
        assert_eq!(s.cols(16, 1, 159), "─".repeat(158), "{sc:?} rule on row 16");
        assert_eq!((s.bg((0, 0)), s.bg((0, 49))), (BAR, BAR), "{sc:?} header and footer");
        assert!(s.line(17).contains("ENDPOINTS") && s.line(17).contains("DEPLOYMENT") && s.line(17).contains("HOST"));
    }
}

#[test]
fn the_ledger_keeps_catalog_order_whatever_fails() {
    for sc in [Scenario::Normal, Scenario::Mixed, Scenario::ManyHttp] {
        let s = render(sc);
        let ys: Vec<u16> = fixtures::ENDPOINTS
            .iter()
            .map(|(_, name, _, _)| (19..48).find(|&y| s.cols(y, 0, 49).contains(&format!(" {name} "))).unwrap())
            .collect();
        assert!(ys.windows(2).all(|p| p[0] < p[1]), "{sc:?}: {ys:?}");
        // a gap every four endpoints
        assert_eq!(ys[4] - ys[3], 2);
    }
}

#[test]
fn mappings_are_explicit_in_the_ledger() {
    let s = render(Scenario::Normal);
    let row = |name: &str| (19..48).map(|y| s.line(y)).find(|l| l.chars().take(40).collect::<String>().contains(name)).unwrap();
    assert!(row("Grafana").contains("victoria-metrics"));
    assert!(row("Immich Share").contains("│ immich "));
    assert!(row("Nix Cache").contains("no app (host)"));
    let label = s.at("apps without an endpoint").1;
    for (i, app) in ["amd-device-plugin", "cloudflare-tunnel", "glance-agent", "tailscale-operator"].iter().enumerate() {
        assert!(s.line(label + 1 + i as u16).contains(app));
    }
}

#[test]
fn scrolling_moves_only_the_ledger_within_bounds() {
    let f = grown();
    let mut d = dashboard(&f);
    let top = draw(&mut d, 160, 50, f.now);
    assert!(top.contains("↓ 12 more rows"));
    assert!(!top.contains("above"));
    assert!(top.line(49).contains("↑↓ scroll services"));
    assert_eq!(d.key(key(KeyCode::Up)), KeyOutcome::Ignore, "nothing above the top");
    for _ in 0..50 {
        d.key(key(KeyCode::Down));
        draw(&mut d, 160, 50, f.now);
    }
    let bottom = draw(&mut d, 160, 50, f.now);
    assert!(bottom.contains("↑ 13 above"));
    assert!(!bottom.contains("more rows"));
    assert!(bottom.contains("tailscale-operator"));
    assert!(bottom.line(18).contains("service") && bottom.line(18).contains("latency"), "column headers stay");
    assert!(bottom.line(19).contains("↑ 13 above"));
    assert_eq!((0..17).map(|y| top.line(y)).collect::<Vec<_>>(), (0..17).map(|y| bottom.line(y)).collect::<Vec<_>>(), "status and attention never scroll");
    assert!(bottom.lines()[19..].iter().all(|l| !l.contains(" Glance ")));
}

#[test]
fn keys_other_than_scrolling_and_ctrl_c_are_ignored() {
    let f = fixtures::fixture(Scenario::Normal);
    let mut d = dashboard(&f);
    draw(&mut d, 160, 50, f.now);
    assert_eq!(d.key(KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL)), KeyOutcome::Exit);
    for code in [KeyCode::Char('q'), KeyCode::Esc, KeyCode::Left, KeyCode::Right, KeyCode::Down, KeyCode::Up] {
        assert_eq!(d.key(key(code)), KeyOutcome::Ignore, "{code:?} with nothing to scroll");
    }
}

#[test]
fn the_compact_fallback_starts_below_150x45() {
    for (w, h) in [(149, 45), (150, 44), (106, 33), (80, 25), (60, 20)] {
        let s = render_at(Scenario::Mixed, w, h);
        assert!(!s.contains("ENDPOINTS"), "{w}x{h} compact");
        assert!(s.contains("8 signals on 3 services"), "{w}x{h}");
        assert!(s.contains("apps  2 of 18 apps unhealthy, 1 out of sync"), "{w}x{h}:\n{}", s.text());
        assert!(s.line(h - 3).contains("cpu") && s.line(h - 3).contains("mem"));
        assert!(s.line(h - 2).contains("root") && s.line(h - 2).contains("temp 83°C"));
        assert!(s.line(h - 1).starts_with(" Ctrl+C close"));
        // at most three problem rows, in the approved order
        let problems: Vec<String> = s.lines().into_iter().filter(|l| l.trim_start().starts_with(['■', '▲', '!', '?'])).take(3).collect();
        assert!(problems[0].contains("Changedetection") && problems[1].contains("Registry") && problems[2].contains("Paperless-ngx"), "{w}x{h}");
    }
    assert!(render_at(Scenario::Mixed, 150, 45).contains("ENDPOINTS"));
}

#[test]
fn the_compact_fallback_keeps_overflow_and_partial_states_truthful() {
    let s = render_at(Scenario::ManyHttp, 106, 33);
    assert!(s.contains("+7 more") && s.contains("(highlighted below)"));
    let s = render_at(Scenario::MonitoringDown, 80, 25);
    assert!(s.contains("cluster monitoring unavailable for 6m"));
    assert!(s.contains("host readings still current"));
    assert!(s.contains("apps  no current status"));
    let s = render_at(Scenario::Missing, 80, 25);
    assert!(s.contains("? Reclip") && s.contains("? glance-agent"));

    // endpoints that do not fit scroll with cues
    let f = fixtures::fixture(Scenario::Normal);
    let mut d = dashboard(&f);
    let s = draw(&mut d, 60, 20, f.now);
    assert!(s.contains("↓ 6 more rows"), "{}", s.text());
    assert!(s.line(19).contains("↑↓ scroll"));
    assert_eq!(d.key(key(KeyCode::Down)), KeyOutcome::Redraw);
    assert!(draw(&mut d, 60, 20, f.now).contains("↑ 1 above"));
}

#[test]
fn tiny_consoles_show_only_status_and_one_summary_line() {
    for (w, h) in [(59, 20), (60, 19), (40, 10)] {
        let s = render_at(Scenario::Mixed, w, h);
        let text: Vec<String> = s.lines().into_iter().map(|l| l.trim().to_string()).filter(|l| !l.is_empty()).collect();
        assert_eq!(text, vec!["ATTENTION".to_string(), "8 signals on 3 services".to_string()], "{w}x{h}");
        assert_eq!((s.fg((1, 0)), s.bg((1, 0))), (TEXT, ALERT_GROUND));
    }
    let s = render_at(Scenario::MonitoringDown, 40, 10);
    assert!(s.line(1).contains("cluster monitoring unavailable"));
}

#[test]
fn long_signals_end_in_more_rather_than_a_cut_word() {
    let mut f = fixtures::fixture(Scenario::Normal);
    fail(&mut f, "registry", "TLS certificate verification failed", 60);
    fixtures::app_state(&mut f, "registry", "OutOfSync", "Degraded", 120);
    for name in ["KubeDeploymentReplicasMismatch", "KubePersistentVolumeInodesFillingUp", "KubeContainerWaiting", "TargetDown"] {
        alert(&mut f, name, Some("registry"), None, 30);
    }
    let s = draw(&mut dashboard(&f), 160, 50, f.now);
    let row = s.line(12);
    assert!(row.contains("app OutOfSync  +4 more"), "four alerts omitted: {row}");
    let shown: Vec<&str> = row[..row.find("+").unwrap()].split("  ·  ").map(str::trim).collect();
    let whole = ["■ Registry              TLS certificate verification failed", "app Degraded", "app OutOfSync"];
    for part in &shown[1..] {
        assert!(whole.contains(part) || part.starts_with("alert Kube") && !part.ends_with("..."), "partial signal {part:?} in {row}");
    }
    assert!(row.trim_end().ends_with("since 2m"));

    // a single overlong signal is fitted at a word boundary
    let mut f = fixtures::fixture(Scenario::Normal);
    let long = "upstream answered with a very long and unhelpful message that keeps going well past the width of the attention row, and then continues for a while longer";
    fail(&mut f, "glance", long, 60);
    let row = draw(&mut dashboard(&f), 160, 50, f.now).line(12);
    let text = row.chars().skip(25).collect::<String>();
    let text = text.trim_end().trim_end_matches("since 1m").trim_end();
    assert!(text.ends_with("..."), "{row}");
    assert!(long.starts_with(text.trim_end_matches("...")), "cut inside a word: {text:?}");
    assert!(long.split([' ', ',']).filter(|w| !w.is_empty()).any(|w| text.trim_end_matches("...").ends_with(w)), "{text:?}");
}

#[test]
fn named_overflow_lists_whole_names_only() {
    let mut f = fixtures::fixture(Scenario::Normal);
    for i in 1..=10 {
        let id = format!("long-{i}");
        f.catalog.endpoints.push(CatalogEndpoint { id: id.clone(), name: format!("Remarkably Long Service {i}"), app: None });
        f.snapshot.endpoints.insert(id, EndpointResult { observed_at: ago(f.now, 21), check: Check::Fail { reason: "HTTP 500".into(), since: ago(f.now, 60) } });
    }
    let row = draw(&mut dashboard(&f), 160, 50, f.now).line(15);
    assert!(row.contains("+7 more"));
    assert!(row.trim_end().ends_with(", ... (highlighted below)"), "{row}");
    let names: String = row.chars().skip(25).collect();
    let names = &names[..names.find(", ...").unwrap()];
    for n in names.split(", ") {
        assert!(n.starts_with("Remarkably Long Service ") && n.len() > 24, "partial name {n:?}");
    }
}

#[test]
fn live_text_is_sanitised_before_it_reaches_the_terminal() {
    let mut f = fixtures::fixture(Scenario::Normal);
    f.catalog.endpoints[0].name = "Gl\u{1b}[31mance\u{7}".into();
    fail(&mut f, "glance", "HTTP 500\r\n\u{1b}]P0ff0000 Ünïcode ✓", 60);
    let s = draw(&mut dashboard(&f), 160, 50, f.now);
    s.assert_console_safe();
    assert!(s.line(12).contains("Gl?[31mance?"));
    assert!(s.line(12).contains("HTTP 500 ?]P0ff0000 ?n?code ?"), "{}", s.line(12));
}

#[test]
fn frames_are_due_on_transitions_not_every_second() {
    let f = fixtures::fixture(Scenario::Normal);
    let d = dashboard(&f);
    // 21:42:00 exactly: nothing changes before the clock's next minute
    assert_eq!(d.next_redraw(f.now), f.now + SignedDuration::from_mins(1));
    let mid = f.now + SignedDuration::from_millis(30_500);
    assert_eq!(d.next_redraw(mid), f.now + SignedDuration::from_mins(1));

    // a source crossing the stale boundary is its own transition
    let mut f = f;
    f.snapshot.sources.http.newest_sample_at = Some(ago(f.now, 170));
    let d = dashboard(&f);
    assert_eq!(d.next_redraw(f.now), ago(f.now, 170) + SignedDuration::from_secs(180) + SignedDuration::from_nanos(1));

    // so is the end of a temporary wake
    let f = fixtures::fixture(Scenario::NightWake);
    let mut d = dashboard(&f);
    let wake_end = f.now + SignedDuration::from_secs(600);
    assert_eq!(d.next_redraw(wake_end - SignedDuration::from_secs(20)), wake_end);

    // identical data is not new data
    assert!(!d.set_snapshot(f.snapshot.clone()));
    assert!(!d.set_night(Some(f.night.clone())));
}

#[test]
fn night_state_is_reported_never_assumed() {
    let f = fixtures::fixture(Scenario::Normal);
    let mut d = dashboard(&f);
    d.set_night(None);
    assert!(draw(&mut d, 160, 50, f.now).line(49).trim_end().ends_with("night schedule state not reported"));

    let f = fixtures::fixture(Scenario::NightWake);
    let mut d = dashboard(&f);
    let after = f.now + SignedDuration::from_secs(601);
    assert!(draw(&mut d, 160, 50, after).line(49).trim_end().ends_with("night schedule state out of date"));

    let mut night = f.night.clone();
    night.failure = Some(Failure { since: f.now, reason: "backlight write rejected".into() });
    night.state = NightState::QuietHours { until: "2026-10-01T06:00:00Z".parse().unwrap(), wake_until: None };
    d.set_night(Some(night));
    let footer = draw(&mut d, 160, 50, f.now).line(49);
    assert!(footer.contains("quiet hours until 08:00 · screen dark · control failed: backlight write rejected"), "{footer}");
    assert_eq!(draw(&mut d, 160, 50, f.now).fg(draw(&mut d, 160, 50, f.now).at("control failed")), WARM);
}

#[test]
fn the_compact_footer_keeps_the_approved_wording_when_it_fits() {
    assert!(render_at(Scenario::Mixed, 106, 33).line(32).starts_with(" Ctrl+C close, monitoring keeps running"));
    assert!(render_at(Scenario::Mixed, 80, 25).line(24).starts_with(" Ctrl+C close "));
}

#[test]
fn a_single_word_too_long_for_the_row_is_counted_not_cut() {
    let mut f = fixtures::fixture(Scenario::Normal);
    fail(&mut f, "glance", &"x".repeat(150), 60);
    let row = draw(&mut dashboard(&f), 160, 50, f.now).line(12);
    assert!(!row.contains("xxx"), "{row}");
    assert!(row.contains("+1 more") && row.trim_end().ends_with("since 1m"), "{row}");
}
