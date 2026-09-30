//! Fixture API-to-frontend check driver: the production derivation and frame boundary.
use health_dashboard::contract::{Catalog, Snapshot};
use health_dashboard::{Dashboard, health::Status};
use jiff::{Timestamp, tz::TimeZone};
use ratatui::{buffer::Buffer, layout::Rect};
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let catalog: Catalog = serde_json::from_slice(&std::fs::read(&args[1]).unwrap()).unwrap();
    let snapshot: Snapshot = serde_json::from_slice(&std::fs::read(&args[2]).unwrap()).unwrap();
    let now = Timestamp::now();
    let mut dashboard = Dashboard::new(
        catalog,
        TimeZone::get("Europe/Oslo").unwrap(),
        snapshot.collector_started_at,
    );
    dashboard.set_snapshot(snapshot);
    let health = dashboard.health(now);
    let status = match health.status {
        Status::AllClear => "all-clear",
        Status::Attention => "attention",
        Status::Unknown => "unknown",
    };
    let mut buffer = Buffer::empty(Rect::new(0, 0, 160, 50));
    dashboard.render(&mut buffer, now);
    let frame: String = buffer.content.iter().map(|c| c.symbol()).collect();
    println!(
        "{}",
        serde_json::json!({"status":status,"signals":health.signals,"gap_endpoints":health.gap_endpoints,"gap_apps":health.gap_apps,"frame":frame})
    );
}
