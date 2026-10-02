//! ILLUSTRATIVE fixtures: the 15 approved scenarios from teevik/homelab#71, written in
//! the production input contracts. Nothing here is read from the cluster or host;
//! readings, alert names and times are made up. They back the
//! `health-dashboard demo` entry point, never the production path.
//!
//! The inventory mirrors today's 16 Glance endpoints and 18 Argo CD apps, so the
//! shared (Immich Share -> immich), differently named (Grafana -> victoria-metrics)
//! and host-only (Nix Cache) mappings are all present.

use crate::contract::*;
use jiff::{SignedDuration, Timestamp};
use std::collections::BTreeMap;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Scenario {
    Normal,
    OneHttp,
    Mixed,
    ManyHttp,
    DeployOnly,
    Alerts,
    MonitoringDown,
    Partial,
    Missing,
    Stale,
    Recovered,
    NoTemp,
    ColdStart,
    NightWake,
    BedtimeWake,
}

impl Scenario {
    pub const ALL: [Scenario; 15] = [
        Scenario::Normal,
        Scenario::OneHttp,
        Scenario::Mixed,
        Scenario::ManyHttp,
        Scenario::DeployOnly,
        Scenario::Alerts,
        Scenario::MonitoringDown,
        Scenario::Partial,
        Scenario::Missing,
        Scenario::Stale,
        Scenario::Recovered,
        Scenario::NoTemp,
        Scenario::ColdStart,
        Scenario::NightWake,
        Scenario::BedtimeWake,
    ];

    pub fn key(self) -> &'static str {
        match self {
            Scenario::Normal => "normal",
            Scenario::OneHttp => "one-http",
            Scenario::Mixed => "mixed",
            Scenario::ManyHttp => "many-http",
            Scenario::DeployOnly => "deploy-only",
            Scenario::Alerts => "alerts",
            Scenario::MonitoringDown => "monitoring-down",
            Scenario::Partial => "partial",
            Scenario::Missing => "missing",
            Scenario::Stale => "stale",
            Scenario::Recovered => "recovered",
            Scenario::NoTemp => "no-temp",
            Scenario::ColdStart => "cold-start",
            Scenario::NightWake => "night-wake",
            Scenario::BedtimeWake => "bedtime-wake",
        }
    }

    pub fn from_key(key: &str) -> Option<Scenario> {
        Scenario::ALL.into_iter().find(|s| s.key() == key)
    }
}

/// One scenario's inputs, and the time at which it is observed.
pub struct Fixture {
    pub now: Timestamp,
    pub catalog: Catalog,
    pub snapshot: Snapshot,
    pub night: NightReport,
}

pub const ENDPOINTS: [(&str, &str, Option<&str>, u32); 16] = [
    ("glance", "Glance", Some("glance"), 12),
    ("longhorn", "Longhorn", Some("longhorn"), 41),
    ("immich", "Immich", Some("immich"), 58),
    ("grafana", "Grafana", Some("victoria-metrics"), 33),
    ("nix-cache", "Nix Cache", None, 6),
    ("argocd", "ArgoCD", Some("argocd"), 27),
    ("kodekamp", "KodeKamp", Some("kodekamp"), 19),
    ("paperless-ngx", "Paperless-ngx", Some("paperless-ngx"), 64),
    ("bentopdf", "BentoPDF", Some("bentopdf"), 9),
    ("amp", "AMP", Some("amp"), 22),
    ("twitchdropsminer", "TwitchDropsMiner", Some("twitchdropsminer"), 15),
    ("ntfy", "ntfy", Some("ntfy"), 8),
    ("immich-share", "Immich Share", Some("immich"), 31),
    ("changedetection", "Changedetection", Some("changedetection"), 47),
    ("registry", "Registry", Some("registry"), 11),
    ("reclip", "Reclip", Some("reclip"), 17),
];

pub const APPS: [&str; 18] = [
    "amd-device-plugin",
    "amp",
    "argocd",
    "bentopdf",
    "changedetection",
    "cloudflare-tunnel",
    "glance",
    "glance-agent",
    "immich",
    "kodekamp",
    "longhorn",
    "ntfy",
    "paperless-ngx",
    "reclip",
    "registry",
    "tailscale-operator",
    "twitchdropsminer",
    "victoria-metrics",
];

pub fn catalog() -> Catalog {
    Catalog {
        version: VERSION,
        endpoints: ENDPOINTS
            .iter()
            .map(|&(id, name, app, _)| CatalogEndpoint { id: id.into(), name: name.into(), app: app.map(Into::into) })
            .collect(),
        apps: APPS.iter().map(|a| a.to_string()).collect(),
    }
}

/// `n` seconds before `now` (negative: after).
pub fn ago(now: Timestamp, secs: i64) -> Timestamp {
    now - SignedDuration::from_secs(secs)
}

const GIB: u64 = 1 << 30;

fn gib(v: f64) -> u64 {
    (v * GIB as f64) as u64
}

fn history(base: f32, rise: f32, gaps: &[usize], len: usize) -> Vec<Option<f32>> {
    (0..len)
        .map(|i| {
            if gaps.contains(&i) {
                return None;
            }
            let t = i as f32;
            let wobble = ((t * 0.7).sin() * 1.6 + (t * 0.23).cos() * 2.2).round();
            let ramp = if t > len as f32 - 16.0 { (t - (len as f32 - 16.0)) * rise } else { 0.0 };
            Some((base + wobble + ramp).clamp(30.0, 99.0))
        })
        .collect()
}

fn current(now: Timestamp, age: i64) -> SourceReport {
    SourceReport { newest_sample_at: Some(ago(now, age)), failure: None }
}

/// Every source current, every endpoint answering, every app synced and healthy.
pub fn healthy(now: Timestamp) -> Fixture {
    let endpoints = ENDPOINTS
        .iter()
        .map(|&(id, _, _, ms)| (id.to_string(), EndpointResult { observed_at: ago(now, 21), check: Check::Ok { latency_ms: ms } }))
        .collect();
    let apps = APPS
        .iter()
        .map(|&id| {
            let r = AppResult { observed_at: ago(now, 12), sync: "Synced".into(), sync_since: None, health: "Healthy".into(), health_since: None };
            (id.to_string(), r)
        })
        .collect();
    Fixture {
        now,
        catalog: catalog(),
        snapshot: Snapshot {
            version: VERSION,
            collector_started_at: ago(now, 3 * 86400),
            sources: Sources { host: current(now, 3), http: current(now, 21), argo: current(now, 12), alerts: current(now, 12) },
            host: Host {
                cpu_percent: Some(28.0),
                cpu_threads: Some(16),
                memory: Some(Capacity { total_bytes: gib(30.6), available_bytes: gib(17.4) }),
                root: Some(Capacity { total_bytes: gib(1800.0), available_bytes: gib(846.0) }),
                temperature: Temperature::Reading { celsius: 54.0, sensor: "Tctl".into() },
                temperature_history: TemperatureHistory { end: Some(ago(now, 42)), celsius: history(55.0, 0.0, &[21, 22], 60) },
            },
            endpoints,
            apps,
            workloads: vec![],
            alerts: vec![],
            recoveries: vec![],
        },
        night: NightReport {
            version: VERSION,
            dark_from: "23:00".into(),
            dark_until: "08:00".into(),
            state: NightState::Day { next_dark_at: ago(now, -(78 * 60)) },
            failure: None,
        },
    }
}

pub fn fail(f: &mut Fixture, id: &str, reason: &str, for_s: i64) {
    let now = f.now;
    let e = f.snapshot.endpoints.get_mut(id).expect("fixture endpoint");
    e.check = Check::Fail { reason: reason.into(), since: ago(now, for_s) };
}

pub fn app_state(f: &mut Fixture, id: &str, sync: &str, health: &str, for_s: i64) {
    let now = f.now;
    let a = f.snapshot.apps.get_mut(id).expect("fixture app");
    a.sync = sync.into();
    a.health = health.into();
    a.sync_since = (sync != "Synced").then(|| ago(now, for_s));
    a.health_since = (health != "Healthy").then(|| ago(now, for_s));
}

pub fn alert(f: &mut Fixture, name: &str, app: Option<&str>, label: Option<&str>, for_s: i64) {
    let since = ago(f.now, for_s);
    f.snapshot.alerts.push(AlertSignal { name: name.into(), app: app.map(Into::into), label: label.map(Into::into), since });
}

pub fn restarts(f: &mut Fixture, app: &str, count: u32, for_s: i64) {
    let since = ago(f.now, for_s);
    f.snapshot.workloads.push(WorkloadSignal { app: Some(app.into()), label: None, problem: WorkloadProblem::Restarts { count }, since });
}

/// Wed 30 Sep 2026, 21:42 in Europe/Oslo.
pub fn evening() -> Timestamp {
    "2026-09-30T19:42:00Z".parse().unwrap()
}

pub fn fixture(sc: Scenario) -> Fixture {
    use Scenario::*;
    let mut f = healthy(evening());
    let now = f.now;
    match sc {
        Normal => {}
        OneHttp => fail(&mut f, "reclip", "HTTP 502", 3 * 60),
        Mixed => {
            fail(&mut f, "registry", "HTTP 503", 4 * 60);
            fail(&mut f, "changedetection", "timeout 3.0s", 2 * 60);
            app_state(&mut f, "registry", "Synced", "Degraded", 4 * 60);
            app_state(&mut f, "changedetection", "Synced", "Progressing", 12 * 60);
            restarts(&mut f, "changedetection", 5, 12 * 60);
            app_state(&mut f, "paperless-ngx", "OutOfSync", "Healthy", 9 * 60);
            alert(&mut f, "KubePodCrashLooping", Some("changedetection"), None, 12 * 60);
            alert(&mut f, "KubeDeploymentReplicasMismatch", Some("registry"), None, 5 * 60);
            let h = &mut f.snapshot.host;
            h.cpu_percent = Some(86.0);
            h.memory = Some(Capacity { total_bytes: gib(30.6), available_bytes: gib(10.1) });
            h.temperature = Temperature::Reading { celsius: 83.0, sensor: "Tctl".into() };
            h.temperature_history.celsius = history(62.0, 1.4, &[21, 22], 60);
        }
        ManyHttp => {
            for id in ["glance", "immich", "grafana", "paperless-ngx", "amp", "ntfy", "immich-share", "reclip"] {
                fail(&mut f, id, "timeout 3.0s", 6 * 60);
            }
            alert(&mut f, "TraefikDown", None, Some("cluster"), 6 * 60);
        }
        DeployOnly => {
            app_state(&mut f, "immich", "Synced", "Degraded", 7 * 60);
            restarts(&mut f, "immich", 2, 7 * 60);
            app_state(&mut f, "paperless-ngx", "OutOfSync", "Healthy", 9 * 60);
            app_state(&mut f, "tailscale-operator", "Synced", "Progressing", 3 * 60);
        }
        Alerts => {
            alert(&mut f, "KubePersistentVolumeFillingUp", Some("immich"), None, 41 * 60);
            alert(&mut f, "NodeClockNotSynchronising", None, Some("cluster"), 18 * 60);
        }
        MonitoringDown => {
            let reason = "cluster API rejected the collector credential (HTTP 401)";
            let s = &mut f.snapshot.sources;
            for src in [&mut s.http, &mut s.argo, &mut s.alerts] {
                src.newest_sample_at = Some(ago(now, 392));
                src.failure = Some(Failure { since: ago(now, 372), reason: reason.into() });
            }
            for e in f.snapshot.endpoints.values_mut() {
                e.observed_at = ago(now, 392);
            }
            for a in f.snapshot.apps.values_mut() {
                a.observed_at = ago(now, 392);
            }
        }
        Partial => {
            fail(&mut f, "registry", "HTTP 503", 4 * 60);
            f.snapshot.sources.alerts.failure = Some(Failure { since: ago(now, 130), reason: "alertmanager request timed out (5s)".into() });
            f.snapshot.sources.alerts.newest_sample_at = Some(ago(now, 150));
        }
        Missing => {
            f.snapshot.endpoints.remove("reclip");
            f.snapshot.apps.remove("glance-agent");
        }
        Stale => {
            f.snapshot.sources.http.newest_sample_at = Some(ago(now, 250));
            for e in f.snapshot.endpoints.values_mut() {
                e.observed_at = ago(now, 250);
            }
        }
        Recovered => {
            f.snapshot.recoveries.push(Recovery {
                service: "registry".into(),
                problem: "HTTP 503".into(),
                began_at: ago(now, 18 * 60),
                cleared_at: ago(now, 4 * 60),
            });
        }
        NoTemp => {
            f.snapshot.host.temperature = Temperature::Unavailable;
            f.snapshot.host.temperature_history = TemperatureHistory::default();
        }
        ColdStart => return cold_start("2026-09-30T10:04:00Z".parse().unwrap()),
        NightWake => {
            // Thu 1 Oct, 02:14: quiet hours, woken for ten minutes
            let mut f = healthy("2026-10-01T00:14:00Z".parse().unwrap());
            let now = f.now;
            f.snapshot.host.cpu_percent = Some(9.0);
            f.snapshot.host.temperature = Temperature::Reading { celsius: 49.0, sensor: "Tctl".into() };
            f.night.state = NightState::QuietHours { until: "2026-10-01T06:00:00Z".parse().unwrap(), wake_until: Some(ago(now, -600)) };
            return f;
        }
        BedtimeWake => {
            // 22:06, after an early bedtime, woken for ten minutes
            let mut f = healthy("2026-09-30T20:06:00Z".parse().unwrap());
            let now = f.now;
            f.night.state = NightState::Bedtime { until: "2026-10-01T06:00:00Z".parse().unwrap(), wake_until: Some(ago(now, -600)) };
            return f;
        }
    }
    f
}

/// Four seconds after the collector started: host readings only.
pub fn cold_start(now: Timestamp) -> Fixture {
    let mut f = healthy(now);
    f.snapshot = Snapshot {
        version: VERSION,
        collector_started_at: ago(now, 4),
        sources: Sources { host: current(now, 1), http: SourceReport::default(), argo: SourceReport::default(), alerts: SourceReport::default() },
        host: Host {
            cpu_percent: None,
            temperature: Temperature::Reading { celsius: 47.0, sensor: "Tctl".into() },
            temperature_history: TemperatureHistory::default(),
            ..f.snapshot.host
        },
        endpoints: BTreeMap::new(),
        apps: BTreeMap::new(),
        workloads: vec![],
        alerts: vec![],
        recoveries: vec![],
    };
    f.night.state = NightState::Day { next_dark_at: ago(now, -(10 * 3600 + 56 * 60)) };
    f
}
