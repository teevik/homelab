//! A · Instrument ledger at 160x50, with every health/data state from
//! "Approve TTY health states and interaction details" (teevik/homelab#71).
//!
//! Only CP437 glyphs that the 256-glyph Terminus fonts carry are used, and only palette
//! slots 0-15 (grounds 0-7). No bold/italic/underline/dim/reverse: the Linux VT turns
//! those into colour changes. "Dimmed" means drawn in overlay1 (META).
//!
//! The B/C variants and the 106x33 layout from #70 are in commit 1011672.

use crate::data::*;
use crate::palette::*;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};

pub struct Canvas<'a> {
    pub buf: &'a mut Buffer,
    pub area: Rect,
}

fn st(fg: u8, bg: u8) -> Style {
    Style::new().fg(Color::Indexed(fg)).bg(Color::Indexed(bg))
}

impl Canvas<'_> {
    fn w(&self) -> u16 {
        self.area.width
    }
    fn h(&self) -> u16 {
        self.area.height
    }
    /// Write clipped text; returns the x after the text.
    fn put(&mut self, x: u16, y: u16, text: &str, fg: u8, bg: u8) -> u16 {
        if y >= self.h() || x >= self.w() {
            return x;
        }
        let max = (self.w() - x) as usize;
        let t: String = text.chars().take(max).collect();
        let n = t.chars().count() as u16;
        self.buf.set_string(self.area.x + x, self.area.y + y, &t, st(fg, bg));
        x + n
    }
    fn fill(&mut self, y: u16, x0: u16, x1: u16, ch: char, fg: u8, bg: u8) {
        for x in x0..x1.min(self.w()) {
            self.put(x, y, &ch.to_string(), fg, bg);
        }
    }
    fn ground(&mut self, y0: u16, y1: u16, bg: u8) {
        for y in y0..y1.min(self.h()) {
            self.fill(y, 0, self.w(), ' ', BODY, bg);
        }
    }
    fn right(&mut self, x_end: u16, y: u16, text: &str, fg: u8, bg: u8) {
        let n = text.chars().count() as u16;
        self.put(x_end.saturating_sub(n), y, text, fg, bg);
    }
}

// ---------------------------------------------------------------- formatting

/// Ages: seconds under a minute, then whole minutes. They are recomputed on each
/// redraw (at least every 5s, when a host sample lands), not by a per-second timer.
pub fn age(s: u32) -> String {
    if s < 60 {
        format!("{s}s")
    } else if s < 3600 {
        format!("{}m", s / 60)
    } else {
        format!("{}h {}m", s / 3600, s / 60 % 60)
    }
}

fn mins(m: u32) -> String {
    age(m * 60)
}

// ---------------------------------------------------------------- big status type

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

/// Draw `word` from a 5x7 pixel font; one pixel is `scale` cells wide and `scale`
/// half-cells tall, so pixels stay square in a 16x32 cell.
fn big(c: &mut Canvas, x: u16, y: u16, word: &str, scale: u16, fg: u8, bg: u8) {
    let w = big_width(word, scale) as usize;
    let hh = (7 * scale) as usize;
    let mut on = vec![vec![false; w]; hh + 1];
    let mut px = 0usize;
    for ch in word.chars() {
        let (rows, gw) = glyph(ch);
        for (ry, row) in rows.iter().enumerate() {
            for (rx, b) in row.chars().enumerate() {
                if b == '#' {
                    for sy in 0..scale as usize {
                        for sx in 0..scale as usize {
                            on[ry * scale as usize + sy][(px + rx) * scale as usize + sx] = true;
                        }
                    }
                }
            }
        }
        px += gw as usize + 1;
    }
    for r in 0..(hh + 1) / 2 {
        for col in 0..w {
            let ch = match (on[2 * r][col], on[2 * r + 1][col]) {
                (true, true) => "█",
                (true, false) => "▀",
                (false, true) => "▄",
                _ => " ",
            };
            c.put(x + col as u16, y + r as u16, ch, fg, bg);
        }
    }
}

// ---------------------------------------------------------------- vocabulary

fn status_word(st: Status) -> (&'static str, u8, u8) {
    match st {
        Status::AllClear => ("ALL CLEAR", OK, GROUND),
        Status::Attention => ("ATTENTION", TEXT, ALERT_GROUND),
        Status::Unknown => ("UNKNOWN", WARM, GROUND),
    }
}

fn tier_marker(t: Tier) -> (&'static str, u8) {
    match t {
        Tier::Fault => ("■", FAIL),
        Tier::Alert => ("!", WARM),
        Tier::Deploy => ("▲", DEPLOY_HI),
        Tier::Unknown => ("?", WARM),
    }
}

fn signal_colour(k: Kind) -> u8 {
    match k {
        Kind::Http => FAIL,
        Kind::AppHealth | Kind::AppSync | Kind::Restarts => DEPLOY_HI,
        Kind::Alert | Kind::NoResult => WARM,
        Kind::EndpointOk => OK,
    }
}

/// How a source reads in a section header: text and colour.
fn freshness(src: Src, every: &str) -> (String, u8) {
    match src {
        Src::Waiting => ("waiting for the first result".into(), META),
        Src::Current { age_s } => (format!("every {every} · {} ago", age(age_s)), META),
        Src::Stale { age_s } => (format!("STALE · newest sample {} old", age(age_s)), WARM),
        Src::Unavailable { for_s, .. } => (format!("UNAVAILABLE {} · last results", age(for_s)), WARM),
    }
}

// ---------------------------------------------------------------- status band

fn summary(s: &Snapshot, d: &Derived) -> Vec<(String, u8)> {
    let ne = s.endpoints.len();
    let na = s.apps.len();
    let mut lines = vec![];

    // headline
    let known: Vec<&Attention> = d.attention.iter().filter(|r| r.tier != Tier::Unknown).collect();
    let cluster = known.iter().any(|r| r.service == "cluster");
    let services = known.len() - cluster as usize;
    let on = match (services, cluster) {
        (0, _) => "on the cluster".to_string(),
        (1, false) => "on 1 service".into(),
        (n, false) => format!("on {n} services"),
        (1, true) => "on 1 service and the cluster".into(),
        (n, true) => format!("on {n} services and the cluster"),
    };
    let cluster_down = [s.http, s.argo, s.alerts_src].iter().all(|x| matches!(x, Src::Unavailable { .. }));
    let headline = match d.status {
        Status::Attention => format!("{} {} {on}", d.signals, if d.signals == 1 { "signal" } else { "signals" }),
        Status::AllClear => "every check passes".into(),
        Status::Unknown => {
            if let Some(t) = s.started_s {
                format!("starting, waiting for first readings ({})", age(t))
            } else if cluster_down {
                if let Src::Unavailable { for_s, .. } = s.http {
                    format!("cluster monitoring unavailable for {}", age(for_s))
                } else {
                    unreachable!()
                }
            } else if let Src::Stale { age_s } = s.http {
                format!("http checks stale, newest sample {} old", age(age_s))
            } else if d.gaps_endpoints + d.gaps_apps > 0 {
                "inventory incomplete, health cannot be confirmed".into()
            } else {
                "health cannot be confirmed".into()
            }
        }
    };
    lines.push((headline, TEXT));

    // endpoints
    let failing = s.endpoints.iter().filter(|e| matches!(e.check, Check::Fail { .. })).count();
    let ok = s.endpoints.iter().filter(|e| matches!(e.check, Check::Ok { .. })).count();
    lines.push(match s.http {
        Src::Waiting => ("endpoints: waiting for the first check".into(), META),
        Src::Stale { .. } => ("endpoints: no current results".into(), WARM),
        Src::Unavailable { .. } => ("endpoints: no current results".into(), WARM),
        Src::Current { .. } if failing > 0 => (format!("{failing} of {ne} endpoints failing"), TEXT),
        Src::Current { .. } if d.gaps_endpoints > 0 => {
            (format!("{ok} of {ne} endpoints respond, {} without a result", d.gaps_endpoints), TEXT)
        }
        Src::Current { .. } => (format!("{ok} of {ne} endpoints respond"), TEXT),
    });

    // apps
    let known: Vec<(Sync, Health)> = s
        .apps
        .iter()
        .filter_map(|a| match a.state {
            AppState::Known { sync, health, .. } => Some((sync, health)),
            _ => None,
        })
        .collect();
    let unhealthy = known.iter().filter(|k| k.1 != Health::Healthy).count();
    let oos = known.iter().filter(|k| k.0 != Sync::Synced).count();
    lines.push(match s.argo {
        Src::Waiting => ("apps: waiting for argo cd".into(), META),
        Src::Stale { .. } | Src::Unavailable { .. } => ("apps: no current status".into(), WARM),
        Src::Current { .. } if unhealthy + oos > 0 => (format!("{unhealthy} of {na} apps unhealthy, {oos} out of sync"), TEXT),
        Src::Current { .. } if d.gaps_apps > 0 => {
            (format!("{} of {na} apps healthy, {} not reported", known.len(), d.gaps_apps), TEXT)
        }
        Src::Current { .. } => (format!("{na} of {na} apps synced and healthy"), TEXT),
    });

    // alerts: "no active alerts" only from a current source; never a zero from nothing
    lines.push(match s.alerts_src {
        Src::Waiting => ("alerts: waiting for alertmanager".into(), META),
        Src::Stale { .. } | Src::Unavailable { .. } => ("alerts: unknown, alertmanager unavailable".into(), WARM),
        Src::Current { .. } if s.alerts.is_empty() => ("no active alerts".into(), TEXT),
        Src::Current { .. } if s.alerts.len() == 1 => ("1 active alert".into(), TEXT),
        Src::Current { .. } => (format!("{} active alerts", s.alerts.len()), TEXT),
    });

    // coverage
    let bad: Vec<String> = s
        .sources()
        .iter()
        .filter_map(|(n, x)| match x {
            Src::Stale { .. } => Some(format!("{n} stale")),
            Src::Unavailable { .. } => Some(format!("{n} unavailable")),
            _ => None,
        })
        .collect();
    let coverage = if s.started_s.is_some() {
        ("host readings current".into(), META)
    } else if cluster_down {
        ("host readings still current".into(), WARM)
    } else if !bad.is_empty() {
        (format!("partial coverage: {}", bad.join(", ")), WARM)
    } else if d.gaps_endpoints + d.gaps_apps > 0 {
        ("partial coverage: catalog entries without data".into(), WARM)
    } else {
        let oldest = s.sources().iter().filter_map(|(_, x)| if let Src::Current { age_s } = x { Some(*age_s) } else { None }).max().unwrap_or(0);
        (format!("all sources current, oldest {}", age(oldest)), META)
    };
    lines.push(coverage);
    lines
}

/// The fixed 4-row attention slot. Never scrolls; overflow collapses into the last row.
fn attention_slot(c: &mut Canvas, s: &Snapshot, d: &Derived, y0: u16) {
    let w = c.w();
    let rows = &d.attention;
    if rows.is_empty() {
        let (text, col) = match d.status {
            Status::AllClear => ("Nothing needs attention.".to_string(), META),
            Status::Unknown if s.started_s.is_some() => ("Waiting for first readings. Nothing is known to need attention yet.".into(), META),
            _ => ("No known problems, but health cannot be confirmed until every source is current.".into(), WARM),
        };
        c.put(3, y0, &text, col, GROUND);
        for (i, r) in s.recovered.iter().take(3).enumerate() {
            let y = y0 + 1 + i as u16;
            c.put(3, y, "·", OK, GROUND);
            c.put(5, y, r.service, BODY, GROUND);
            let x = c.put(25, y, "recovered", OK, GROUND);
            c.put(x, y, &format!("  ·  was {} for {}  ·  ok since {}", r.what, r.lasted, r.ok_since), META, GROUND);
        }
        return;
    }
    let slots = 4usize;
    let shown = if rows.len() > slots { slots - 1 } else { rows.len() };
    for (i, a) in rows.iter().take(shown).enumerate() {
        let y = y0 + i as u16;
        let (m, mc) = tier_marker(a.tier);
        c.put(3, y, m, mc, GROUND);
        c.put(5, y, &a.service, TEXT, GROUND);
        // signals, truncated with "+n more" rather than cut mid-word
        let limit = w - 16;
        let mut x = 25;
        for (j, g) in a.signals.iter().enumerate() {
            let sep = if j > 0 { 5 } else { 0 };
            let rest = a.signals.len() - j;
            let need = sep + g.text.chars().count() as u16 + if rest > 1 { 12 } else { 0 };
            if x + need > limit {
                c.put(x + 2, y, &format!("+{rest} more"), META, GROUND);
                break;
            }
            if j > 0 {
                x = c.put(x, y, "  ·  ", RULE, GROUND);
            }
            let col = if g.text.contains("Degraded") { FAIL } else { signal_colour(g.kind) };
            x = c.put(x, y, &g.text, col, GROUND);
        }
        match a.since_m {
            Some(m) => c.right(w - 2, y, &format!("since {}", mins(m)), META, GROUND),
            None => c.right(w - 2, y, "expected by catalog", META, GROUND),
        }
    }
    if rows.len() > slots {
        let y = y0 + slots as u16 - 1;
        let more = &rows[shown..];
        let x = c.put(5, y, &format!("+{} more", more.len()), WARM, GROUND);
        let names: Vec<&str> = more.iter().map(|r| r.service.as_str()).collect();
        let x = c.put(25.max(x + 2), y, &names.join(", "), BODY, GROUND);
        c.put(x + 2, y, "(highlighted below)", META, GROUND);
    }
}

// ---------------------------------------------------------------- instruments

fn heat(v: u8, warm: u8, hot: u8) -> u8 {
    if v >= hot {
        HOT
    } else if v >= warm {
        WARM
    } else {
        COOL
    }
}

fn temp_colour(t: u8) -> u8 {
    heat(t, 70, 80)
}

fn meter(c: &mut Canvas, x: u16, y: u16, cells: u16, pct: Option<u8>) -> u16 {
    let Some(pct) = pct else {
        c.fill(y, x, x + cells, '░', RULE, GROUND);
        return x + cells;
    };
    let fill = ((pct as u32 * cells as u32 + 50) / 100) as u16;
    c.fill(y, x, x + fill, '█', heat(pct, 80, 90), GROUND);
    c.fill(y, x + fill, x + cells, '░', RULE, GROUND);
    x + cells
}

/// Temperature history, one column per minute, half-block resolution, 40-95 °C.
fn chart(c: &mut Canvas, x: u16, y: u16, cols: u16, rows: u16, hist: &[Option<u8>]) {
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
                let lvl = (((*t as f32 - lo) / (hi - lo)).clamp(0.0, 1.0) * levels).round() as u16;
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

fn host(c: &mut Canvas, s: &Snapshot, hx: u16) {
    for y in 17..c.h() - 2 {
        c.put(hx - 3, y, "│", RULE, GROUND);
    }
    c.put(hx, 17, "HOST", LABEL, GROUND);
    let (f, fc) = freshness(s.host_src, "5s");
    c.put(hx + 5, 17, &f, fc, GROUND);
    let h = &s.host;
    let mw = 26;
    let cpu_detail = if h.cpu.is_some() { format!("{} threads", h.threads) } else { "measuring".into() };
    for (i, (label, pct, detail)) in [
        ("cpu", h.cpu, cpu_detail),
        ("mem", Some(h.mem), h.mem_detail.to_string()),
        ("root", Some(h.root), h.root_detail.to_string()),
    ]
    .iter()
    .enumerate()
    {
        let y = 19 + i as u16 * 2;
        c.put(hx, y, label, BODY, GROUND);
        let x = meter(c, hx + 5, y, mw, *pct);
        match pct {
            Some(p) => c.right(x + 5, y, &format!("{p}%"), TEXT, GROUND),
            None => c.right(x + 5, y, "--", META, GROUND),
        }
        c.put(x + 7, y, detail, META, GROUND);
    }
    let ty = 26;
    c.put(hx, ty, "cpu temp", BODY, GROUND);
    let cols = (c.w() - hx - 6).min(60);
    match h.temp {
        Temp::Reading(t) => {
            let x = c.put(hx + 10, ty, &format!("{t}°C"), if t < 70 { TEXT } else { temp_colour(t) }, GROUND);
            c.put(x + 2, ty, "Tctl, last hour", META, GROUND);
            for (lbl, r) in [("90°", 0u16), ("70°", 3), ("50°", 6)] {
                c.put(hx, ty + 2 + r, lbl, META, GROUND);
            }
            chart(c, hx + 5, ty + 2, cols, 8, &h.temp_history);
        }
        Temp::Unsupported => {
            c.put(hx + 10, ty, "unavailable", META, GROUND);
            c.put(hx + 10, ty + 2, "No CPU package sensor was found.", META, GROUND);
            c.put(hx + 10, ty + 3, "This does not affect service health.", META, GROUND);
        }
    }

    let sy = ty + 13;
    c.put(hx, sy, "SOURCES", LABEL, GROUND);
    c.put(hx + 8, sy, "age of the newest sample", META, GROUND);
    let mut y = sy + 1;
    for (name, src) in s.sources() {
        let (dot, dc, a, word, wc) = match src {
            Src::Waiting => ("·", META, "--".to_string(), "waiting", META),
            Src::Current { age_s } => ("·", OK, age(age_s), "current", OK),
            Src::Stale { age_s } => ("?", WARM, age(age_s), "stale", WARM),
            Src::Unavailable { for_s, .. } => ("?", WARM, age(for_s), "unavailable", WARM),
        };
        c.put(hx, y, dot, dc, GROUND);
        c.put(hx + 2, y, name, BODY, GROUND);
        c.right(hx + 22, y, &a, META, GROUND);
        c.put(hx + 24, y, word, wc, GROUND);
        y += 1;
    }
    // one reason line per distinct failure cause
    let mut reasons: Vec<&str> = vec![];
    for (_, src) in s.sources() {
        if let Src::Unavailable { reason, .. } = src {
            if !reasons.contains(&reason) {
                reasons.push(reason);
            }
        }
    }
    for r in reasons {
        c.put(hx + 2, y, r, META, GROUND);
        y += 1;
    }
}

// ---------------------------------------------------------------- header, footer

fn header(c: &mut Canvas, s: &Snapshot, proto: &str) {
    c.ground(0, 1, BAR);
    let x = c.put(1, 0, "HOMELAB", BRAND, BAR);
    c.put(x + 2, 0, "host health", META, BAR);
    let w = c.w();
    c.put(w / 2 - proto.chars().count() as u16 / 2, 0, proto, WARM, BAR);
    c.right(w, 0, &format!("{}  {} ", s.date, s.clock), TEXT, BAR);
}

fn footer(c: &mut Canvas, s: &Snapshot, overflow: bool) {
    let y = c.h() - 1;
    c.ground(y, y + 1, BAR);
    let mut x = c.put(1, y, "Ctrl+C", TEXT, BAR);
    x = c.put(x + 1, y, "close, monitoring keeps running", META, BAR);
    if overflow {
        x = c.put(x + 4, y, "↑↓", TEXT, BAR);
        c.put(x + 1, y, "scroll services", META, BAR);
    }
    let w = c.w();
    match s.night {
        Night::Day { dark_in } => {
            c.right(w, y, &format!("screen dark 23:00-08:00, in {dark_in} "), COOL, BAR);
        }
        Night::QuietWake { dark_at, left } => {
            let t = format!("quiet hours until 08:00 · woken, dark again at {dark_at} (in {left}) ");
            c.right(w, y, &t, COOL, BAR);
        }
        Night::BedtimeWake { dark_at, left } => {
            let t = format!("bedtime until 08:00 · woken, dark again at {dark_at} (in {left}) ");
            c.right(w, y, &t, COOL, BAR);
        }
    }
}

// ---------------------------------------------------------------- the ledger

pub fn draw(c: &mut Canvas, s: &Snapshot, scroll: u16, proto: &str) {
    c.ground(0, c.h(), GROUND);
    let d = derive(s);
    if c.w() < 150 || c.h() < 45 {
        return compact(c, s, &d);
    }
    header(c, s, proto);

    let (word, wc, ground) = status_word(d.status);
    c.ground(2, 11, ground);
    big(c, 3, 3, word, 2, wc, ground);
    // summary column is anchored to the widest word so it never moves between states
    let sx = 3 + big_width("ATTENTION", 2) + 6;
    for (i, (t, col)) in summary(s, &d).iter().enumerate() {
        let col = if ground == ALERT_GROUND && *col == WARM { TEXT } else { *col };
        c.put(sx, 3 + i as u16 + (i >= 3) as u16, t, col, ground);
    }
    attention_slot(c, s, &d, 12);
    c.fill(16, 1, c.w() - 1, '─', RULE, GROUND);

    let (xm, xn, xc, xl, xd, xa, xs, xh) = (3, 5, 24, 40, 49, 51, 71, 83);
    let hx = 101;
    c.put(xm, 17, "ENDPOINTS", LABEL, GROUND);
    let (f, fc) = freshness(s.http, "30s");
    c.put(xm + 10, 17, &f, fc, GROUND);
    for (x, t) in [(xn, "service"), (xc, "check"), (xl, "latency"), (xa, "app"), (xs, "sync"), (xh, "health")] {
        c.put(x, 18, t, META, GROUND);
    }
    c.put(xa, 17, "DEPLOYMENT", LABEL, GROUND);
    let (f, fc) = freshness(s.argo, "30s");
    c.put(xa + 11, 17, &f, fc, GROUND);

    enum Row<'a> {
        Gap,
        Label(&'a str),
        Ep(&'a Endpoint),
        App(&'a App),
    }
    let mut rows = vec![];
    for (i, e) in s.endpoints.iter().enumerate() {
        if i > 0 && i % 4 == 0 {
            rows.push(Row::Gap);
        }
        rows.push(Row::Ep(e));
    }
    rows.push(Row::Gap);
    rows.push(Row::Label("apps without an endpoint"));
    for a in s.apps_without_endpoint() {
        rows.push(Row::App(a));
    }
    let top = 19;
    let bottom = c.h() - 3;
    let avail = (bottom - top) as usize;
    let scroll = (scroll as usize).min(rows.len().saturating_sub(avail));
    let http_live = s.http.current();
    let argo_live = s.argo.current();
    for (i, r) in rows.iter().skip(scroll).take(avail).enumerate() {
        let y = top + i as u16;
        let app_cols = |c: &mut Canvas, a: &App| match a.state {
            AppState::Waiting => {
                c.put(xa, y, a.id, BODY, GROUND);
                c.put(xs, y, "waiting", META, GROUND);
            }
            AppState::Missing => {
                c.put(xa, y, a.id, TEXT, GROUND);
                c.put(xs, y, "?", WARM, GROUND);
                c.put(xh, y, "not reported", WARM, GROUND);
            }
            AppState::Known { sync, health, restarts, .. } => {
                let problem = sync != Sync::Synced || health != Health::Healthy || restarts.is_some();
                let (st_, sc) = match sync {
                    Sync::Synced => ("synced", DEPLOY),
                    Sync::OutOfSync => ("OutOfSync", DEPLOY_HI),
                };
                let (ht, hc) = match health {
                    Health::Healthy => ("healthy", DEPLOY),
                    Health::Progressing => ("Progressing", DEPLOY_HI),
                    Health::Degraded => ("Degraded", FAIL),
                };
                let dim = |col: u8| if argo_live || col == FAIL { col } else { META };
                c.put(xa, y, a.id, dim(if problem { TEXT } else { BODY }), GROUND);
                c.put(xs, y, st_, dim(sc), GROUND);
                c.put(xh, y, ht, dim(hc), GROUND);
            }
        };
        match r {
            Row::Gap => {}
            Row::Label(t) => {
                c.put(xa, y, t, META, GROUND);
            }
            Row::Ep(e) => {
                let failing = matches!(e.check, Check::Fail { .. });
                let bg = if failing { ALERT_GROUND } else { GROUND };
                if failing {
                    c.fill(y, xm - 1, xd, ' ', BODY, bg);
                }
                match e.check {
                    Check::Waiting => {
                        c.put(xn, y, e.name, BODY, bg);
                        c.put(xc, y, "waiting", META, bg);
                    }
                    Check::Missing => {
                        c.put(xm, y, "?", WARM, bg);
                        c.put(xn, y, e.name, TEXT, bg);
                        c.put(xc, y, "no result", WARM, bg);
                        c.right(xl + 6, y, "--", META, bg);
                    }
                    Check::Ok { ms } => {
                        // last-known ok from a stale/unavailable source is dimmed, never green
                        let (mc, oc, nc) = if http_live { (OK, OK, BODY) } else { (META, META, META) };
                        c.put(xm, y, "·", mc, bg);
                        c.put(xn, y, e.name, nc, bg);
                        c.put(xc, y, "ok", oc, bg);
                        c.right(xl + 6, y, &format!("{ms} ms"), META, bg);
                    }
                    Check::Fail { what, for_m } => {
                        // known failures stay at full strength
                        c.put(xm, y, "■", FAIL, bg);
                        c.put(xn, y, e.name, TEXT, bg);
                        c.put(xc, y, what, FAIL, bg);
                        c.right(xl + 6, y, &format!("for {}", mins(for_m)), TEXT, bg);
                    }
                }
                c.put(xd, y, "│", RULE, GROUND);
                match e.app.and_then(|id| s.app(id)) {
                    Some(a) => app_cols(c, a),
                    None => {
                        c.put(xa, y, "no app (host)", META, GROUND);
                    }
                }
            }
            Row::App(a) => {
                c.put(xd, y, "│", RULE, GROUND);
                app_cols(c, a);
            }
        }
    }
    let overflow = rows.len() > avail;
    if scroll + avail < rows.len() {
        c.put(xn, bottom, &format!("↓ {} more rows", rows.len() - scroll - avail), WARM, GROUND);
    }
    if scroll > 0 {
        c.right(xd - 1, 18, &format!("↑ {scroll} above"), WARM, GROUND);
    }
    host(c, s, hx);
    footer(c, s, overflow);
}

/// Below 150x45 (a different font or a resized terminal). Not part of this review:
/// the compact fallback was settled in #70 and is not re-prototyped here.
fn compact(c: &mut Canvas, s: &Snapshot, d: &Derived) {
    let (word, wc, ground) = status_word(d.status);
    c.ground(0, 3, ground);
    c.put(1, 0, word, wc, ground);
    c.put(1, 1, &summary(s, d)[0].0, TEXT, ground);
    c.put(1, 3, &format!("Console is {}x{}; this prototype draws the full layout at 150x45 or more.", c.w(), c.h()), META, GROUND);
    c.put(1, 4, "Ctrl+C close", META, GROUND);
}
