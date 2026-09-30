//! ILLUSTRATIVE fixtures only. Nothing here is read from the cluster or host.
//!
//! Endpoint inventory mirrors the 16 sites in `kubernetes/glance.nix` (stable ids,
//! catalog order). Application inventory mirrors the 18 Argo `Application`s in
//! `manifests/homelab/apps`. The two are deliberately separate lists: an endpoint
//! may map to a shared app (Immich Share -> immich), a differently named app
//! (Grafana -> victoria-metrics) or to none (host Nix Cache).

#[derive(Clone, Copy, PartialEq)]
pub enum Scenario {
    Normal,
    Mixed,
}

impl Scenario {
    pub fn label(self) -> &'static str {
        match self {
            Scenario::Normal => "normal",
            Scenario::Mixed => "mixed attention",
        }
    }
}

#[derive(Clone)]
pub enum Check {
    Ok { ms: u32 },
    Fail { what: &'static str, for_: &'static str },
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

pub struct Endpoint {
    pub id: &'static str,
    pub name: &'static str,
    pub app: Option<&'static str>,
    pub check: Check,
}

pub struct App {
    pub id: &'static str,
    pub sync: Sync,
    pub health: Health,
    pub restarts: Option<&'static str>,
}

pub struct Alert {
    pub name: &'static str,
    pub subject: &'static str,
    pub for_: &'static str,
}

pub struct Host {
    pub cpu: u8,
    pub threads: u8,
    pub mem: u8,
    pub mem_detail: &'static str,
    pub root: u8,
    pub root_detail: &'static str,
    pub temp: Option<u8>,
    /// one value per minute, oldest first; None = no sample (gap)
    pub temp_history: Vec<Option<u8>>,
}

pub struct Source {
    pub name: &'static str,
    pub age: &'static str,
}

/// One row of the attention summary. `signals` is a count of signals, never of incidents.
pub struct Attention {
    pub severity: Severity,
    pub service: &'static str,
    pub parts: Vec<&'static str>,
    pub since: &'static str,
}

#[derive(Clone, Copy, PartialEq, PartialOrd)]
pub enum Severity {
    Fault,
    Deploy,
}

pub struct Snapshot {
    pub clock: &'static str,
    pub date: &'static str,
    pub endpoints: Vec<Endpoint>,
    pub apps: Vec<App>,
    pub alerts: Vec<Alert>,
    pub host: Host,
    pub sources: Vec<Source>,
    pub attention: Vec<Attention>,
    pub signals: usize,
}

impl Snapshot {
    pub fn app(&self, id: &str) -> Option<&App> {
        self.apps.iter().find(|a| a.id == id)
    }
    pub fn endpoints_ok(&self) -> usize {
        self.endpoints.iter().filter(|e| matches!(e.check, Check::Ok { .. })).count()
    }
    pub fn apps_healthy(&self) -> usize {
        self.apps.iter().filter(|a| a.health == Health::Healthy).count()
    }
    pub fn apps_synced(&self) -> usize {
        self.apps.iter().filter(|a| a.sync == Sync::Synced).count()
    }
    pub fn apps_without_endpoint(&self) -> Vec<&App> {
        self.apps
            .iter()
            .filter(|a| !self.endpoints.iter().any(|e| e.app == Some(a.id)))
            .collect()
    }
}

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

fn history(base: f32, rise: f32, gaps: &[usize]) -> Vec<Option<u8>> {
    (0..60)
        .map(|i| {
            if gaps.contains(&i) {
                return None;
            }
            let t = i as f32;
            let wobble = ((t * 0.7).sin() * 1.6 + (t * 0.23).cos() * 2.2).round();
            let ramp = if t > 44.0 { (t - 44.0) * rise } else { 0.0 };
            Some((base + wobble + ramp).clamp(30.0, 99.0) as u8)
        })
        .collect()
}

pub fn snapshot(s: Scenario) -> Snapshot {
    let mixed = s == Scenario::Mixed;
    let endpoints = ENDPOINTS
        .iter()
        .map(|&(id, name, app, ms)| {
            let check = match (mixed, id) {
                (true, "registry") => Check::Fail { what: "HTTP 503", for_: "4m" },
                (true, "changedetection") => Check::Fail { what: "timeout 3.0s", for_: "2m" },
                _ => Check::Ok { ms },
            };
            Endpoint { id, name, app, check }
        })
        .collect();
    let apps = APPS
        .iter()
        .map(|&id| {
            let (sync, health, restarts) = match (mixed, id) {
                (true, "registry") => (Sync::Synced, Health::Degraded, None),
                (true, "changedetection") => {
                    (Sync::Synced, Health::Progressing, Some("5 restarts / 15m"))
                }
                (true, "paperless-ngx") => (Sync::OutOfSync, Health::Healthy, None),
                _ => (Sync::Synced, Health::Healthy, None),
            };
            App { id, sync, health, restarts }
        })
        .collect();
    let alerts = if mixed {
        vec![
            Alert { name: "KubePodCrashLooping", subject: "changedetection-0", for_: "12m" },
            Alert { name: "KubeDeploymentReplicasMismatch", subject: "registry/zot", for_: "5m" },
        ]
    } else {
        vec![]
    };
    let host = if mixed {
        Host {
            cpu: 86,
            threads: 16,
            mem: 67,
            mem_detail: "20.5 / 30.6 GiB",
            root: 53,
            root_detail: "846 GiB free",
            temp: Some(83),
            temp_history: history(62.0, 1.4, &[21, 22]),
        }
    } else {
        Host {
            cpu: 28,
            threads: 16,
            mem: 43,
            mem_detail: "13.2 / 30.6 GiB",
            root: 53,
            root_detail: "846 GiB free",
            temp: Some(54),
            temp_history: history(55.0, 0.0, &[21, 22]),
        }
    };
    let sources = vec![
        Source { name: "host", age: "3s" },
        Source { name: "http checks", age: "21s" },
        Source { name: "argo cd", age: "12s" },
        Source { name: "alerts", age: "12s" },
    ];
    let attention = if mixed {
        vec![
            Attention {
                severity: Severity::Fault,
                service: "Registry",
                parts: vec!["HTTP 503", "app Degraded", "alert ReplicasMismatch"],
                since: "4m",
            },
            Attention {
                severity: Severity::Fault,
                service: "Changedetection",
                parts: vec!["timeout 3.0s", "5 restarts / 15m", "alert CrashLooping"],
                since: "2m",
            },
            Attention {
                severity: Severity::Deploy,
                service: "Paperless-ngx",
                parts: vec!["app OutOfSync", "endpoint ok"],
                since: "9m",
            },
        ]
    } else {
        vec![]
    };
    let signals = if mixed { 8 } else { 0 };
    Snapshot {
        clock: "21:42",
        date: "Wed 30 Sep",
        endpoints,
        apps,
        alerts,
        host,
        sources,
        attention,
        signals,
    }
}
