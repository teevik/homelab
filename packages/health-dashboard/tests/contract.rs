//! The input contracts: the documented examples parse, and every fixture survives a
//! round trip through JSON unchanged.
mod common;

use common::*;
use health_dashboard::contract::*;
use health_dashboard::fixtures::{self, Scenario};
use health_dashboard::health::Status;

fn round_trip<T: serde::Serialize + serde::de::DeserializeOwned + PartialEq + std::fmt::Debug>(v: &T) {
    let json = serde_json::to_string(v).unwrap();
    assert_eq!(&serde_json::from_str::<T>(&json).unwrap(), v, "{json}");
}

#[test]
fn every_fixture_round_trips_through_json() {
    for sc in Scenario::ALL {
        let f = fixtures::fixture(sc);
        round_trip(&f.catalog);
        round_trip(&f.snapshot);
        round_trip(&f.night);
    }
}

#[test]
fn the_documented_examples_parse_and_render() {
    let catalog: Catalog = serde_json::from_str(include_str!("../examples/contract/catalog.json")).unwrap();
    let snapshot: Snapshot = serde_json::from_str(include_str!("../examples/contract/snapshot.json")).unwrap();
    let night: NightReport = serde_json::from_str(include_str!("../examples/contract/night.json")).unwrap();
    let now = "2026-09-30T19:42:00Z".parse().unwrap();
    let mut d = health_dashboard::Dashboard::new(catalog, oslo(), snapshot.collector_started_at);
    d.set_snapshot(snapshot);
    d.set_night(Some(night));
    let h = d.health(now);
    assert_eq!(h.status, Status::Attention);
    // Grafana's HTTP failure; immich's Degraded, restarts and alert once; kube-system; cluster
    assert_eq!(h.signals, 6);
    assert_eq!(h.gap_endpoints, 1, "nix-cache has no result");
    assert_eq!(h.gap_apps, 1, "cloudflare-tunnel is not reported");
    let s = draw(&mut d, 160, 50, now);
    s.assert_console_safe();
    assert!(s.contains("6 signals on 2 services and the cluster"));
    assert!(s.line(49).trim_end().ends_with("screen dark 23:00-08:00, in 1h 18m"));
}
