//! Independent host sampling and fixed service-proxy reads. Only snapshots leave this service.
use crate::contract::*;
use crate::health;
use jiff::{SignedDuration, Timestamp};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

const SELECTOR: &str = "{__name__=~\"up|probe_success|probe_duration_seconds|probe_http_status_code|argocd_app_info|kube_pod_info|kube_pod_status_phase|kube_pod_status_ready|kube_pod_container_status_restarts_total|kube_pod_labels|vmalert_iteration_total\"}";
const RESTARTS: &str = "round(increase_prometheus(kube_pod_container_status_restarts_total[1h]))";
const METRICS_PROXY: &str = "https://127.0.0.1:6443/api/v1/namespaces/victoria-metrics/services/http:vmsingle-vm-victoria-metrics-k8s-stack:8428/proxy/api/v1/query";
const ALERTS_PROXY: &str = "https://127.0.0.1:6443/api/v1/namespaces/victoria-metrics/services/http:vmalertmanager-vm-victoria-metrics-k8s-stack:9093/proxy/api/v2/alerts";

#[derive(Clone, Deserialize)]
struct Settings {
    catalog: PathBuf,
    snapshot: PathBuf,
    state: PathBuf,
    credential: PathBuf,
    #[serde(default = "metrics_proxy")]
    metrics_url: String,
    #[serde(default = "alerts_proxy")]
    alerts_url: String,
    #[serde(default = "host_interval")]
    host_interval_ms: u64,
    #[serde(default = "cluster_interval")]
    cluster_interval_ms: u64,
    /// Explicit namespace ownership derived from configured apps, not endpoint names.
    namespaces: BTreeMap<String, String>,
    #[serde(default)]
    controller_report: Option<PathBuf>,
    #[serde(default)]
    night: Option<PathBuf>,
}
fn metrics_proxy() -> String {
    METRICS_PROXY.into()
}
fn alerts_proxy() -> String {
    ALERTS_PROXY.into()
}
fn host_interval() -> u64 {
    5_000
}
fn cluster_interval() -> u64 {
    30_000
}

#[derive(Deserialize)]
struct Credential {
    token: String,
    #[serde(default)]
    ca: Option<PathBuf>,
}

#[derive(Clone, Deserialize)]
struct Metric {
    metric: BTreeMap<String, String>,
    value: (f64, String),
}
impl Metric {
    fn label(&self, key: &str) -> &str {
        self.metric.get(key).map(String::as_str).unwrap_or("")
    }
    fn number(&self) -> Result<f64, String> {
        self.value
            .1
            .parse::<f64>()
            .ok()
            .filter(|v| v.is_finite())
            .ok_or_else(|| "non-finite or invalid metric".into())
    }
}
#[derive(Deserialize)]
struct Vector {
    status: String,
    data: VectorData,
}
#[derive(Deserialize)]
struct VectorData {
    #[serde(rename = "resultType")]
    kind: String,
    result: Vec<Metric>,
}

fn instant(seconds: f64) -> Result<Timestamp, String> {
    if !seconds.is_finite() {
        return Err("invalid observation time".into());
    }
    Timestamp::from_millisecond((seconds * 1_000.) as i64).map_err(|e| e.to_string())
}
fn fresh(t: Timestamp, now: Timestamp) -> bool {
    t <= now + SignedDuration::from_secs(5) && now.duration_since(t) <= health::STALE_AFTER
}
fn read<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T, String> {
    serde_json::from_slice(&fs::read(path).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
}

/// curl owns verified TLS and bounded I/O. Bearer material travels on stdin, never argv.
fn request(url: &str, query: Option<&str>, credential: &Credential) -> Result<Value, String> {
    if credential
        .token
        .chars()
        .any(|c| c.is_control() || c == '"' || c == '\\')
    {
        return Err("collector credential malformed".into());
    }
    let mut command = Command::new("curl");
    command.args([
        "--silent",
        "--show-error",
        "--fail",
        "--connect-timeout",
        "2",
        "--max-time",
        "4",
        "--max-filesize",
        "8388608",
        "--config",
        "-",
    ]);
    if let Some(ca) = &credential.ca {
        command.arg("--cacert").arg(ca);
    }
    if let Some(query) = query {
        command.args(["--get", "--data-urlencode", &format!("query={query}")]);
    }
    command
        .arg(url)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = command.spawn().map_err(|e| e.to_string())?;
    writeln!(
        child.stdin.take().unwrap(),
        "header = \"Authorization: Bearer {}\"",
        credential.token
    )
    .map_err(|e| e.to_string())?;
    let output = child.wait_with_output().map_err(|e| e.to_string())?;
    if !output.status.success() {
        // curl's errors contain status/timeout/TLS diagnostics, but no request header.
        return Err(format!(
            "cluster read failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|e| format!("invalid API response: {e}"))
}
fn query(
    settings: &Settings,
    credential: &Credential,
    expression: &str,
) -> Result<Vec<Metric>, String> {
    let v: Vector = serde_json::from_value(request(
        &settings.metrics_url,
        Some(expression),
        credential,
    )?)
    .map_err(|e| e.to_string())?;
    if v.status != "success" || v.data.kind != "vector" {
        return Err("metrics query unsuccessful or not a vector".into());
    }
    for metric in &v.data.result {
        metric.number()?;
    }
    Ok(v.data.result)
}

struct Cluster {
    metrics: Vec<Metric>,
    times: BTreeMap<BTreeMap<String, String>, Timestamp>,
    restarts: Vec<Metric>,
    alerts: Result<Value, String>,
    fetched_at: Timestamp,
    evaluated_at: Timestamp,
}
fn fetch(settings: &Settings) -> Result<Cluster, String> {
    // Reopen the atomic credential on every poll, so renewal needs no service restart.
    let credential: Credential =
        read(&settings.credential).map_err(|e| format!("collector credential unavailable: {e}"))?;
    let metrics = query(settings, &credential, SELECTOR)?;
    let evaluated_at = metrics
        .first()
        .map(|m| instant(m.value.0))
        .transpose()?
        .unwrap_or(Timestamp::now());
    let times = query(
        settings,
        &credential,
        &format!("timestamp({SELECTOR}) keep_metric_names"),
    )?
    .into_iter()
    .map(|m| Ok((m.metric.clone(), instant(m.number()?)?)))
    .collect::<Result<_, String>>()?;
    let restarts = query(settings, &credential, RESTARTS)?;
    let alerts = request(&settings.alerts_url, None, &credential);
    Ok(Cluster {
        metrics,
        times,
        restarts,
        alerts,
        fetched_at: Timestamp::now(),
        evaluated_at,
    })
}
impl Cluster {
    fn named(&self, name: &'static str) -> impl Iterator<Item = &Metric> {
        self.metrics
            .iter()
            .filter(move |m| m.label("__name__") == name)
    }
    fn time(&self, metric: &Metric) -> Result<Timestamp, String> {
        self.times.get(&metric.metric).copied().ok_or_else(|| {
            format!(
                "underlying timestamp absent for {}",
                metric.label("__name__")
            )
        })
    }
    fn current(&self, metric: &Metric, now: Timestamp) -> Result<Timestamp, String> {
        let time = self.time(metric)?;
        if !fresh(time, now) {
            return Err(format!(
                "old underlying sample: {}",
                metric.label("__name__")
            ));
        }
        Ok(time)
    }
    fn scrape(&self, job: &str, now: Timestamp) -> Result<Timestamp, String> {
        let rows: Vec<_> = self.named("up").filter(|m| m.label("job") == job).collect();
        if rows.is_empty() {
            return Err(format!("required scrape absent: {job}"));
        }
        let mut oldest = now;
        for m in rows {
            oldest = oldest.min(self.current(m, now)?);
            if m.number()? != 1. {
                return Err(format!("required scrape down: {job}"));
            }
        }
        Ok(oldest)
    }
}
fn report(source: &mut SourceReport, result: Result<Timestamp, String>, now: Timestamp) {
    match result {
        Ok(time) => {
            source.newest_sample_at = Some(time);
            source.failure = None;
        }
        Err(reason) => {
            let since = source.failure.as_ref().map(|f| f.since).unwrap_or(now);
            source.failure = Some(Failure { since, reason });
        }
    }
}

fn cluster_report(
    source: &mut SourceReport,
    result: Result<Timestamp, String>,
    cluster: &Cluster,
    names: &[&str],
    jobs: &[&str],
    now: Timestamp,
) {
    // A successfully fetched, uniformly old source is stale. A fresh subset with old
    // required evidence remains unavailable with a reason, never a green refresh.
    if result.as_ref().is_err_and(|reason| reason.contains("old")) {
        let newest = cluster
            .metrics
            .iter()
            .filter(|m| {
                names.contains(&m.label("__name__"))
                    || (m.label("__name__") == "up" && jobs.contains(&m.label("job")))
            })
            .filter_map(|m| cluster.time(m).ok())
            .max();
        if let Some(time) = newest.filter(|t| now.duration_since(*t) > health::STALE_AFTER) {
            report(source, Ok(time), now);
            return;
        }
    }
    report(source, result, now);
}

fn http(
    catalog: &Catalog,
    cluster: &Cluster,
    snapshot: &mut Snapshot,
    now: Timestamp,
) -> Result<Timestamp, String> {
    let mut newest = None;
    let mut failures = vec![];
    for endpoint in &catalog.endpoints {
        let result = (|| {
            let required = |name: &'static str| -> Result<&Metric, String> {
                let mut rows = cluster
                    .named(name)
                    .filter(|m| m.label("service_id") == endpoint.id);
                let metric = rows
                    .next()
                    .ok_or_else(|| format!("{}: missing {name}", endpoint.id))?;
                if rows.next().is_some() {
                    return Err(format!("{}: ambiguous {name}", endpoint.id));
                }
                Ok(metric)
            };
            let up = required("up")?;
            let success = required("probe_success")?;
            let duration = required("probe_duration_seconds")?;
            let status = required("probe_http_status_code")?;
            let mut observed = now;
            for m in [up, success, duration, status] {
                let time = cluster.time(m)?;
                if time > now + SignedDuration::from_secs(5) {
                    return Err("probe observation is in the future".into());
                }
                observed = observed.min(time);
            }
            if up.number()? != 1. {
                return Err(format!("{}: probe scrape failed", endpoint.id));
            }
            if ![0., 1.].contains(&success.number()?) {
                return Err("invalid probe_success".into());
            }
            let mut check = if success.number()? == 1. {
                Check::Ok {
                    latency_ms: (duration.number()? * 1_000.).max(0.) as u32,
                }
            } else {
                let since = match snapshot.endpoints.get(&endpoint.id).map(|r| &r.check) {
                    Some(Check::Fail { since, .. }) => *since,
                    _ => observed,
                };
                let code = status.number()? as u32;
                Check::Fail {
                    since,
                    reason: if code == 0 {
                        "HTTP probe failed (timeout, DNS or TLS)".into()
                    } else {
                        format!("HTTP {code}")
                    },
                }
            };
            if !fresh(observed, now) {
                if let Some(EndpointResult {
                    check: previous @ Check::Fail { .. },
                    ..
                }) = snapshot.endpoints.get(&endpoint.id)
                {
                    check = previous.clone();
                }
            }
            snapshot.endpoints.insert(
                endpoint.id.clone(),
                EndpointResult {
                    observed_at: observed,
                    check,
                },
            );
            Ok(observed)
        })();
        match result {
            Ok(t) => newest = Some(newest.map_or(t, |previous: Timestamp| previous.max(t))),
            Err(e) => failures.push(e),
        }
    }
    if failures.is_empty() {
        Ok(newest.unwrap_or(now))
    } else {
        Err(failures.join("; "))
    }
}

fn owner(
    labels: &BTreeMap<String, String>,
    catalog: &Catalog,
    settings: &Settings,
) -> Option<String> {
    for key in [
        "catalog_app",
        "label_argocd_argoproj_io_instance",
        "label_app_kubernetes_io_part_of",
        "app",
    ] {
        if let Some(app) = labels.get(key).filter(|app| catalog.apps.contains(app)) {
            return Some(app.clone());
        }
    }
    // Namespace -> app is an explicit generated ownership declaration, only when unique.
    let namespace = labels.get("namespace")?;
    let mut apps = settings
        .namespaces
        .iter()
        .filter(|(_, ns)| *ns == namespace);
    let first = apps.next()?;
    if apps.next().is_some() {
        None
    } else {
        Some(first.0.clone())
    }
}
fn argo(
    catalog: &Catalog,
    settings: &Settings,
    cluster: &Cluster,
    snapshot: &mut Snapshot,
    now: Timestamp,
) -> Result<Timestamp, String> {
    let mut oldest = cluster
        .scrape("argocd-application-controller-metrics", now)?
        .min(cluster.scrape("kube-state-metrics", now)?);
    let mut errors = vec![];
    for app in &catalog.apps {
        let rows: Vec<_> = cluster
            .named("argocd_app_info")
            .filter(|m| m.label("name") == app && m.number().ok() == Some(1.))
            .collect();
        if rows.len() != 1 {
            errors.push(format!("app {app}: missing or ambiguous Argo result"));
            continue;
        }
        let m = rows[0];
        let time = match cluster.current(m, now) {
            Ok(t) => t,
            Err(e) => {
                errors.push(e);
                continue;
            }
        };
        if m.label("sync_status").is_empty() || m.label("health_status").is_empty() {
            errors.push(format!("app {app}: required status absent"));
            continue;
        }
        let previous = snapshot.apps.get(app);
        let onset = |healthy: bool, previous: Option<Timestamp>| {
            if healthy {
                None
            } else {
                Some(previous.unwrap_or(time))
            }
        };
        let sync = m.label("sync_status").to_string();
        let health = m.label("health_status").to_string();
        let result = AppResult {
            observed_at: time,
            sync_since: onset(sync == "Synced", previous.and_then(|p| p.sync_since)),
            health_since: onset(health == "Healthy", previous.and_then(|p| p.health_since)),
            sync,
            health,
        };
        snapshot.apps.insert(app.clone(), result);
        oldest = oldest.min(time);
    }
    let pods: Vec<_> = cluster.named("kube_pod_info").collect();
    if pods.is_empty() {
        errors.push("required workload inventory absent".into());
    }
    let mut workloads = vec![];
    for pod in pods {
        let matches = |m: &&Metric| {
            m.label("namespace") == pod.label("namespace") && m.label("pod") == pod.label("pod")
        };
        let observations: Vec<_> = [
            "kube_pod_status_phase",
            "kube_pod_status_ready",
            "kube_pod_container_status_restarts_total",
        ]
        .into_iter()
        .map(|name| cluster.named(name).filter(matches).collect::<Vec<_>>())
        .collect();
        let completed = observations[0]
            .iter()
            .any(|m| m.label("phase") == "Succeeded" && m.number().ok() == Some(1.));
        let required = if completed {
            &observations[..1]
        } else {
            &observations[..]
        };
        let mut valid = true;
        for rows in required {
            if rows.is_empty() {
                valid = false;
                errors.push(format!(
                    "{}/{}: required workload series absent",
                    pod.label("namespace"),
                    pod.label("pod")
                ));
            }
            for m in rows {
                match cluster.current(m, now) {
                    Ok(t) => oldest = oldest.min(t),
                    Err(e) => {
                        valid = false;
                        errors.push(e);
                    }
                }
            }
        }
        match cluster.current(pod, now) {
            Ok(t) => oldest = oldest.min(t),
            Err(e) => {
                valid = false;
                errors.push(e);
            }
        }
        if !valid || completed {
            continue;
        }
        let mut labels = pod.metric.clone();
        for m in cluster.named("kube_pod_labels").filter(matches) {
            labels.extend(m.metric.clone());
        }
        let app = owner(&labels, catalog, settings);
        let label = Some(format!("{}/{}", pod.label("namespace"), pod.label("pod")));
        let unready = observations[0].iter().any(|m| {
            ["Pending", "Failed", "Unknown"].contains(&m.label("phase"))
                && m.number().ok() == Some(1.)
        }) || observations[1]
            .iter()
            .any(|m| m.label("condition") != "true" && m.number().ok() == Some(1.));
        let mut restarts = 0;
        for container in &observations[2] {
            let increases: Vec<_> = cluster
                .restarts
                .iter()
                .filter(|m| {
                    m.label("namespace") == pod.label("namespace")
                        && m.label("pod") == pod.label("pod")
                        && m.label("container") == container.label("container")
                })
                .collect();
            if increases.len() != 1 {
                errors.push(format!(
                    "{}/{}: required one-hour restart observation absent or ambiguous",
                    pod.label("namespace"),
                    pod.label("pod")
                ));
                continue;
            }
            if !fresh(instant(increases[0].value.0)?, now) {
                errors.push("old one-hour restart evaluation".into());
                continue;
            }
            restarts += increases[0].number()?.max(0.) as u32;
        }
        for problem in [
            unready.then_some(WorkloadProblem::Unready { count: 1 }),
            (restarts > 0).then_some(WorkloadProblem::Restarts { count: restarts }),
        ]
        .into_iter()
        .flatten()
        {
            let same_kind =
                |p: &WorkloadProblem| std::mem::discriminant(p) == std::mem::discriminant(&problem);
            let since = snapshot
                .workloads
                .iter()
                .find(|s| s.label == label && same_kind(&s.problem))
                .map(|s| s.since)
                .unwrap_or(now);
            workloads.push(WorkloadSignal {
                app: app.clone(),
                label: label.clone(),
                problem,
                since,
            });
        }
    }
    // Incomplete workload evidence cannot clear any known workload signal.
    if errors.is_empty() {
        snapshot.workloads = workloads;
        Ok(oldest)
    } else {
        for old in &snapshot.workloads {
            if !workloads.iter().any(|s| {
                s.label == old.label
                    && std::mem::discriminant(&s.problem) == std::mem::discriminant(&old.problem)
            }) {
                workloads.push(old.clone());
            }
        }
        snapshot.workloads = workloads;
        Err(errors.join("; "))
    }
}

#[derive(Default)]
struct Evaluator {
    groups: BTreeMap<BTreeMap<String, String>, (f64, Timestamp, bool)>,
}
impl Evaluator {
    fn observe(&mut self, cluster: &Cluster, now: Timestamp) -> Result<Timestamp, String> {
        let scrape = cluster.scrape("vmalert-vm-victoria-metrics-k8s-stack", now)?;
        let rows: Vec<_> = cluster.named("vmalert_iteration_total").collect();
        if rows.is_empty() {
            return Err("required evaluator series absent".into());
        }
        let mut oldest = scrape;
        for row in rows {
            oldest = oldest.min(cluster.current(row, now)?);
            let value = row.number()?;
            let observation = self
                .groups
                .entry(row.metric.clone())
                .or_insert((value, now, false));
            if observation.0 != value {
                *observation = (value, now, true);
            }
            if !observation.2 {
                return Err("waiting for observed evaluator progress".into());
            }
            if !fresh(observation.1, now) {
                return Err("old evaluator progress".into());
            }
            oldest = oldest.min(observation.1);
        }
        Ok(oldest)
    }
}
fn alerts(
    catalog: &Catalog,
    settings: &Settings,
    cluster: &Cluster,
    evaluator: &mut Evaluator,
    snapshot: &mut Snapshot,
    now: Timestamp,
) -> Result<Timestamp, String> {
    let evidence = evaluator.observe(cluster, now);
    let rows = cluster
        .alerts
        .as_ref()
        .map_err(Clone::clone)?
        .as_array()
        .ok_or("alerts response is not an array")?;
    let mut alerts = vec![];
    for row in rows {
        let labels: BTreeMap<String, String> =
            serde_json::from_value(row.get("labels").cloned().ok_or("alert labels absent")?)
                .map_err(|e| e.to_string())?;
        let name = labels.get("alertname").ok_or("alert name absent")?;
        let status = row.get("status").ok_or("alert status absent")?;
        if ["Watchdog", "InfoInhibitor"].contains(&name.as_str()) {
            continue;
        }
        let state = status
            .get("state")
            .and_then(Value::as_str)
            .ok_or("alert state absent")?;
        let silenced = status
            .get("silencedBy")
            .and_then(Value::as_array)
            .ok_or("alert silence evidence absent")?;
        let inhibited = status
            .get("inhibitedBy")
            .and_then(Value::as_array)
            .ok_or("alert inhibition evidence absent")?;
        if !["active", "suppressed", "unprocessed"].contains(&state) {
            return Err("unknown alert state".into());
        }
        if state != "active" || !silenced.is_empty() || !inhibited.is_empty() {
            continue;
        }
        let started: Timestamp = row
            .get("startsAt")
            .and_then(Value::as_str)
            .ok_or("alert onset absent")?
            .parse()
            .map_err(|e: jiff::Error| e.to_string())?;
        let ends: Timestamp = row
            .get("endsAt")
            .and_then(Value::as_str)
            .ok_or("alert expiry absent")?
            .parse()
            .map_err(|e: jiff::Error| e.to_string())?;
        if ends <= now || started > now + SignedDuration::from_secs(5) {
            return Err("active alert has invalid observation bounds".into());
        }
        let app = owner(&labels, catalog, settings);
        let label = if app.is_none() {
            Some(
                labels
                    .get("namespace")
                    .cloned()
                    .unwrap_or_else(|| "cluster".into()),
            )
        } else {
            None
        };
        let since = snapshot
            .alerts
            .iter()
            .find(|s| s.name == *name && s.app == app && s.label == label)
            .map(|s| s.since.min(started))
            .unwrap_or(started);
        let signal = AlertSignal {
            name: name.clone(),
            app,
            label,
            since,
        };
        if !alerts.contains(&signal) {
            alerts.push(signal);
        }
    }
    if evidence.is_err() {
        for old in &snapshot.alerts {
            if !alerts.contains(old) {
                alerts.push(old.clone());
            }
        }
    }
    snapshot.alerts = alerts;
    evidence.map(|time| time.min(cluster.fetched_at))
}

struct HostSampler {
    cpu: Option<(u64, u64)>,
}
impl HostSampler {
    fn sample(&mut self, host: &mut Host, now: Timestamp) -> Result<(), String> {
        let stat = fs::read_to_string("/proc/stat").map_err(|e| e.to_string())?;
        let ticks: Vec<u64> = stat
            .lines()
            .next()
            .ok_or("CPU sample absent")?
            .split_whitespace()
            .skip(1)
            .take(8)
            .map(|v| v.parse().map_err(|_| "CPU sample malformed"))
            .collect::<Result<_, _>>()?;
        if ticks.len() < 4 {
            return Err("CPU sample incomplete".into());
        }
        let total = ticks.iter().sum::<u64>();
        let idle = ticks[3] + ticks.get(4).copied().unwrap_or(0);
        host.cpu_percent = self
            .cpu
            .filter(|(t, i)| total > *t && idle >= *i)
            .map(|(t, i)| (100. * (1. - (idle - i) as f32 / (total - t) as f32)).clamp(0., 100.));
        self.cpu = Some((total, idle));
        host.cpu_threads = Some(
            stat.lines()
                .filter(|l| {
                    l.starts_with("cpu") && l.as_bytes().get(3).is_some_and(u8::is_ascii_digit)
                })
                .count() as u32,
        );
        let mem = fs::read_to_string("/proc/meminfo").map_err(|e| e.to_string())?;
        let memory = |key: &str| {
            mem.lines()
                .find(|l| l.starts_with(key))
                .and_then(|l| l.split_whitespace().nth(1))
                .and_then(|v| v.parse::<u64>().ok())
                .map(|v| v * 1024)
                .ok_or("memory sample incomplete")
        };
        host.memory = Some(Capacity {
            total_bytes: memory("MemTotal:")?,
            available_bytes: memory("MemAvailable:")?,
        });
        let mut capacity: libc::statvfs = unsafe { std::mem::zeroed() };
        if unsafe { libc::statvfs(c"/".as_ptr(), &mut capacity) } != 0 {
            return Err(std::io::Error::last_os_error().to_string());
        }
        host.root = Some(Capacity {
            total_bytes: capacity.f_blocks * capacity.f_frsize,
            available_bytes: capacity.f_bavail * capacity.f_frsize,
        });
        host.temperature = temperature();
        let minute = Timestamp::from_second(now.as_second().div_euclid(60) * 60).unwrap();
        let history = &mut host.temperature_history;
        if history.end.is_some_and(|end| minute < end) {
            history.celsius.clear();
            history.end = None;
        }
        if let Some(end) = history.end {
            let missed = minute
                .duration_since(end)
                .as_secs()
                .div_euclid(60)
                .clamp(0, 90);
            history
                .celsius
                .extend(std::iter::repeat_n(None, missed as usize));
        } else {
            history.celsius.push(None);
        }
        history.end = Some(minute);
        let value = match host.temperature {
            Temperature::Reading { celsius, .. } => Some(celsius),
            _ => None,
        };
        if let Some(last) = history.celsius.last_mut().filter(|_| value.is_some()) {
            *last = value;
        }
        if history.celsius.len() > 90 {
            history.celsius.drain(..history.celsius.len() - 90);
        }
        Ok(())
    }
}
fn temperature() -> Temperature {
    for hwmon in fs::read_dir("/sys/class/hwmon")
        .into_iter()
        .flatten()
        .flatten()
    {
        let path = hwmon.path();
        let name = fs::read_to_string(path.join("name")).unwrap_or_default();
        if !["k10temp", "coretemp"].contains(&name.trim()) {
            continue;
        }
        for file in fs::read_dir(&path).into_iter().flatten().flatten() {
            let name = file.file_name().to_string_lossy().into_owned();
            if !name.starts_with("temp") || !name.ends_with("_label") {
                continue;
            }
            let label = fs::read_to_string(file.path()).unwrap_or_default();
            if !["Tctl", "Tdie", "Package id 0"].contains(&label.trim()) {
                continue;
            }
            let input = path.join(name.replace("_label", "_input"));
            if let Some(celsius) = fs::read_to_string(input)
                .ok()
                .and_then(|s| s.trim().parse::<f32>().ok())
                .map(|v| v / 1_000.)
                .filter(|v| v.is_finite() && (-20. ..=130.).contains(v))
            {
                return Temperature::Reading {
                    celsius,
                    sensor: label.trim().into(),
                };
            }
        }
    }
    Temperature::Unavailable
}

#[derive(Serialize, Deserialize)]
struct CollectorState {
    #[serde(flatten)]
    snapshot: Snapshot,
    #[serde(default)]
    signals: BTreeMap<String, Recovery>,
}

fn recover(
    catalog: &Catalog,
    before: &Snapshot,
    after: &mut Snapshot,
    signals: &mut BTreeMap<String, Recovery>,
    now: Timestamp,
) {
    let old = health::derive(catalog, before, now);
    let new = health::derive(catalog, after, now);
    for row in old
        .attention
        .iter()
        .chain(&new.attention)
        .filter(|r| r.signals() > 0)
    {
        let service = catalog
            .endpoints
            .iter()
            .find(|e| e.name == row.service)
            .map(|e| e.id.clone())
            .unwrap_or_else(|| row.service.clone());
        let signal = signals.entry(row.service.clone()).or_insert(Recovery {
            service,
            problem: String::new(),
            began_at: row.since.unwrap_or(now),
            cleared_at: now,
        });
        signal.began_at = signal.began_at.min(row.since.unwrap_or(now));
        signal.problem = row
            .parts
            .iter()
            .filter(|p| p.kind.is_signal())
            .map(|p| p.text.clone())
            .collect::<Vec<_>>()
            .join(", ");
    }
    // Affirmative clearance requires all relevant monitoring evidence, never data loss.
    if [
        &after.sources.http,
        &after.sources.argo,
        &after.sources.alerts,
    ]
    .iter()
    .all(|s| s.failure.is_none() && s.newest_sample_at.is_some_and(|t| fresh(t, now)))
        && new.gap_apps == 0
        && new.gap_endpoints == 0
    {
        let cleared: Vec<_> = signals
            .keys()
            .filter(|name| !new.attention.iter().any(|r| &r.service == *name))
            .cloned()
            .collect();
        for name in cleared {
            let mut recovery = signals.remove(&name).unwrap();
            recovery.cleared_at = now;
            after.recoveries.retain(|r| r.service != recovery.service);
            after.recoveries.push(recovery);
        }
    }
    after
        .recoveries
        .retain(|r| now.duration_since(r.cleared_at) < health::RECOVERY_SHOWN_FOR);
    if after.recoveries.len() > 128 {
        after.recoveries.drain(..after.recoveries.len() - 128);
    }
}
fn atomic(path: &Path, value: &impl serde::Serialize) -> Result<(), String> {
    let temporary = path.with_extension("tmp");
    let mut file = fs::File::create(&temporary).map_err(|e| e.to_string())?;
    serde_json::to_writer(&mut file, value).map_err(|e| e.to_string())?;
    file.sync_all().map_err(|e| e.to_string())?;
    fs::rename(temporary, path).map_err(|e| e.to_string())
}

/// Translate only a recent report from the independent controller. No device writes.
fn night(settings: &Settings, now: Timestamp) -> Result<(), String> {
    let (Some(input), Some(output)) = (&settings.controller_report, &settings.night) else {
        return Ok(());
    };
    let translated = (|| {
        let report: Value = read(input)?;
        if report["version"].as_u64() != Some(1) {
            return Err("unknown policy contract".into());
        }
        let observed = instant(
            report["observed_at"]
                .as_f64()
                .ok_or("policy observation absent")?,
        )?;
        if observed > now + SignedDuration::from_secs(5)
            || now.duration_since(observed) > SignedDuration::from_secs(15)
        {
            return Err("old policy report".into());
        }
        let boot = fs::read_to_string("/proc/sys/kernel/random/boot_id")
            .map_err(|e| e.to_string())?;
        if report["boot_id"].as_str() != Some(boot.trim()) {
            return Err("policy report belongs to another boot".into());
        }
        let until = instant(
            report["schedule_until"]
                .as_f64()
                .ok_or("policy expiry absent")?,
        )?;
        let wake = report["wake_until"].as_f64().map(instant).transpose()?;
        let state = if let Some(bedtime) = report["bedtime_until"].as_f64() {
            NightState::Bedtime {
                until: instant(bedtime)?,
                wake_until: wake,
            }
        } else if report["scheduled_dark"]
            .as_bool()
            .ok_or("policy mode absent")?
        {
            NightState::QuietHours {
                until,
                wake_until: wake,
            }
        } else {
            NightState::Day {
                next_dark_at: until,
            }
        };
        let failures = report["failures"]
            .as_array()
            .ok_or("policy application evidence absent")?;
        let failure = if report["application"].as_str() != Some("applied") || !failures.is_empty() {
            Some(Failure {
                since: observed,
                reason: failures
                    .iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join("; "),
            })
        } else {
            None
        };
        Ok::<_, String>(NightReport {
            version: VERSION,
            dark_from: "23:00".into(),
            dark_until: "08:00".into(),
            state,
            failure,
        })
    })();
    match translated {
        Ok(report) => atomic(output, &report),
        Err(_) => match fs::remove_file(output) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e.to_string()),
        },
    }
}

pub fn run(config: &Path) -> Result<(), String> {
    let settings: Settings = read(config)?;
    if settings.host_interval_ms == 0 || settings.cluster_interval_ms == 0 {
        return Err("sampling intervals must be positive".into());
    }
    let catalog: Catalog = read(&settings.catalog)?;
    if catalog.version != VERSION {
        return Err("unsupported catalog version".into());
    }
    let now = Timestamp::now();
    let waiting = SourceReport::default();
    let restored = read::<CollectorState>(&settings.state)
        .ok()
        .filter(|s| s.snapshot.version == VERSION);
    let mut signals = restored
        .as_ref()
        .map(|s| s.signals.clone())
        .unwrap_or_default();
    let mut snapshot: Snapshot = restored.map(|s| s.snapshot).unwrap_or(Snapshot {
        version: VERSION,
        collector_started_at: now,
        sources: Sources {
            host: waiting.clone(),
            http: waiting.clone(),
            argo: waiting.clone(),
            alerts: waiting,
        },
        host: Host::default(),
        endpoints: BTreeMap::new(),
        apps: BTreeMap::new(),
        workloads: vec![],
        alerts: vec![],
        recoveries: vec![],
    });
    snapshot.collector_started_at = now;
    snapshot.host = Host::default();
    for source in [
        &mut snapshot.sources.http,
        &mut snapshot.sources.argo,
        &mut snapshot.sources.alerts,
    ] {
        if source.newest_sample_at.is_some() {
            report(
                source,
                Err("collector restarted; awaiting refresh".into()),
                now,
            );
        }
    }
    let (sender, receiver) = mpsc::sync_channel(1);
    let worker_settings = settings.clone();
    std::thread::spawn(move || {
        loop {
            let start = Instant::now();
            if sender.send(fetch(&worker_settings)).is_err() {
                return;
            }
            std::thread::sleep(
                Duration::from_millis(worker_settings.cluster_interval_ms)
                    .saturating_sub(start.elapsed()),
            );
        }
    });
    let mut sampler = HostSampler { cpu: None };
    let mut evaluator = Evaluator::default();
    let mut metadata = Value::Null;
    let mut next_host = Instant::now();
    loop {
        let now = Timestamp::now();
        let mut changed = false;
        if Instant::now() >= next_host {
            let result = sampler.sample(&mut snapshot.host, now).map(|()| now);
            report(&mut snapshot.sources.host, result, now);
            next_host = Instant::now() + Duration::from_millis(settings.host_interval_ms);
            changed = true;
            night(&settings, now)?;
        }
        if let Ok(result) = receiver.try_recv() {
            changed = true;
            let before = snapshot.clone();
            match result {
                Ok(cluster) => {
                    let h = http(&catalog, &cluster, &mut snapshot, now);
                    report(&mut snapshot.sources.http, h, now);
                    let a = argo(&catalog, &settings, &cluster, &mut snapshot, now);
                    cluster_report(
                        &mut snapshot.sources.argo,
                        a,
                        &cluster,
                        &[
                            "argocd_app_info",
                            "kube_pod_info",
                            "kube_pod_status_phase",
                            "kube_pod_status_ready",
                            "kube_pod_container_status_restarts_total",
                        ],
                        &[
                            "argocd-application-controller-metrics",
                            "kube-state-metrics",
                        ],
                        now,
                    );
                    let alerts = alerts(
                        &catalog,
                        &settings,
                        &cluster,
                        &mut evaluator,
                        &mut snapshot,
                        now,
                    );
                    cluster_report(
                        &mut snapshot.sources.alerts,
                        alerts,
                        &cluster,
                        &["vmalert_iteration_total"],
                        &["vmalert-vm-victoria-metrics-k8s-stack"],
                        now,
                    );
                    metadata = serde_json::json!({"fetched_at": cluster.fetched_at, "evaluated_at": cluster.evaluated_at});
                }
                Err(error) => {
                    for source in [
                        &mut snapshot.sources.http,
                        &mut snapshot.sources.argo,
                        &mut snapshot.sources.alerts,
                    ] {
                        report(source, Err(error.clone()), now);
                    }
                }
            }
            recover(&catalog, &before, &mut snapshot, &mut signals, now);
        }
        snapshot
            .recoveries
            .retain(|r| now.duration_since(r.cleared_at) < health::RECOVERY_SHOWN_FOR);
        if changed {
            atomic(
                &settings.state,
                &CollectorState {
                    snapshot: snapshot.clone(),
                    signals: signals.clone(),
                },
            )?;
            let mut public = serde_json::to_value(&snapshot).map_err(|e| e.to_string())?;
            public["collection"] = metadata.clone();
            atomic(&settings.snapshot, &public)?;
        }
        // Worker waits never block host sampling. Public heartbeat tracks collector liveness.
        std::thread::sleep(
            next_host
                .saturating_duration_since(Instant::now())
                .min(Duration::from_millis(100)),
        );
    }
}
