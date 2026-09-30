//! Health derivation: one pure function of catalog, snapshot and an explicit time.
//!
//! Status, counts, attention rows and every per-row view come from here; rendering
//! only lays them out. The rules are the approved ones (teevik/homelab#71, #72):
//!
//! - ATTENTION whenever at least one known signal exists, even with partial coverage.
//! - Otherwise UNKNOWN while any required source (host, HTTP checks, Argo CD, alerts)
//!   is not current, or an expected endpoint/app has no current result.
//! - ALL CLEAR only with every source current, complete inventory and no signals.
//!
//! Counts are signals, never incidents. Coverage gaps are not signals. A loss of data
//! never clears a known signal: retained failures keep counting.

use crate::contract::*;
use jiff::{SignedDuration, Timestamp};

/// A source (or an individual result) older than this is stale.
pub const STALE_AFTER: SignedDuration = SignedDuration::from_secs(180);
/// Recoveries are shown for this long after their signals cleared.
pub const RECOVERY_SHOWN_FOR: SignedDuration = SignedDuration::from_secs(15 * 60);

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Status {
    AllClear,
    Attention,
    Unknown,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SourceId {
    Host,
    Http,
    Argo,
    Alerts,
}

impl SourceId {
    pub const ALL: [SourceId; 4] = [SourceId::Host, SourceId::Http, SourceId::Argo, SourceId::Alerts];

    pub fn name(self) -> &'static str {
        match self {
            SourceId::Host => "host",
            SourceId::Http => "http checks",
            SourceId::Argo => "argo cd",
            SourceId::Alerts => "alerts",
        }
    }
}

#[derive(Clone, PartialEq, Debug)]
pub enum Freshness {
    /// No observation since the collector started.
    Waiting,
    Current { age: SignedDuration },
    /// The newest sample is older than [`STALE_AFTER`].
    Stale { age: SignedDuration },
    /// The latest refresh failed.
    Unavailable { duration: SignedDuration, reason: String },
}

impl Freshness {
    pub fn is_current(&self) -> bool {
        matches!(self, Freshness::Current { .. })
    }
}

/// Attention tiers in display order; a row's tier is its worst signal.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub enum Tier {
    /// `■` red: an internal HTTP check fails.
    Http,
    /// `!` yellow: an active alert.
    Alert,
    /// `▲` mauve: deployment only (app health, sync, workloads).
    Deployment,
    /// `?` yellow: expected by the catalog, no current result. Not a signal.
    CoverageGap,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PartKind {
    Http,
    /// App health; `Degraded` stays red.
    AppHealth { degraded: bool },
    AppSync,
    Workload,
    Alert,
    /// Not a signal: expected data is missing or old.
    Gap,
    /// Not a signal: the endpoint answers despite the row's other signals.
    EndpointOk,
}

impl PartKind {
    pub fn is_signal(self) -> bool {
        !matches!(self, PartKind::Gap | PartKind::EndpointOk)
    }
}

#[derive(Clone, PartialEq, Debug)]
pub struct Part {
    pub kind: PartKind,
    pub text: String,
}

#[derive(Clone, PartialEq, Debug)]
pub struct AttentionRow {
    pub tier: Tier,
    pub service: String,
    /// Evidence that matched no catalog app, kept under its label (e.g. "cluster").
    pub is_label: bool,
    /// Signals in their observed order, then gap notes and `endpoint ok`.
    pub parts: Vec<Part>,
    /// Onset of the oldest signal with a reported onset; `None` for a coverage gap or
    /// when no onset was reported. Never invented from an observation time.
    pub since: Option<Timestamp>,
}

impl AttentionRow {
    pub fn signals(&self) -> usize {
        self.parts.iter().filter(|p| p.kind.is_signal()).count()
    }
}

#[derive(Clone, PartialEq, Debug)]
pub enum EndpointView {
    Waiting,
    /// Expected, but the current HTTP source has no result for it.
    Missing,
    /// No result while the source itself is not current.
    NoResult,
    Ok {
        latency_ms: u32,
        /// Last-known rather than current: drawn dimmed, never green.
        retained: bool,
        /// Set when this result is individually older than [`STALE_AFTER`].
        old: Option<SignedDuration>,
    },
    Fail {
        reason: String,
        since: Timestamp,
    },
}

#[derive(Clone, PartialEq, Debug)]
pub enum AppView {
    Waiting,
    /// Expected, but absent from Argo CD's current report.
    Missing,
    NoResult,
    Known {
        sync: String,
        health: String,
        synced: bool,
        healthy: bool,
        degraded: bool,
        retained: bool,
        old: Option<SignedDuration>,
    },
}

impl AppView {
    fn is_gap(&self) -> bool {
        matches!(self, AppView::Missing | AppView::Known { old: Some(_), .. })
    }
}

#[derive(Clone, PartialEq, Debug)]
pub struct LedgerEndpoint {
    pub name: String,
    pub view: EndpointView,
    pub app: Option<(String, AppView)>,
}

#[derive(Clone, PartialEq, Debug)]
pub struct RecoveryView {
    pub service: String,
    pub problem: String,
    pub lasted: SignedDuration,
    pub cleared_at: Timestamp,
}

pub struct Health {
    pub status: Status,
    /// Tier first, then stable catalog order.
    pub attention: Vec<AttentionRow>,
    pub signals: usize,
    pub gap_endpoints: usize,
    pub gap_apps: usize,
    pub sources: Vec<(SourceId, Freshness)>,
    /// Every cluster source is still waiting for its first observation.
    pub cold_start: bool,
    pub collector_age: SignedDuration,
    /// Catalog order, never re-sorted.
    pub endpoints: Vec<LedgerEndpoint>,
    pub apps_without_endpoint: Vec<(String, AppView)>,
    /// Cleared less than 15 minutes ago, most recent first, at most three.
    pub recoveries: Vec<RecoveryView>,
    pub endpoints_ok: usize,
    pub endpoints_failing: usize,
    pub apps_known: usize,
    pub apps_unhealthy: usize,
    pub apps_out_of_sync: usize,
    pub alerts: usize,
    /// The next time this derivation would change on its own (a freshness boundary or
    /// a recovery leaving the display). Redraw then, not on a timer.
    pub next_change: Option<Timestamp>,
}

impl Health {
    pub fn source(&self, id: SourceId) -> &Freshness {
        &self.sources.iter().find(|(s, _)| *s == id).unwrap().1
    }
}

fn freshness(r: &SourceReport, now: Timestamp) -> Freshness {
    if let Some(f) = &r.failure {
        return Freshness::Unavailable { duration: now.duration_since(f.since), reason: f.reason.clone() };
    }
    match r.newest_sample_at {
        None => Freshness::Waiting,
        Some(t) => {
            let age = now.duration_since(t);
            if age > STALE_AFTER { Freshness::Stale { age } } else { Freshness::Current { age } }
        }
    }
}

/// An individual result is old when its own sample passed the stale boundary.
fn old(observed_at: Timestamp, now: Timestamp) -> Option<SignedDuration> {
    let age = now.duration_since(observed_at);
    (age > STALE_AFTER).then_some(age)
}

fn endpoint_view(r: Option<&EndpointResult>, src: &Freshness, now: Timestamp) -> EndpointView {
    let current = src.is_current();
    match r {
        None if matches!(src, Freshness::Waiting) => EndpointView::Waiting,
        None if current => EndpointView::Missing,
        None => EndpointView::NoResult,
        Some(r) => match &r.check {
            Check::Fail { reason, since } => EndpointView::Fail { reason: reason.clone(), since: *since },
            Check::Ok { latency_ms } => {
                let old = old(r.observed_at, now);
                EndpointView::Ok { latency_ms: *latency_ms, retained: !current || old.is_some(), old: if current { old } else { None } }
            }
        },
    }
}

fn app_view(r: Option<&AppResult>, src: &Freshness, now: Timestamp) -> AppView {
    let current = src.is_current();
    match r {
        None if matches!(src, Freshness::Waiting) => AppView::Waiting,
        None if current => AppView::Missing,
        None => AppView::NoResult,
        Some(r) => {
            let old = old(r.observed_at, now);
            AppView::Known {
                sync: r.sync.clone(),
                health: r.health.clone(),
                synced: r.is_synced(),
                healthy: r.is_healthy(),
                degraded: r.is_degraded(),
                retained: !current || old.is_some(),
                old: if current { old } else { None },
            }
        }
    }
}

/// Collects one row's parts and its oldest onset.
#[derive(Default)]
struct RowBuilder {
    parts: Vec<Part>,
    since: Option<Timestamp>,
}

impl RowBuilder {
    /// A signal without a reported onset still counts; it just cannot set `since`.
    fn signal(&mut self, kind: PartKind, text: String, since: Option<Timestamp>) {
        self.parts.push(Part { kind, text });
        if let Some(since) = since {
            self.since = Some(self.since.map_or(since, |s| s.min(since)));
        }
    }

    fn gap(&mut self, text: &str) {
        self.parts.push(Part { kind: PartKind::Gap, text: text.into() });
    }

    fn has(&self, f: impl Fn(PartKind) -> bool) -> bool {
        self.parts.iter().any(|p| f(p.kind))
    }

    fn finish(mut self, service: String, endpoint_answers: bool, is_label: bool) -> Option<AttentionRow> {
        let tier = if self.has(|k| k == PartKind::Http) {
            Tier::Http
        } else if self.has(|k| k == PartKind::Alert) {
            Tier::Alert
        } else if self.has(PartKind::is_signal) {
            Tier::Deployment
        } else if self.has(|k| k == PartKind::Gap) {
            Tier::CoverageGap
        } else {
            return None;
        };
        // signals first (in their observed order), notes after
        self.parts.sort_by_key(|p| !p.kind.is_signal());
        if endpoint_answers && tier != Tier::Http && tier != Tier::CoverageGap {
            self.parts.push(Part { kind: PartKind::EndpointOk, text: "endpoint ok".into() });
        }
        let since = if tier == Tier::CoverageGap { None } else { self.since };
        Some(AttentionRow { tier, service, is_label, parts: self.parts, since })
    }
}

pub fn derive(catalog: &Catalog, s: &Snapshot, now: Timestamp) -> Health {
    let sources: Vec<(SourceId, Freshness)> = SourceId::ALL
        .iter()
        .map(|&id| {
            let r = match id {
                SourceId::Host => &s.sources.host,
                SourceId::Http => &s.sources.http,
                SourceId::Argo => &s.sources.argo,
                SourceId::Alerts => &s.sources.alerts,
            };
            (id, freshness(r, now))
        })
        .collect();
    let src = |id: SourceId| &sources.iter().find(|(s, _)| *s == id).unwrap().1;
    let http = src(SourceId::Http);
    let argo = src(SourceId::Argo);

    let endpoint_apps: Vec<&str> = catalog.endpoints.iter().filter_map(|e| e.app.as_deref()).collect();
    let known_app = |id: &str| catalog.apps.iter().any(|a| a == id) || endpoint_apps.contains(&id);
    let mut used_alerts = vec![false; s.alerts.len()];
    let mut used_workloads = vec![false; s.workloads.len()];

    // One app's evidence, added once: health, sync, workloads, alerts.
    let mut app_parts = |row: &mut RowBuilder, app: &str, view: &AppView| {
        if let (AppView::Known { .. }, Some(r)) = (view, s.apps.get(app)) {
            if !r.is_healthy() {
                row.signal(PartKind::AppHealth { degraded: r.is_degraded() }, format!("app {}", r.health), r.health_since);
            }
            if !r.is_synced() {
                row.signal(PartKind::AppSync, format!("app {}", r.sync), r.sync_since);
            }
        }
        match view {
            AppView::Missing => row.gap("not reported by argo cd"),
            AppView::Known { old: Some(age), .. } => row.gap(&format!("argo cd report {} old", crate::text::age(*age))),
            _ => {}
        }
        for (i, w) in s.workloads.iter().enumerate() {
            if w.app.as_deref() == Some(app) {
                used_workloads[i] = true;
                row.signal(PartKind::Workload, workload_text(&w.problem), Some(w.since));
            }
        }
        for (i, a) in s.alerts.iter().enumerate() {
            if a.app.as_deref() == Some(app) {
                used_alerts[i] = true;
                row.signal(PartKind::Alert, format!("alert {}", a.name), Some(a.since));
            }
        }
    };

    let mut rows = vec![];
    let mut claimed: Vec<&str> = vec![];
    let mut endpoints = vec![];
    for e in &catalog.endpoints {
        let view = endpoint_view(s.endpoints.get(&e.id), http, now);
        let mut row = RowBuilder::default();
        match &view {
            EndpointView::Fail { reason, since } => row.signal(PartKind::Http, reason.clone(), Some(*since)),
            EndpointView::Missing => row.gap("no check result"),
            EndpointView::Ok { old: Some(age), .. } => row.gap(&format!("check result {} old", crate::text::age(*age))),
            _ => {}
        }
        let app = e.app.as_deref().map(|id| (id.to_string(), app_view(s.apps.get(id), argo, now)));
        if let Some((id, v)) = &app {
            // a shared app's evidence belongs to its first endpoint in catalog order
            if !claimed.contains(&id.as_str()) {
                claimed.push(e.app.as_deref().unwrap());
                app_parts(&mut row, id, v);
            }
        }
        let answers = matches!(view, EndpointView::Ok { retained: false, .. });
        rows.extend(row.finish(e.name.clone(), answers, false));
        endpoints.push(LedgerEndpoint { name: e.name.clone(), view, app });
    }
    let mut apps_without_endpoint = vec![];
    for id in &catalog.apps {
        if endpoint_apps.contains(&id.as_str()) {
            continue;
        }
        let view = app_view(s.apps.get(id), argo, now);
        let mut row = RowBuilder::default();
        app_parts(&mut row, id, &view);
        rows.extend(row.finish(id.clone(), false, false));
        apps_without_endpoint.push((id.clone(), view));
    }

    // Evidence matching no catalog app keeps its own row, by label, in first-seen order.
    let mut labels: Vec<String> = vec![];
    let label_of = |app: &Option<String>, label: &Option<String>| match app {
        Some(a) if !known_app(a) => a.clone(),
        _ => label.clone().unwrap_or_else(|| "cluster".into()),
    };
    for (i, w) in s.workloads.iter().enumerate() {
        if !used_workloads[i] {
            let l = label_of(&w.app, &w.label);
            if !labels.contains(&l) {
                labels.push(l);
            }
        }
    }
    for (i, a) in s.alerts.iter().enumerate() {
        if !used_alerts[i] {
            let l = label_of(&a.app, &a.label);
            if !labels.contains(&l) {
                labels.push(l);
            }
        }
    }
    for label in labels {
        let mut row = RowBuilder::default();
        for (i, w) in s.workloads.iter().enumerate() {
            if !used_workloads[i] && label_of(&w.app, &w.label) == label {
                row.signal(PartKind::Workload, workload_text(&w.problem), Some(w.since));
            }
        }
        for (i, a) in s.alerts.iter().enumerate() {
            if !used_alerts[i] && label_of(&a.app, &a.label) == label {
                row.signal(PartKind::Alert, format!("alert {}", a.name), Some(a.since));
            }
        }
        rows.extend(row.finish(label, false, true));
    }
    rows.sort_by_key(|r| r.tier); // stable: catalog order within a tier

    let signals = rows.iter().map(AttentionRow::signals).sum();
    let endpoint_gap = |v: &EndpointView| matches!(v, EndpointView::Missing | EndpointView::Ok { old: Some(_), .. });
    let gap_endpoints = endpoints.iter().filter(|e| endpoint_gap(&e.view)).count();
    let mut expected_apps: Vec<(&str, AppView)> = vec![];
    for e in &endpoints {
        if let Some((id, v)) = &e.app
            && !expected_apps.iter().any(|(a, _)| a == id) {
                expected_apps.push((id, v.clone()));
            }
    }
    for (id, v) in &apps_without_endpoint {
        expected_apps.push((id, v.clone()));
    }
    let gap_apps = expected_apps.iter().filter(|(_, v)| v.is_gap()).count();
    let all_current = sources.iter().all(|(_, f)| f.is_current());
    let status = if signals > 0 {
        Status::Attention
    } else if !all_current || gap_endpoints + gap_apps > 0 {
        Status::Unknown
    } else {
        Status::AllClear
    };

    let mut recoveries: Vec<&Recovery> =
        s.recoveries.iter().filter(|r| r.cleared_at <= now && now.duration_since(r.cleared_at) < RECOVERY_SHOWN_FOR).collect();
    recoveries.sort_by_key(|r| std::cmp::Reverse(r.cleared_at));
    let service_name = |id: &str| {
        catalog.endpoints.iter().find(|e| e.id == id).map(|e| e.name.clone()).unwrap_or_else(|| id.to_string())
    };
    let recoveries = recoveries
        .into_iter()
        .take(3)
        .map(|r| RecoveryView {
            service: service_name(&r.service),
            problem: r.problem.clone(),
            lasted: r.cleared_at.duration_since(r.began_at),
            cleared_at: r.cleared_at,
        })
        .collect();

    // the next moment something changes without new data
    let mut boundaries: Vec<Timestamp> = vec![];
    let past_stale = |t: Timestamp| t + STALE_AFTER + SignedDuration::from_nanos(1);
    for r in [&s.sources.host, &s.sources.http, &s.sources.argo, &s.sources.alerts] {
        boundaries.extend(r.newest_sample_at.map(past_stale));
    }
    boundaries.extend(s.endpoints.values().map(|e| past_stale(e.observed_at)));
    boundaries.extend(s.apps.values().map(|a| past_stale(a.observed_at)));
    boundaries.extend(s.recoveries.iter().map(|r| r.cleared_at + RECOVERY_SHOWN_FOR));
    let next_change = boundaries.into_iter().filter(|t| *t > now).min();

    let known_apps: Vec<(bool, bool)> = expected_apps
        .iter()
        .filter_map(|(_, v)| match v {
            AppView::Known { synced, healthy, .. } => Some((*synced, *healthy)),
            _ => None,
        })
        .collect();
    let cold_start = [SourceId::Http, SourceId::Argo, SourceId::Alerts].iter().all(|&id| matches!(src(id), Freshness::Waiting));
    Health {
        status,
        signals,
        gap_endpoints,
        gap_apps,
        cold_start,
        collector_age: now.duration_since(s.collector_started_at),
        endpoints_ok: endpoints.iter().filter(|e| matches!(e.view, EndpointView::Ok { .. })).count(),
        endpoints_failing: endpoints.iter().filter(|e| matches!(e.view, EndpointView::Fail { .. })).count(),
        apps_known: known_apps.len(),
        apps_unhealthy: known_apps.iter().filter(|(_, healthy)| !healthy).count(),
        apps_out_of_sync: known_apps.iter().filter(|(synced, _)| !synced).count(),
        alerts: s.alerts.len(),
        attention: rows,
        sources,
        endpoints,
        apps_without_endpoint,
        recoveries,
        next_change,
    }
}

fn workload_text(p: &WorkloadProblem) -> String {
    match p {
        WorkloadProblem::Restarts { count: 1 } => "1 restart / 1h".into(),
        WorkloadProblem::Restarts { count } => format!("{count} restarts / 1h"),
        WorkloadProblem::Unready { count: 1 } => "1 workload unready".into(),
        WorkloadProblem::Unready { count } => format!("{count} workloads unready"),
    }
}
