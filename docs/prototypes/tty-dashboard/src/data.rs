//! ILLUSTRATIVE fixtures only. Nothing here is read from the cluster or host.
//!
//! Endpoint inventory mirrors the 16 sites in `kubernetes/glance.nix` (stable ids,
//! catalog order). Application inventory mirrors the 18 Argo `Application`s in
//! `manifests/homelab/apps`. The two are deliberately separate lists: an endpoint
//! may map to a shared app (Immich Share -> immich), a differently named app
//! (Grafana -> victoria-metrics) or to none (host Nix Cache).
//!
//! Each scenario is a snapshot as the collector would hand it to the TUI: per-source
//! freshness plus the last values it has. Attention rows, counts and the status word
//! are *derived* from that (see `derive`), never written into the fixture.

#[derive(Clone, Copy, PartialEq, Debug)]
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
    pub fn label(self) -> &'static str {
        match self {
            Scenario::Normal => "normal",
            Scenario::OneHttp => "one HTTP failure",
            Scenario::Mixed => "mixed attention",
            Scenario::ManyHttp => "many HTTP failures, overflow",
            Scenario::DeployOnly => "HTTP ok, deployment unhealthy",
            Scenario::Alerts => "active alerts only",
            Scenario::MonitoringDown => "cluster monitoring unavailable",
            Scenario::Partial => "partial coverage, known failure",
            Scenario::Missing => "missing expected inventory",
            Scenario::Stale => "stale samples",
            Scenario::Recovered => "recovery",
            Scenario::NoTemp => "unsupported temperature",
            Scenario::ColdStart => "cold start",
            Scenario::NightWake => "woken in quiet hours",
            Scenario::BedtimeWake => "woken during bedtime",
        }
    }
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
}

/// Freshness of one collector source, from the age of its newest *source* sample.
#[derive(Clone, Copy, PartialEq)]
pub enum Src {
    /// no observation yet since the collector started
    Waiting,
    Current { age_s: u32 },
    /// requests succeed but the newest sample is older than 3 minutes
    Stale { age_s: u32 },
    Unavailable { for_s: u32, reason: &'static str },
}

impl Src {
    pub fn current(self) -> bool {
        matches!(self, Src::Current { .. })
    }
}

#[derive(Clone, Copy)]
pub enum Check {
    Waiting,
    Ok { ms: u32 },
    Fail { what: &'static str, for_m: u32 },
    /// the catalog expects this target but no probe series exists
    Missing,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Sync {
    Synced,
    OutOfSync,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Health {
    Healthy,
    Progressing,
    Degraded,
}

#[derive(Clone, Copy)]
pub enum AppState {
    Waiting,
    /// expected by the catalog, absent from Argo CD's report
    Missing,
    Known { sync: Sync, health: Health, restarts: Option<&'static str>, since_m: u32 },
}

pub struct Endpoint {
    pub id: &'static str,
    pub name: &'static str,
    pub app: Option<&'static str>,
    pub check: Check,
}

pub struct App {
    pub id: &'static str,
    pub state: AppState,
}

pub struct Alert {
    pub name: &'static str,
    /// Argo app id the alert maps to, or a free label ("cluster") when it maps to none
    pub target: &'static str,
    pub for_m: u32,
}

#[derive(Clone, Copy)]
pub enum Temp {
    Reading(u8),
    Unsupported,
}

pub struct Host {
    /// None until a second sample exists
    pub cpu: Option<u8>,
    pub threads: u8,
    pub mem: u8,
    pub mem_detail: &'static str,
    pub root: u8,
    pub root_detail: &'static str,
    pub temp: Temp,
    /// one value per minute, oldest first; None = no sample (gap). Empty after start.
    pub temp_history: Vec<Option<u8>>,
}

/// What the night-policy controller reports; the TUI only displays it.
pub enum Night {
    Day { dark_in: &'static str },
    /// temporary wake inside 23:00-08:00
    QuietWake { dark_at: &'static str, left: &'static str },
    /// temporary wake during a manual bedtime
    BedtimeWake { dark_at: &'static str, left: &'static str },
}

pub struct Recovery {
    pub service: &'static str,
    pub what: &'static str,
    pub lasted: &'static str,
    pub ok_since: &'static str,
}

pub struct Snapshot {
    pub clock: &'static str,
    pub date: &'static str,
    /// Some(seconds) while the dashboard has just started
    pub started_s: Option<u32>,
    pub host_src: Src,
    pub http: Src,
    pub argo: Src,
    pub alerts_src: Src,
    pub endpoints: Vec<Endpoint>,
    pub apps: Vec<App>,
    pub alerts: Vec<Alert>,
    pub host: Host,
    pub night: Night,
    pub recovered: Vec<Recovery>,
}

impl Snapshot {
    pub fn app(&self, id: &str) -> Option<&App> {
        self.apps.iter().find(|a| a.id == id)
    }
    pub fn apps_without_endpoint(&self) -> Vec<&App> {
        self.apps
            .iter()
            .filter(|a| !self.endpoints.iter().any(|e| e.app == Some(a.id)))
            .collect()
    }
    pub fn sources(&self) -> [(&'static str, Src); 4] {
        [("host", self.host_src), ("http checks", self.http), ("argo cd", self.argo), ("alerts", self.alerts_src)]
    }
}

// ---------------------------------------------------------------- derived state

/// Attention tiers, in display order. The row's tier is its worst signal.
#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord)]
pub enum Tier {
    /// an internal HTTP check fails                      ■ red
    Fault,
    /// an active alert, endpoint and deployment fine     ! yellow
    Alert,
    /// deployment only: health, sync or restarts         ▲ mauve
    Deploy,
    /// expected by the catalog, no result                ? yellow (coverage, not a signal)
    Unknown,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Http,
    AppHealth,
    AppSync,
    Restarts,
    Alert,
    /// annotation, not a signal: the endpoint answers despite the other signals
    EndpointOk,
    NoResult,
}

pub struct Signal {
    pub kind: Kind,
    pub text: String,
}

pub struct Attention {
    pub tier: Tier,
    pub service: String,
    pub signals: Vec<Signal>,
    /// minutes since the oldest signal began; None for coverage gaps
    pub since_m: Option<u32>,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Status {
    AllClear,
    Attention,
    Unknown,
}

pub struct Derived {
    pub status: Status,
    /// worst first, then stable catalog order
    pub attention: Vec<Attention>,
    /// signals, never incidents
    pub signals: usize,
    pub gaps_endpoints: usize,
    pub gaps_apps: usize,
}

fn app_signals(a: &App, sigs: &mut Vec<Signal>, since: &mut Option<u32>) -> bool {
    match a.state {
        AppState::Missing => {
            sigs.push(Signal { kind: Kind::NoResult, text: "not reported by argo cd".to_string() });
            true
        }
        AppState::Known { sync, health, restarts, since_m } => {
            let before = sigs.len();
            match health {
                Health::Healthy => {}
                Health::Progressing => sigs.push(Signal { kind: Kind::AppHealth, text: "app Progressing".into() }),
                Health::Degraded => sigs.push(Signal { kind: Kind::AppHealth, text: "app Degraded".into() }),
            }
            if sync == Sync::OutOfSync {
                sigs.push(Signal { kind: Kind::AppSync, text: "app OutOfSync".into() });
            }
            if let Some(r) = restarts {
                sigs.push(Signal { kind: Kind::Restarts, text: r.into() });
            }
            if sigs.len() > before {
                *since = Some(since.map_or(since_m, |s| s.max(since_m)));
            }
            false
        }
        AppState::Waiting => false,
    }
}

pub fn derive(s: &Snapshot) -> Derived {
    let mut rows: Vec<Attention> = vec![];
    let mut claimed: Vec<&str> = vec![];
    let mut used_alerts = vec![false; s.alerts.len()];

    let mut row = |service: String, ep: Option<&Endpoint>, app: Option<&App>, rows: &mut Vec<Attention>, claimed: &mut Vec<&'static str>| {
        let mut sigs = vec![];
        let mut since: Option<u32> = None;
        let mut gap = false;
        if let Some(e) = ep {
            match e.check {
                Check::Fail { what, for_m } => {
                    sigs.push(Signal { kind: Kind::Http, text: what.into() });
                    since = Some(for_m);
                }
                Check::Missing => {
                    sigs.push(Signal { kind: Kind::NoResult, text: "no check result".into() });
                    gap = true;
                }
                _ => {}
            }
        }
        if let Some(a) = app {
            claimed.push(a.id);
            gap |= app_signals(a, &mut sigs, &mut since);
            for (i, al) in s.alerts.iter().enumerate() {
                if al.target == a.id {
                    used_alerts[i] = true;
                    sigs.push(Signal { kind: Kind::Alert, text: format!("alert {}", al.name) });
                    since = Some(since.map_or(al.for_m, |x| x.max(al.for_m)));
                }
            }
        }
        let has = |k: Kind| sigs.iter().any(|g| g.kind == k);
        let tier = if has(Kind::Http) {
            Tier::Fault
        } else if has(Kind::Alert) {
            Tier::Alert
        } else if has(Kind::AppHealth) || has(Kind::AppSync) || has(Kind::Restarts) {
            Tier::Deploy
        } else if gap {
            Tier::Unknown
        } else {
            return;
        };
        if tier != Tier::Fault && tier != Tier::Unknown {
            if let Some(Endpoint { check: Check::Ok { .. }, .. }) = ep {
                sigs.push(Signal { kind: Kind::EndpointOk, text: "endpoint ok".into() });
            }
        }
        rows.push(Attention { tier, service, signals: sigs, since_m: if tier == Tier::Unknown { None } else { since } });
    };

    // catalog endpoints first; a shared app's signals belong to its first endpoint
    for e in &s.endpoints {
        let app = e.app.filter(|id| !claimed.contains(id)).and_then(|id| s.app(id));
        row(e.name.to_string(), Some(e), app, &mut rows, &mut claimed);
    }
    for a in s.apps_without_endpoint() {
        row(a.id.to_string(), None, Some(a), &mut rows, &mut claimed);
    }
    drop(row);
    // alerts that map to no app: one row per label
    let mut free: Vec<&str> = vec![];
    for (i, al) in s.alerts.iter().enumerate() {
        if !used_alerts[i] && !free.contains(&al.target) {
            free.push(al.target);
        }
    }
    for label in free {
        let hits: Vec<&Alert> = s.alerts.iter().filter(|a| a.target == label).collect();
        rows.push(Attention {
            tier: Tier::Alert,
            service: label.to_string(),
            signals: hits.iter().map(|a| Signal { kind: Kind::Alert, text: format!("alert {}", a.name) }).collect(),
            since_m: hits.iter().map(|a| a.for_m).max(),
        });
    }
    rows.sort_by_key(|r| r.tier); // stable: catalog order within a tier

    let signals = rows
        .iter()
        .flat_map(|r| &r.signals)
        .filter(|g| !matches!(g.kind, Kind::EndpointOk | Kind::NoResult))
        .count();
    let gaps_endpoints = s.endpoints.iter().filter(|e| matches!(e.check, Check::Missing)).count();
    let gaps_apps = s.apps.iter().filter(|a| matches!(a.state, AppState::Missing)).count();
    let complete = s.http.current() && s.argo.current() && s.alerts_src.current() && gaps_endpoints + gaps_apps == 0;
    let status = if rows.iter().any(|r| r.tier != Tier::Unknown) {
        Status::Attention
    } else if !complete {
        Status::Unknown
    } else {
        Status::AllClear
    };
    Derived { status, attention: rows, signals, gaps_endpoints, gaps_apps }
}

// ---------------------------------------------------------------- fixtures

const ENDPOINTS: [(&str, &str, Option<&str>, u32); 16] = [
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

const APPS: [&str; 18] = [
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

fn history(base: f32, rise: f32, gaps: &[usize], len: usize) -> Vec<Option<u8>> {
    (0..len)
        .map(|i| {
            if gaps.contains(&i) {
                return None;
            }
            let t = i as f32;
            let wobble = ((t * 0.7).sin() * 1.6 + (t * 0.23).cos() * 2.2).round();
            let ramp = if t > len as f32 - 16.0 { (t - (len as f32 - 16.0)) * rise } else { 0.0 };
            Some((base + wobble + ramp).clamp(30.0, 99.0) as u8)
        })
        .collect()
}

const HEALTHY: AppState = AppState::Known { sync: Sync::Synced, health: Health::Healthy, restarts: None, since_m: 0 };

pub fn snapshot(sc: Scenario) -> Snapshot {
    use Scenario::*;
    let cur = |age_s| Src::Current { age_s };
    let mut s = Snapshot {
        clock: "21:42",
        date: "Wed 30 Sep",
        started_s: None,
        host_src: cur(3),
        http: cur(21),
        argo: cur(12),
        alerts_src: cur(12),
        endpoints: ENDPOINTS
            .iter()
            .map(|&(id, name, app, ms)| Endpoint { id, name, app, check: Check::Ok { ms } })
            .collect(),
        apps: APPS.iter().map(|&id| App { id, state: HEALTHY }).collect(),
        alerts: vec![],
        host: Host {
            cpu: Some(28),
            threads: 16,
            mem: 43,
            mem_detail: "13.2 / 30.6 GiB",
            root: 53,
            root_detail: "846 GiB free",
            temp: Temp::Reading(54),
            temp_history: history(55.0, 0.0, &[21, 22], 60),
        },
        night: Night::Day { dark_in: "1h 18m" },
        recovered: vec![],
    };
    let fail = |s: &mut Snapshot, id: &str, what: &'static str, for_m: u32| {
        s.endpoints.iter_mut().find(|e| e.id == id).unwrap().check = Check::Fail { what, for_m };
    };
    let app = |s: &mut Snapshot, id: &str, st: AppState| {
        s.apps.iter_mut().find(|a| a.id == id).unwrap().state = st;
    };
    match sc {
        Normal => {}
        OneHttp => fail(&mut s, "reclip", "HTTP 502", 3),
        Mixed => {
            fail(&mut s, "registry", "HTTP 503", 4);
            fail(&mut s, "changedetection", "timeout 3.0s", 2);
            app(&mut s, "registry", AppState::Known { sync: Sync::Synced, health: Health::Degraded, restarts: None, since_m: 4 });
            app(
                &mut s,
                "changedetection",
                AppState::Known { sync: Sync::Synced, health: Health::Progressing, restarts: Some("5 restarts / 15m"), since_m: 12 },
            );
            app(&mut s, "paperless-ngx", AppState::Known { sync: Sync::OutOfSync, health: Health::Healthy, restarts: None, since_m: 9 });
            s.alerts = vec![
                Alert { name: "KubePodCrashLooping", target: "changedetection", for_m: 12 },
                Alert { name: "KubeDeploymentReplicasMismatch", target: "registry", for_m: 5 },
            ];
            s.host.cpu = Some(86);
            s.host.mem = 67;
            s.host.mem_detail = "20.5 / 30.6 GiB";
            s.host.temp = Temp::Reading(83);
            s.host.temp_history = history(62.0, 1.4, &[21, 22], 60);
        }
        ManyHttp => {
            for id in ["glance", "immich", "grafana", "paperless-ngx", "amp", "ntfy", "immich-share", "reclip"] {
                fail(&mut s, id, "timeout 3.0s", 6);
            }
            s.alerts = vec![Alert { name: "TraefikDown", target: "cluster", for_m: 6 }];
        }
        DeployOnly => {
            app(&mut s, "immich", AppState::Known { sync: Sync::Synced, health: Health::Degraded, restarts: Some("2 restarts / 15m"), since_m: 7 });
            app(&mut s, "paperless-ngx", AppState::Known { sync: Sync::OutOfSync, health: Health::Healthy, restarts: None, since_m: 9 });
            app(&mut s, "tailscale-operator", AppState::Known { sync: Sync::Synced, health: Health::Progressing, restarts: None, since_m: 3 });
        }
        Alerts => {
            s.alerts = vec![
                Alert { name: "KubePersistentVolumeFillingUp", target: "immich", for_m: 41 },
                Alert { name: "NodeClockNotSynchronising", target: "cluster", for_m: 18 },
            ];
        }
        MonitoringDown => {
            let down = Src::Unavailable { for_s: 372, reason: "cluster API rejected the collector credential (HTTP 401)" };
            (s.http, s.argo, s.alerts_src) = (down, down, down);
        }
        Partial => {
            fail(&mut s, "registry", "HTTP 503", 4);
            s.alerts_src = Src::Unavailable { for_s: 130, reason: "alertmanager request timed out (5s)" };
        }
        Missing => {
            s.endpoints.iter_mut().find(|e| e.id == "reclip").unwrap().check = Check::Missing;
            app(&mut s, "glance-agent", AppState::Missing);
        }
        Stale => s.http = Src::Stale { age_s: 250 },
        Recovered => {
            s.recovered = vec![Recovery { service: "Registry", what: "HTTP 503", lasted: "14m", ok_since: "21:38" }];
        }
        NoTemp => {
            s.host.temp = Temp::Unsupported;
            s.host.temp_history = vec![];
        }
        ColdStart => {
            s.clock = "12:04";
            s.started_s = Some(4);
            s.host_src = cur(1);
            (s.http, s.argo, s.alerts_src) = (Src::Waiting, Src::Waiting, Src::Waiting);
            for e in &mut s.endpoints {
                e.check = Check::Waiting;
            }
            for a in &mut s.apps {
                a.state = AppState::Waiting;
            }
            s.host.cpu = None;
            s.host.temp = Temp::Reading(47);
            s.host.temp_history = vec![];
            s.night = Night::Day { dark_in: "10h 56m" };
        }
        NightWake => {
            (s.clock, s.date) = ("02:14", "Thu 1 Oct");
            s.host.temp = Temp::Reading(49);
            s.host.cpu = Some(9);
            s.night = Night::QuietWake { dark_at: "02:24", left: "10m" };
        }
        BedtimeWake => {
            s.clock = "22:06";
            s.night = Night::BedtimeWake { dark_at: "22:16", left: "10m" };
        }
    }
    s
}
