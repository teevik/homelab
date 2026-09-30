//! The approved A · Instrument ledger (teevik/homelab#70, #71), drawn from a derived
//! [`Health`]. Rendering is a plain function of its inputs.
//!
//! At 160x50: row 0 header; rows 2-10 the status band; rows 12-15 the fixed attention
//! slot; row 16 a rule; the endpoint/app ledger left and centre; HOST and SOURCES on
//! the right; the footer on the last row. Below 150x45 the compact fallback, below
//! 60x20 only the status word and one summary line.
//!
//! Only palette slots 0-15 (grounds 0-7), no text attributes, and only glyphs the
//! 256-glyph Terminus font carries.

use crate::contract::{NightReport, NightState, Snapshot, Temperature};
use crate::health::*;
use crate::palette::*;
use crate::text::{age, fit, fit_words, is_supported, sanitize, width};
use jiff::tz::TimeZone;
use jiff::{SignedDuration, Timestamp};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};

pub const FULL_MIN: (u16, u16) = (150, 45);
pub const COMPACT_MIN: (u16, u16) = (60, 20);

/// Everything one frame is drawn from.
pub struct View<'a> {
    pub health: &'a Health,
    pub snapshot: &'a Snapshot,
    pub night: Option<&'a NightReport>,
    pub now: Timestamp,
    pub tz: &'a TimeZone,
    /// Demo entry point only: names the illustrative fixture in the header.
    pub label: Option<&'a str>,
}

/// What the frame needed from the interaction state.
pub struct Drawn {
    /// The ledger (or compact endpoint list) has more rows than fit.
    pub overflow: bool,
    /// The scroll offset after clamping to the rows that exist.
    pub scroll: usize,
}

struct Canvas<'a> {
    buf: &'a mut Buffer,
    area: Rect,
}

impl Canvas<'_> {
    fn w(&self) -> u16 {
        self.area.width
    }

    fn h(&self) -> u16 {
        self.area.height
    }

    /// Write clipped text; returns the x after it. Anything the console font cannot
    /// show becomes `?`, so no live text reaches the terminal raw.
    fn put(&mut self, x: u16, y: u16, text: &str, fg: u8, bg: u8) -> u16 {
        if y >= self.h() || x >= self.w() {
            return x;
        }
        let max = (self.w() - x) as usize;
        let t: String = text.chars().take(max).map(|c| if is_supported(c) { c } else { '?' }).collect();
        let style = Style::new().fg(Color::Indexed(fg)).bg(Color::Indexed(bg));
        self.buf.set_string(self.area.x + x, self.area.y + y, &t, style);
        x + width(&t) as u16
    }

    fn fill(&mut self, y: u16, x0: u16, x1: u16, ch: char, fg: u8, bg: u8) {
        let x1 = x1.min(self.w());
        if x0 < x1 {
            self.put(x0, y, &ch.to_string().repeat((x1 - x0) as usize), fg, bg);
        }
    }

    fn ground(&mut self, y0: u16, y1: u16, bg: u8) {
        for y in y0..y1.min(self.h()) {
            self.fill(y, 0, self.w(), ' ', BODY, bg);
        }
    }

    fn right(&mut self, x_end: u16, y: u16, text: &str, fg: u8, bg: u8) -> u16 {
        let x = x_end.saturating_sub(width(text) as u16);
        self.put(x, y, text, fg, bg);
        x
    }
}

// ---------------------------------------------------------------- wording

/// A time still ahead, in whole minutes rounded up so that it never reads "0m".
fn ahead(d: SignedDuration) -> String {
    let m = (d.as_secs().max(0) + 59) / 60;
    age(SignedDuration::from_mins(m.max(1)))
}

fn clock(t: Timestamp, tz: &TimeZone) -> String {
    t.to_zoned(tz.clone()).strftime("%H:%M").to_string()
}

fn status_word(s: Status) -> (&'static str, u8, u8) {
    match s {
        Status::AllClear => ("ALL CLEAR", OK, GROUND),
        Status::Attention => ("ATTENTION", TEXT, ALERT_GROUND),
        Status::Unknown => ("UNKNOWN", WARM, GROUND),
    }
}

fn tier_marker(t: Tier) -> (&'static str, u8) {
    match t {
        Tier::Http => ("■", FAIL),
        Tier::Alert => ("!", WARM),
        Tier::Deployment => ("▲", DEPLOY_HI),
        Tier::CoverageGap => ("?", WARM),
    }
}

fn part_colour(k: PartKind) -> u8 {
    match k {
        PartKind::Http | PartKind::AppHealth { degraded: true } => FAIL,
        PartKind::AppHealth { .. } | PartKind::AppSync | PartKind::Workload => DEPLOY_HI,
        PartKind::Alert | PartKind::Gap => WARM,
        PartKind::EndpointOk => OK,
    }
}

/// A section header's freshness: `every 30s · 21s ago`, `STALE · newest sample 4m
/// old`, `UNAVAILABLE 6m · last results` or `waiting for the first result`.
fn freshness(f: &Freshness, every: &str) -> (String, u8) {
    match f {
        Freshness::Waiting => ("waiting for the first result".into(), META),
        Freshness::Current { age: a } => (format!("every {every} · {} ago", age(*a)), META),
        Freshness::Stale { age: a } => (format!("STALE · newest sample {} old", age(*a)), WARM),
        Freshness::Unavailable { duration, .. } => (format!("UNAVAILABLE {} · last results", age(*duration)), WARM),
    }
}

fn cluster_down(h: &Health) -> bool {
    [SourceId::Http, SourceId::Argo, SourceId::Alerts].iter().all(|&id| matches!(h.source(id), Freshness::Unavailable { .. }))
}

fn headline(h: &Health) -> String {
    match h.status {
        Status::AllClear => "every check passes".into(),
        Status::Attention => {
            let signal_rows: Vec<&AttentionRow> = h.attention.iter().filter(|r| r.tier != Tier::CoverageGap).collect();
            let labels = signal_rows.iter().filter(|r| r.is_label).count();
            let services = signal_rows.len() - labels;
            let on = match (services, labels > 0) {
                (0, _) => "on the cluster".to_string(),
                (1, false) => "on 1 service".into(),
                (n, false) => format!("on {n} services"),
                (1, true) => "on 1 service and the cluster".into(),
                (n, true) => format!("on {n} services and the cluster"),
            };
            format!("{} {} {on}", h.signals, if h.signals == 1 { "signal" } else { "signals" })
        }
        Status::Unknown => {
            if h.cold_start {
                return format!("starting, waiting for first readings ({})", age(h.collector_age));
            }
            if let Freshness::Unavailable { duration, .. } = h.source(SourceId::Host)
                && cluster_down(h) {
                    return format!("every source unavailable for {}", age(*duration));
                }
            if cluster_down(h)
                && let Freshness::Unavailable { duration, .. } = h.source(SourceId::Http) {
                    return format!("cluster monitoring unavailable for {}", age(*duration));
                }
            for (id, f) in &h.sources {
                let name = if *id == SourceId::Host { "host readings" } else { id.name() };
                match f {
                    Freshness::Unavailable { duration, .. } => return format!("{name} unavailable for {}", age(*duration)),
                    Freshness::Stale { age: a } => return format!("{name} stale, newest sample {} old", age(*a)),
                    Freshness::Waiting => return format!("waiting for {name}"),
                    Freshness::Current { .. } => {}
                }
            }
            "inventory incomplete, health cannot be confirmed".into()
        }
    }
}

fn endpoints_line(h: &Health) -> (String, u8) {
    let n = h.endpoints.len();
    let responding = h.endpoints.iter().filter(|e| matches!(e.view, EndpointView::Ok { retained: false, .. })).count();
    let gaps = if h.gap_endpoints > 0 { format!(", {} without a result", h.gap_endpoints) } else { String::new() };
    match h.source(SourceId::Http) {
        Freshness::Waiting => ("endpoints: waiting for the first check".into(), META),
        Freshness::Stale { .. } | Freshness::Unavailable { .. } => ("endpoints: no current results".into(), WARM),
        Freshness::Current { .. } if h.endpoints_failing > 0 => (format!("{} of {n} endpoints failing{gaps}", h.endpoints_failing), TEXT),
        Freshness::Current { .. } => (format!("{responding} of {n} endpoints respond{gaps}"), TEXT),
    }
}

fn apps_line(h: &Health) -> (String, u8) {
    let n = h.endpoints.iter().filter_map(|e| e.app.as_ref().map(|a| &a.0)).collect::<std::collections::BTreeSet<_>>().len()
        + h.apps_without_endpoint.len();
    let gaps = if h.gap_apps > 0 { format!(", {} not reported", h.gap_apps) } else { String::new() };
    match h.source(SourceId::Argo) {
        Freshness::Waiting => ("apps: waiting for argo cd".into(), META),
        Freshness::Stale { .. } | Freshness::Unavailable { .. } => ("apps: no current status".into(), WARM),
        Freshness::Current { .. } if h.apps_unhealthy + h.apps_out_of_sync > 0 => {
            (format!("{} of {n} apps unhealthy, {} out of sync{gaps}", h.apps_unhealthy, h.apps_out_of_sync), TEXT)
        }
        Freshness::Current { .. } if h.gap_apps > 0 => (format!("{} of {n} apps healthy{gaps}", h.apps_known - h.gap_apps.min(h.apps_known)), TEXT),
        Freshness::Current { .. } => (format!("{n} of {n} apps synced and healthy"), TEXT),
    }
}

fn alerts_line(h: &Health) -> (String, u8) {
    match h.source(SourceId::Alerts) {
        Freshness::Waiting => ("alerts: waiting for alertmanager".into(), META),
        Freshness::Unavailable { .. } => ("alerts: unknown, alertmanager unavailable".into(), WARM),
        Freshness::Stale { .. } => ("alerts: unknown, alertmanager stale".into(), WARM),
        Freshness::Current { .. } => match h.alerts {
            0 => ("no active alerts".into(), TEXT),
            1 => ("1 active alert".into(), TEXT),
            n => (format!("{n} active alerts"), TEXT),
        },
    }
}

fn coverage_line(h: &Health) -> (String, u8) {
    let host_current = h.source(SourceId::Host).is_current();
    if h.cold_start {
        return if host_current { ("host readings current".into(), META) } else { ("waiting for host readings".into(), META) };
    }
    if cluster_down(h) {
        return if host_current { ("host readings still current".into(), WARM) } else { ("no source is current".into(), WARM) };
    }
    let bad: Vec<String> = h
        .sources
        .iter()
        .filter_map(|(id, f)| match f {
            Freshness::Waiting => Some(format!("{} waiting", id.name())),
            Freshness::Stale { .. } => Some(format!("{} stale", id.name())),
            Freshness::Unavailable { .. } => Some(format!("{} unavailable", id.name())),
            Freshness::Current { .. } => None,
        })
        .collect();
    if !bad.is_empty() {
        (format!("partial coverage: {}", bad.join(", ")), WARM)
    } else if h.gap_endpoints + h.gap_apps > 0 {
        ("partial coverage: catalog entries without data".into(), WARM)
    } else {
        let oldest = h
            .sources
            .iter()
            .filter_map(|(_, f)| if let Freshness::Current { age } = f { Some(*age) } else { None })
            .max()
            .unwrap_or_default();
        (format!("all sources current, oldest {}", age(oldest)), META)
    }
}

fn empty_slot(h: &Health) -> (&'static str, u8) {
    match h.status {
        Status::AllClear => ("Nothing needs attention.", META),
        _ if h.cold_start => ("Waiting for first readings. Nothing is known to need attention yet.", META),
        _ => ("No known problems, but health cannot be confirmed until every source is current.", WARM),
    }
}

fn night_text(night: Option<&NightReport>, now: Timestamp, tz: &TimeZone) -> Vec<(String, u8)> {
    let Some(r) = night else {
        return vec![("night schedule state not reported".into(), META)];
    };
    let expired = match &r.state {
        NightState::Day { next_dark_at } => *next_dark_at <= now,
        NightState::QuietHours { until, wake_until } | NightState::Bedtime { until, wake_until } => {
            *until <= now || wake_until.is_some_and(|w| w <= now)
        }
    };
    if expired {
        return vec![("night schedule state out of date".into(), WARM)];
    }
    let (from, to) = (sanitize(&r.dark_from), sanitize(&r.dark_until));
    let intent = match &r.state {
        NightState::Day { next_dark_at } => format!("screen dark {from}-{to}, in {}", ahead(next_dark_at.duration_since(now))),
        NightState::QuietHours { until, wake_until } | NightState::Bedtime { until, wake_until } => {
            let what = if matches!(r.state, NightState::Bedtime { .. }) { "bedtime" } else { "quiet hours" };
            match wake_until {
                Some(w) => format!(
                    "{what} until {} · woken, dark again at {} (in {})",
                    clock(*until, tz),
                    clock(*w, tz),
                    ahead(w.duration_since(now))
                ),
                None => format!("{what} until {} · screen dark", clock(*until, tz)),
            }
        }
    };
    let mut out = vec![(intent, COOL)];
    if let Some(f) = &r.failure {
        out.push((format!(" · control failed: {}", sanitize(&f.reason)), WARM));
    }
    out
}

// ---------------------------------------------------------------- block letters

fn glyph(c: char) -> (&'static [&'static str; 7], u16) {
    const A: [&str; 7] = [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"];
    const C: [&str; 7] = [" ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####"];
    const E: [&str; 7] = ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"];
    const I: [&str; 7] = ["###", " # ", " # ", " # ", " # ", " # ", "###"];
    const K: [&str; 7] = ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"];
    const L: [&str; 7] = ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"];
    const N: [&str; 7] = ["#   #", "##  #", "##  #", "# # #", "#  ##", "#  ##", "#   #"];
    const O: [&str; 7] = [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "];
    const R: [&str; 7] = ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"];
    const T: [&str; 7] = ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "];
    const U: [&str; 7] = ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "];
    const W: [&str; 7] = ["#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #"];
    const SP: [&str; 7] = ["  ", "  ", "  ", "  ", "  ", "  ", "  "];
    match c {
        'A' => (&A, 5),
        'C' => (&C, 5),
        'E' => (&E, 5),
        'I' => (&I, 3),
        'K' => (&K, 5),
        'L' => (&L, 5),
        'N' => (&N, 5),
        'O' => (&O, 5),
        'R' => (&R, 5),
        'T' => (&T, 5),
        'U' => (&U, 5),
        'W' => (&W, 5),
        _ => (&SP, 2),
    }
}

fn big_width(word: &str, scale: u16) -> u16 {
    let px: u16 = word.chars().map(|c| glyph(c).1 + 1).sum::<u16>() - 1;
    px * scale
}

/// `word` in a 5x7 pixel font; a pixel is `scale` cells wide and `scale` half-cells
/// tall, so it stays square in a 16x32 cell.
fn big(c: &mut Canvas, x: u16, y: u16, word: &str, scale: u16, fg: u8, bg: u8) {
    let w = big_width(word, scale) as usize;
    let s = scale as usize;
    let hh = 7 * s;
    let mut on = vec![vec![false; w]; hh + 1];
    let mut px = 0usize;
    for ch in word.chars() {
        let (rows, gw) = glyph(ch);
        for (ry, row) in rows.iter().enumerate() {
            for (rx, b) in row.chars().enumerate() {
                if b == '#' {
                    for sy in 0..s {
                        for sx in 0..s {
                            on[ry * s + sy][(px + rx) * s + sx] = true;
                        }
                    }
                }
            }
        }
        px += gw as usize + 1;
    }
    for r in 0..hh.div_ceil(2) {
        let line: String = (0..w)
            .map(|col| match (on[2 * r][col], on[2 * r + 1][col]) {
                (true, true) => '█',
                (true, false) => '▀',
                (false, true) => '▄',
                _ => ' ',
            })
            .collect();
        c.put(x, y + r as u16, &line, fg, bg);
    }
}

// ---------------------------------------------------------------- attention

/// Word-wrap `text` into at most `max_lines` lines of `w` cells; the last line is
/// fitted at a word boundary if the text still does not fit.
fn wrap(text: &str, w: usize, max_lines: usize) -> Vec<String> {
    let mut lines: Vec<String> = vec![];
    let mut rest = text;
    while !rest.is_empty() && lines.len() < max_lines {
        if width(rest) <= w || lines.len() + 1 == max_lines {
            lines.push(fit(rest, w));
            break;
        }
        let cut = rest.char_indices().take_while(|(i, _)| width(&rest[..*i]) <= w).filter(|(_, c)| *c == ' ').map(|(i, _)| i).last();
        let Some(cut) = cut else {
            lines.push(fit(rest, w));
            break;
        };
        lines.push(rest[..cut].to_string());
        rest = rest[cut..].trim_start();
    }
    lines
}

/// Where one attention row's columns sit.
struct RowGeometry {
    marker: u16,
    service: u16,
    service_w: usize,
    parts: u16,
    /// Right edge for signal text; `since` is right-aligned beyond it at `since_end`.
    parts_end: u16,
    since_end: u16,
    /// "since 4m" at full size, "4m" in the compact fallback.
    since_word: bool,
}

fn attention_row(c: &mut Canvas, y: u16, row: &AttentionRow, g: &RowGeometry, now: Timestamp) {
    let (m, mc) = tier_marker(row.tier);
    c.put(g.marker, y, m, mc, GROUND);
    c.put(g.service, y, &fit(&sanitize(&row.service), g.service_w), TEXT, GROUND);
    // signals joined by " · ", ending in "+n more" rather than cut mid-word
    let texts: Vec<String> = row.parts.iter().map(|p| sanitize(&p.text)).collect();
    let more = |from: usize| row.parts[from..].iter().filter(|p| p.kind.is_signal()).count();
    let mut x = g.parts;
    for (j, (p, t)) in row.parts.iter().zip(&texts).enumerate() {
        let sep = if j > 0 { 5 } else { 0 };
        let reserve = match more(j + 1) {
            0 => 0,
            n => width(&format!("  +{n} more")) as u16,
        };
        let room = g.parts_end.saturating_sub(x + sep + reserve) as usize;
        let colour = part_colour(p.kind);
        // a first signal too long for the row is fitted at a word boundary
        let shown = if width(t) <= room { Some(t.clone()) } else if j == 0 { fit_words(t, room) } else { None };
        let Some(shown) = shown else {
            if more(j) > 0 {
                c.put(x + 2, y, &format!("+{} more", more(j)), META, GROUND);
            }
            break;
        };
        if j > 0 {
            x = c.put(x, y, "  ·  ", RULE, GROUND);
        }
        x = c.put(x, y, &shown, colour, GROUND);
        if width(&shown) < width(t) {
            if more(j + 1) > 0 {
                c.put(x + 2, y, &format!("+{} more", more(j + 1)), META, GROUND);
            }
            break;
        }
    }
    let since = match (row.since, row.tier) {
        (Some(t), _) if g.since_word => format!("since {}", age(now.duration_since(t))),
        (Some(t), _) => age(now.duration_since(t)),
        (None, Tier::CoverageGap) if g.since_word => "expected by catalog".into(),
        (None, Tier::CoverageGap) => "expected".into(),
        // no reported onset: nothing is invented
        (None, _) => String::new(),
    };
    c.right(g.since_end, y, &since, META, GROUND);
}

/// A fixed slot of `slots` rows that never scrolls: all rows when they fit, otherwise
/// `slots - 1` plus a named `+n more` line.
fn attention_slot(c: &mut Canvas, v: &View, y0: u16, slots: usize, g: &RowGeometry) {
    let h = v.health;
    let rows = &h.attention;
    if rows.is_empty() {
        let (text, colour) = empty_slot(h);
        let lines = wrap(text, c.w().saturating_sub(g.marker + 1) as usize, slots);
        for (i, line) in lines.iter().enumerate() {
            c.put(g.marker, y0 + i as u16, line, colour, GROUND);
        }
        for (i, r) in h.recoveries.iter().take(slots - lines.len()).enumerate() {
            let y = y0 + (lines.len() + i) as u16;
            c.put(g.marker, y, "·", OK, GROUND);
            c.put(g.service, y, &fit(&sanitize(&r.service), g.service_w), BODY, GROUND);
            let x = c.put(g.parts, y, "recovered", OK, GROUND);
            let detail = format!("  ·  was {} for {}  ·  ok since {}", sanitize(&r.problem), age(r.lasted), clock(r.cleared_at, v.tz));
            c.put(x, y, &fit(&detail, c.w().saturating_sub(x + 1) as usize), META, GROUND);
        }
        return;
    }
    let shown = if rows.len() > slots { slots - 1 } else { rows.len() };
    for (i, row) in rows.iter().take(shown).enumerate() {
        attention_row(c, y0 + i as u16, row, g, v.now);
    }
    if rows.len() > slots {
        let y = y0 + shown as u16;
        let more = &rows[shown..];
        c.put(g.service, y, &format!("+{} more:", more.len()), WARM, GROUND);
        let tail = " (highlighted below)";
        let room = g.since_end.saturating_sub(g.parts) as usize - width(tail);
        let mut names = String::new();
        for (i, r) in more.iter().enumerate() {
            let name = sanitize(&r.service);
            let sep = if i == 0 { "" } else { ", " };
            let left = more.len() - i - 1;
            let need = width(&names) + width(sep) + width(&name) + if left > 0 { width(", ...") } else { 0 };
            if need > room {
                names.push_str(if i == 0 { "..." } else { ", ..." });
                break;
            }
            names.push_str(sep);
            names.push_str(&name);
        }
        let x = c.put(g.parts, y, &names, BODY, GROUND);
        c.put(x, y, tail, META, GROUND);
    }
}

// ---------------------------------------------------------------- instruments

fn heat(v: f32, warm: f32, hot: f32) -> u8 {
    if v >= hot {
        HOT
    } else if v >= warm {
        WARM
    } else {
        COOL
    }
}

/// Presentation thresholds only, never health signals: meters warm at 80%, hot at 90%.
fn meter_colour(pct: f32) -> u8 {
    heat(pct, 80.0, 90.0)
}

/// Presentation thresholds only: temperature warm at 70 °C, hot at 80 °C.
fn temp_colour(t: f32) -> u8 {
    heat(t, 70.0, 80.0)
}

fn meter(c: &mut Canvas, x: u16, y: u16, cells: u16, pct: Option<f32>, dim: bool) -> u16 {
    let Some(pct) = pct else {
        c.fill(y, x, x + cells, '░', RULE, GROUND);
        return x + cells;
    };
    let full = ((pct.clamp(0.0, 100.0) * cells as f32 / 100.0).round() as u16).min(cells);
    c.fill(y, x, x + full, '█', if dim { META } else { meter_colour(pct) }, GROUND);
    c.fill(y, x + full, x + cells, '░', RULE, GROUND);
    x + cells
}

struct Readings {
    cpu: Option<f32>,
    threads: Option<u32>,
    mem: Option<(f32, String)>,
    root: Option<(f32, String)>,
}

fn readings(s: &Snapshot) -> Readings {
    let gib = |b: u64| b as f64 / (1u64 << 30) as f64;
    let used = |c: &crate::contract::Capacity| {
        if c.total_bytes == 0 { 0.0 } else { 100.0 * (c.total_bytes.saturating_sub(c.available_bytes)) as f32 / c.total_bytes as f32 }
    };
    let h = &s.host;
    Readings {
        cpu: h.cpu_percent,
        threads: h.cpu_threads,
        mem: h.memory.map(|m| (used(&m), format!("{:.1} / {:.1} GiB", gib(m.total_bytes - m.available_bytes.min(m.total_bytes)), gib(m.total_bytes)))),
        root: h.root.map(|r| (used(&r), format!("{:.0} GiB free", gib(r.available_bytes)))),
    }
}

/// Minute columns ending now: supplied history, then a gap for every minute since it
/// ended. Missing minutes are never interpolated.
fn history_columns(s: &Snapshot, now: Timestamp) -> Vec<Option<f32>> {
    let h = &s.host.temperature_history;
    let mut cols = h.celsius.clone();
    if let (Some(end), false) = (h.end, cols.is_empty()) {
        let behind = (now.duration_since(end).as_secs().max(0) / 60) as usize;
        cols.extend(std::iter::repeat_n(None, behind.min(240)));
    }
    cols
}

/// Temperature history: one column per minute, half-block resolution, 40-95 °C.
fn chart(c: &mut Canvas, x: u16, y: u16, cols: u16, rows: u16, hist: &[Option<f32>]) {
    let (lo, hi) = (40.0, 95.0);
    let levels = (rows * 2) as f32;
    let shown = &hist[hist.len().saturating_sub(cols as usize)..];
    let x0 = x + cols - shown.len() as u16;
    for (i, v) in shown.iter().enumerate() {
        let cx = x0 + i as u16;
        match v {
            None => {
                c.put(cx, y + rows - 1, "·", META, GROUND);
            }
            Some(t) => {
                let lvl = (((*t - lo) / (hi - lo)).clamp(0.0, 1.0) * levels).round() as u16;
                for r in 0..rows {
                    let rb = rows - 1 - r;
                    let ch = if lvl >= 2 * (rb + 1) {
                        "█"
                    } else if lvl == 2 * rb + 1 {
                        "▄"
                    } else {
                        " "
                    };
                    c.put(cx, y + r, ch, temp_colour(*t), GROUND);
                }
            }
        }
    }
    c.fill(y + rows, x, x + cols, '─', RULE, GROUND);
    if shown.is_empty() {
        c.put(x, y + rows + 1, "no history yet, it builds from now", META, GROUND);
    } else {
        c.put(x, y + rows + 1, &format!("-{}m", shown.len()), META, GROUND);
    }
    c.right(x + cols, y + rows + 1, "now", META, GROUND);
}

fn reasons(h: &Health) -> Vec<String> {
    let mut out: Vec<String> = vec![];
    for (_, f) in &h.sources {
        if let Freshness::Unavailable { reason, .. } = f {
            let r = sanitize(reason);
            if !out.contains(&r) {
                out.push(r);
            }
        }
    }
    out
}

fn host_column(c: &mut Canvas, v: &View, hx: u16) {
    let h = v.health;
    let bottom = c.h() - 3;
    for y in 17..=bottom {
        c.put(hx - 3, y, "│", RULE, GROUND);
    }
    c.put(hx, 17, "HOST", LABEL, GROUND);
    let host = h.source(SourceId::Host);
    let (f, fc) = freshness(host, "5s");
    c.put(hx + 5, 17, &f, fc, GROUND);
    let dim = !host.is_current();
    let r = readings(v.snapshot);
    let mw = c.w().saturating_sub(134).clamp(16, 26);
    let cpu_detail = match (r.cpu, r.threads) {
        (None, _) if matches!(host, Freshness::Waiting) => "waiting".to_string(),
        (None, _) => "measuring".to_string(),
        (Some(_), Some(t)) => format!("{t} threads"),
        (Some(_), None) => String::new(),
    };
    let lines = [
        ("cpu", r.cpu, cpu_detail),
        ("mem", r.mem.as_ref().map(|m| m.0), r.mem.as_ref().map_or("no reading".into(), |m| m.1.clone())),
        ("root", r.root.as_ref().map(|m| m.0), r.root.as_ref().map_or("no reading".into(), |m| m.1.clone())),
    ];
    for (i, (label, pct, detail)) in lines.iter().enumerate() {
        let y = 19 + i as u16 * 2;
        c.put(hx, y, label, BODY, GROUND);
        let x = meter(c, hx + 5, y, mw, *pct, dim);
        match pct {
            Some(p) => c.right(x + 5, y, &format!("{:.0}%", p), if dim { META } else { TEXT }, GROUND),
            None => c.right(x + 5, y, "--", META, GROUND),
        };
        c.put(x + 7, y, &fit(detail, c.w().saturating_sub(x + 8) as usize), META, GROUND);
    }

    let ty = 26;
    c.put(hx, ty, "cpu temp", BODY, GROUND);
    let why = reasons(h);
    // the chart gives way to SOURCES on shorter consoles
    let chart_rows = (bottom as i32 - ty as i32 - 5 - 4 - why.len() as i32).clamp(3, 8) as u16;
    let cols = c.w().saturating_sub(hx + 6).min(60);
    match &v.snapshot.host.temperature {
        Temperature::Reading { celsius, sensor } => {
            let colour = if dim { META } else if *celsius < 70.0 { TEXT } else { temp_colour(*celsius) };
            let x = c.put(hx + 10, ty, &format!("{:.0}°C", celsius), colour, GROUND);
            c.put(x + 2, ty, &fit(&sanitize(sensor), 20), META, GROUND);
            let scale = [("90°", 90.0), ("70°", 70.0), ("50°", 50.0)];
            for (lbl, t) in scale {
                let r = ((95.0 - t) / 55.0 * chart_rows as f32).floor() as u16;
                c.put(hx, ty + 2 + r.min(chart_rows - 1), lbl, META, GROUND);
            }
            chart(c, hx + 5, ty + 2, cols, chart_rows, &history_columns(v.snapshot, v.now));
        }
        Temperature::Unavailable => {
            c.put(hx + 10, ty, "unavailable", META, GROUND);
            c.put(hx + 10, ty + 2, "No CPU package sensor was found.", META, GROUND);
            c.put(hx + 10, ty + 3, "This does not affect service health.", META, GROUND);
        }
        Temperature::Waiting => {
            c.put(hx + 10, ty, "waiting for the first reading", META, GROUND);
        }
    }

    let sy = ty + 5 + chart_rows;
    c.put(hx, sy, "SOURCES", LABEL, GROUND);
    c.put(hx + 8, sy, "age of the newest sample", META, GROUND);
    let mut y = sy + 1;
    for (id, f) in &h.sources {
        let (dot, dc, a, word, wc) = match f {
            Freshness::Waiting => ("·", META, "--".to_string(), "waiting", META),
            Freshness::Current { age: a } => ("·", OK, age(*a), "current", OK),
            Freshness::Stale { age: a } => ("?", WARM, age(*a), "stale", WARM),
            Freshness::Unavailable { duration, .. } => ("?", WARM, age(*duration), "unavailable", WARM),
        };
        c.put(hx, y, dot, dc, GROUND);
        c.put(hx + 2, y, id.name(), BODY, GROUND);
        c.right(hx + 22, y, &a, META, GROUND);
        c.put(hx + 24, y, word, wc, GROUND);
        y += 1;
    }
    // one reason line per distinct cause
    for r in why {
        if y > bottom {
            break;
        }
        c.put(hx + 2, y, &fit(&r, c.w().saturating_sub(hx + 3) as usize), META, GROUND);
        y += 1;
    }
}

// ---------------------------------------------------------------- header, footer

fn header(c: &mut Canvas, v: &View) {
    c.ground(0, 1, BAR);
    let x = c.put(1, 0, "HOMELAB", BRAND, BAR);
    if c.w() >= FULL_MIN.0 {
        c.put(x + 2, 0, "host health", META, BAR);
    }
    let zoned = v.now.to_zoned(v.tz.clone());
    let when = format!("{}  {} ", zoned.strftime("%a %-d %b"), zoned.strftime("%H:%M"));
    let right = c.right(c.w(), 0, &when, TEXT, BAR);
    if let Some(label) = v.label {
        let text = fit(&format!("ILLUSTRATIVE FIXTURE · {label}"), right.saturating_sub(x + 4) as usize);
        let n = width(&text) as u16;
        let cx = (c.w() / 2).saturating_sub(n / 2).clamp(x + 2, right.saturating_sub(n + 2).max(x + 2));
        c.put(cx, 0, &text, WARM, BAR);
    }
}

fn footer(c: &mut Canvas, v: &View, overflow: bool) {
    let y = c.h() - 1;
    // the approved wording, shortened only when the console is too narrow for it
    let short = c.w() < 100;
    c.ground(y, y + 1, BAR);
    let mut x = c.put(1, y, "Ctrl+C", TEXT, BAR);
    x = c.put(x + 1, y, if short { "close" } else { "close, monitoring keeps running" }, META, BAR);
    if overflow {
        x = c.put(x + 4, y, "↑↓", TEXT, BAR);
        x = c.put(x + 1, y, if short { "scroll" } else { "scroll services" }, META, BAR);
    }
    // the controller's reported state, only when it fits whole
    let segments = night_text(v.night, v.now, v.tz);
    let total: usize = segments.iter().map(|(t, _)| width(t)).sum::<usize>() + 1;
    if (x + 4) as usize + total <= c.w() as usize {
        let mut nx = c.w() - total as u16;
        for (t, colour) in segments {
            nx = c.put(nx, y, &t, colour, BAR);
        }
    } else if let Some((t, colour)) = segments.first()
        && (x + 4) as usize + width(t) < c.w() as usize {
            c.right(c.w() - 1, y, t, *colour, BAR);
        }
}

// ---------------------------------------------------------------- the ledger

enum LedgerRow<'a> {
    Gap,
    Label(&'static str),
    Endpoint(&'a LedgerEndpoint),
    App(&'a (String, AppView)),
}

fn app_columns(c: &mut Canvas, y: u16, (id, view): &(String, AppView), (xa, xs, xh): (u16, u16, u16)) {
    let id = fit(&sanitize(id), (xs - xa - 1) as usize);
    match view {
        AppView::Waiting => {
            c.put(xa, y, &id, BODY, GROUND);
            c.put(xs, y, "waiting", META, GROUND);
        }
        AppView::Missing => {
            c.put(xa, y, &id, TEXT, GROUND);
            c.put(xs, y, "?", WARM, GROUND);
            c.put(xh, y, "not reported", WARM, GROUND);
        }
        AppView::NoResult => {
            c.put(xa, y, &id, META, GROUND);
            c.put(xs, y, "no result", META, GROUND);
        }
        AppView::Known { sync, health, synced, healthy, degraded, retained, old } => {
            let (st, sc) = if *synced { ("synced".to_string(), DEPLOY) } else { (sanitize(sync), DEPLOY_HI) };
            let (ht, hc) = match (healthy, degraded) {
                (true, _) => ("healthy".to_string(), DEPLOY),
                (_, true) => ("Degraded".to_string(), FAIL),
                _ => (sanitize(health), DEPLOY_HI),
            };
            let problem = !synced || !healthy;
            // retained ok values lose their colour; known problems keep full strength
            let dim = |col: u8, bad: bool| if *retained && !bad { META } else { col };
            c.put(xa, y, &id, dim(if problem { TEXT } else { BODY }, problem), GROUND);
            match old {
                Some(a) => c.put(xs, y, &format!("{} old", age(*a)), WARM, GROUND),
                None => c.put(xs, y, &fit(&st, (xh - xs - 1) as usize), dim(sc, !synced), GROUND),
            };
            c.put(xh, y, &fit(&ht, 16), dim(hc, !healthy), GROUND);
        }
    }
}

fn endpoint_columns(c: &mut Canvas, y: u16, e: &LedgerEndpoint, (xm, xn, xc, xl, xd): (u16, u16, u16, u16, u16), now: Timestamp) {
    let failing = matches!(e.view, EndpointView::Fail { .. });
    let bg = if failing { ALERT_GROUND } else { GROUND };
    if failing {
        c.fill(y, xm - 1, xd, ' ', BODY, bg);
    }
    let name = fit(&sanitize(&e.name), (xc - xn - 1) as usize);
    let lat_end = xl + 6;
    match &e.view {
        EndpointView::Waiting => {
            c.put(xn, y, &name, BODY, bg);
            c.put(xc, y, "waiting", META, bg);
        }
        EndpointView::Missing => {
            c.put(xm, y, "?", WARM, bg);
            c.put(xn, y, &name, TEXT, bg);
            c.put(xc, y, "no result", WARM, bg);
            c.right(lat_end, y, "--", META, bg);
        }
        EndpointView::NoResult => {
            c.put(xn, y, &name, META, bg);
            c.put(xc, y, "no result", META, bg);
            c.right(lat_end, y, "--", META, bg);
        }
        EndpointView::Ok { latency_ms, retained, old } => {
            match old {
                Some(a) => {
                    c.put(xm, y, "?", WARM, bg);
                    c.put(xn, y, &name, TEXT, bg);
                    c.put(xc, y, "ok", META, bg);
                    c.right(lat_end, y, &format!("{} old", age(*a)), WARM, bg);
                }
                None => {
                    // last-known ok from a stale or unavailable source: dimmed, never green
                    let (mc, nc) = if *retained { (META, META) } else { (OK, BODY) };
                    c.put(xm, y, "·", mc, bg);
                    c.put(xn, y, &name, nc, bg);
                    c.put(xc, y, "ok", mc, bg);
                    c.right(lat_end, y, &format!("{latency_ms} ms"), META, bg);
                }
            }
        }
        EndpointView::Fail { reason, since } => {
            c.put(xm, y, "■", FAIL, bg);
            c.put(xn, y, &name, TEXT, bg);
            c.put(xc, y, &fit(&sanitize(reason), (xl - xc - 1) as usize), FAIL, bg);
            c.right(lat_end, y, &format!("for {}", age(now.duration_since(*since))), TEXT, bg);
        }
    }
}

fn full(c: &mut Canvas, v: &View, scroll: usize) -> Drawn {
    let h = v.health;
    header(c, v);
    let (word, wc, ground) = status_word(h.status);
    c.ground(2, 11, ground);
    big(c, 3, 3, word, 2, wc, ground);
    // anchored to ATTENTION's width so the summary never moves between states
    let sx = 3 + big_width("ATTENTION", 2) + 6;
    let lines = [(headline(h), TEXT), endpoints_line(h), apps_line(h), alerts_line(h), coverage_line(h)];
    for (i, (t, col)) in lines.iter().enumerate() {
        let col = if ground == ALERT_GROUND && *col == WARM { TEXT } else { *col };
        c.put(sx, 3 + i as u16 + (i >= 3) as u16, &fit(t, c.w().saturating_sub(sx + 1) as usize), col, ground);
    }
    let geometry = RowGeometry { marker: 3, service: 5, service_w: 19, parts: 25, parts_end: c.w() - 16, since_end: c.w() - 2, since_word: true };
    attention_slot(c, v, 12, 4, &geometry);
    c.fill(16, 1, c.w() - 1, '─', RULE, GROUND);

    let (xm, xn, xc, xl, xd, xa, xs, xh) = (3, 5, 24, 40, 49, 51, 71, 83);
    let hx = 101;
    c.put(xm, 17, "ENDPOINTS", LABEL, GROUND);
    let (f, fc) = freshness(h.source(SourceId::Http), "30s");
    c.put(xm + 10, 17, &f, fc, GROUND);
    c.put(xa, 17, "DEPLOYMENT", LABEL, GROUND);
    let (f, fc) = freshness(h.source(SourceId::Argo), "30s");
    c.put(xa + 11, 17, &fit(&f, (hx - 4 - xa - 11) as usize), fc, GROUND);
    for (x, t) in [(xn, "service"), (xc, "check"), (xl, "latency"), (xa, "app"), (xs, "sync"), (xh, "health")] {
        c.put(x, 18, t, META, GROUND);
    }

    let mut rows = vec![];
    for (i, e) in h.endpoints.iter().enumerate() {
        if i > 0 && i % 4 == 0 {
            rows.push(LedgerRow::Gap);
        }
        rows.push(LedgerRow::Endpoint(e));
    }
    if !h.apps_without_endpoint.is_empty() {
        rows.push(LedgerRow::Gap);
        rows.push(LedgerRow::Label("apps without an endpoint"));
        rows.extend(h.apps_without_endpoint.iter().map(LedgerRow::App));
    }
    let bottom = c.h() - 3;
    let fits = (bottom - 19) as usize;
    // once scrolled, the first ledger row carries the "above" cue
    let scroll = if rows.len() > fits { scroll.min(rows.len() - (fits - 1)) } else { 0 };
    let (top, avail) = if scroll > 0 { (20, fits - 1) } else { (19, fits) };
    for (i, r) in rows.iter().skip(scroll).take(avail).enumerate() {
        let y = top + i as u16;
        match r {
            LedgerRow::Gap => {}
            LedgerRow::Label(t) => {
                c.put(xa, y, t, META, GROUND);
            }
            LedgerRow::Endpoint(e) => {
                endpoint_columns(c, y, e, (xm, xn, xc, xl, xd), v.now);
                c.put(xd, y, "│", RULE, GROUND);
                match &e.app {
                    Some(app) => app_columns(c, y, app, (xa, xs, xh)),
                    None => {
                        c.put(xa, y, "no app (host)", META, GROUND);
                    }
                }
            }
            LedgerRow::App(app) => {
                c.put(xd, y, "│", RULE, GROUND);
                app_columns(c, y, app, (xa, xs, xh));
            }
        }
    }
    let overflow = rows.len() > fits;
    if scroll + avail < rows.len() {
        c.put(xn, bottom, &format!("↓ {} more rows", rows.len() - scroll - avail), WARM, GROUND);
    }
    if scroll > 0 {
        c.put(xn, 19, &format!("↑ {scroll} above"), WARM, GROUND);
    }
    host_column(c, v, hx);
    footer(c, v, overflow);
    Drawn { overflow, scroll }
}

// ---------------------------------------------------------------- compact fallback

/// Below 150x45: status, up to three problems, a two-column endpoint list in catalog
/// order, one apps line and two instrument lines.
fn compact(c: &mut Canvas, v: &View, scroll: usize) -> Drawn {
    let h = v.health;
    let w = c.w();
    header(c, v);
    let (word, wc, ground) = status_word(h.status);
    let sx = 2 + big_width("ATTENTION", 1) + 3;
    let beside = w >= sx + 30;
    let band_end = if beside { 7 } else { 8 };
    c.ground(1, band_end, ground);
    big(c, 2, 2, word, 1, wc, ground);
    let col = |col: u8| if ground == ALERT_GROUND && col == WARM { TEXT } else { col };
    if beside {
        let lines = [(headline(h), TEXT), endpoints_line(h), alerts_line(h), coverage_line(h)];
        for (i, (t, colour)) in lines.iter().enumerate() {
            c.put(sx, 2 + i as u16, &fit(t, (w - sx - 1) as usize), col(*colour), ground);
        }
    } else {
        let (cov, cc) = coverage_line(h);
        c.put(2, 6, &fit(&headline(h), (w - 3) as usize), TEXT, ground);
        c.put(2, 7, &fit(&cov, (w - 3) as usize), col(cc), ground);
    }

    let geometry = RowGeometry { marker: 2, service: 4, service_w: 16, parts: 21, parts_end: w - 7, since_end: w - 1, since_word: false };
    attention_slot(c, v, band_end + 1, 3, &geometry);
    let rule = band_end + 4;
    c.fill(rule, 1, w - 1, '─', RULE, GROUND);

    // endpoints: two columns, catalog order running down the first column
    let top = rule + 1;
    let apps_y = c.h() - 4;
    let n = h.endpoints.len();
    let per_col = n.div_ceil(2);
    let mut avail = apps_y.saturating_sub(top) as usize;
    let overflow = per_col > avail;
    if overflow {
        avail = avail.saturating_sub(1); // the last row carries the scroll cue
    }
    let scroll = scroll.min(per_col.saturating_sub(avail));
    let colw = (w - 4) / 2;
    for (i, e) in h.endpoints.iter().enumerate() {
        let (column, row) = (i / per_col, i % per_col);
        if row < scroll || row - scroll >= avail {
            continue;
        }
        let (x, y) = (2 + column as u16 * colw, top + (row - scroll) as u16);
        let failing = matches!(e.view, EndpointView::Fail { .. });
        let (marker, mc, nc, note, notec) = match &e.view {
            EndpointView::Waiting => (" ", META, META, "waiting".to_string(), META),
            EndpointView::Missing => ("?", WARM, TEXT, "no result".into(), WARM),
            EndpointView::NoResult => (" ", META, META, "no result".into(), META),
            EndpointView::Ok { old: Some(a), .. } => ("?", WARM, TEXT, format!("{} old", age(*a)), WARM),
            EndpointView::Ok { retained: true, .. } => ("·", META, META, String::new(), META),
            EndpointView::Ok { .. } => ("·", OK, BODY, String::new(), META),
            EndpointView::Fail { reason, .. } => ("■", FAIL, TEXT, sanitize(reason), FAIL),
        };
        let bg = if failing { ALERT_GROUND } else { GROUND };
        if failing {
            c.fill(y, x - 1, x + colw - 1, ' ', BODY, bg);
        }
        c.put(x, y, marker, mc, bg);
        let name_w = (colw as usize).saturating_sub(4).min(18);
        c.put(x + 2, y, &fit(&sanitize(&e.name), name_w), nc, bg);
        let room = (colw as usize).saturating_sub(name_w + 5);
        if !note.is_empty() && room > 0 {
            // whole words only: the full note, else a failure's last word ("503")
            let last = note.rsplit(' ').next().unwrap_or("");
            let fitted = if width(&note) <= room {
                Some(note.as_str())
            } else if failing && width(last) <= room {
                Some(last)
            } else {
                None
            };
            if let Some(t) = fitted {
                c.right(x + colw - 2, y, t, notec, bg);
            }
        }
    }
    if overflow {
        let y = top + avail as u16;
        let below = per_col - scroll - avail;
        if below > 0 {
            c.put(4, y, &format!("↓ {below} more rows"), WARM, GROUND);
        }
        if scroll > 0 {
            c.right(w - 2, y, &format!("↑ {scroll} above"), WARM, GROUND);
        }
    }

    let (apps, ac) = apps_line(h);
    let x = c.put(2, apps_y, "apps", BODY, GROUND);
    let quiet = if ac == TEXT { DEPLOY } else { ac };
    c.put(x + 2, apps_y, &fit(apps.trim_start_matches("apps: "), (w - x - 3) as usize), quiet, GROUND);

    // two instrument lines
    let host = h.source(SourceId::Host);
    let dim = !host.is_current();
    let r = readings(v.snapshot);
    let mw = ((w as i32 - 27) / 2).clamp(4, 20) as u16;
    let gauge = |c: &mut Canvas, x: u16, y: u16, label: &str, pct: Option<f32>| {
        let x = c.put(x, y, label, BODY, GROUND);
        let x = meter(c, x + (5 - label.len() as u16), y, mw, pct, dim);
        match pct {
            Some(p) => c.right(x + 5, y, &format!("{p:.0}%"), if dim { META } else { TEXT }, GROUND),
            None => c.right(x + 5, y, "--", META, GROUND),
        };
        x + 5
    };
    let y1 = c.h() - 3;
    let x = gauge(c, 2, y1, "cpu", r.cpu);
    gauge(c, x + 3, y1, "mem", r.mem.map(|m| m.0));
    let x = gauge(c, 2, y1 + 1, "root", r.root.map(|m| m.0));
    let tx = c.put(x + 3, y1 + 1, "temp ", BODY, GROUND);
    match &v.snapshot.host.temperature {
        Temperature::Reading { celsius, .. } => {
            let colour = if dim { META } else if *celsius < 70.0 { TEXT } else { temp_colour(*celsius) };
            c.put(tx, y1 + 1, &format!("{celsius:.0}°C"), colour, GROUND);
        }
        Temperature::Unavailable => {
            c.put(tx, y1 + 1, &fit("unavailable, does not affect health", (w - tx - 1) as usize), META, GROUND);
        }
        Temperature::Waiting => {
            c.put(tx, y1 + 1, "--", META, GROUND);
        }
    }
    footer(c, v, overflow);
    Drawn { overflow, scroll }
}

/// Below 60x20: only the status word and one summary line.
fn tiny(c: &mut Canvas, v: &View) -> Drawn {
    let (word, wc, ground) = status_word(v.health.status);
    c.ground(0, c.h(), ground);
    c.put(1.min(c.w() - 1), 0, word, wc, ground);
    c.put(1.min(c.w() - 1), 1, &fit(&headline(v.health), c.w().saturating_sub(2) as usize), TEXT, ground);
    Drawn { overflow: false, scroll: 0 }
}

pub fn draw(buf: &mut Buffer, v: &View, scroll: usize) -> Drawn {
    let area = buf.area;
    let mut c = Canvas { buf, area };
    if c.w() == 0 || c.h() == 0 {
        return Drawn { overflow: false, scroll: 0 };
    }
    c.ground(0, c.h(), GROUND);
    if c.w() >= FULL_MIN.0 && c.h() >= FULL_MIN.1 {
        full(&mut c, v, scroll)
    } else if c.w() >= COMPACT_MIN.0 && c.h() >= COMPACT_MIN.1 {
        compact(&mut c, v, scroll)
    } else {
        tiny(&mut c, v)
    }
}
