//! Three structurally different layouts of the chosen "A · Terminal instruments"
//! direction. Only CP437 glyphs that the 256-glyph Terminus fonts carry are used, and
//! only palette slots 0-15 (grounds 0-7). No bold/italic/underline/dim/reverse: the
//! Linux VT turns those into colour changes.

use crate::data::*;
use crate::palette::*;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};

#[derive(Clone, Copy, PartialEq)]
pub enum Variant {
    A,
    B,
    C,
}

impl Variant {
    pub const ALL: [Variant; 3] = [Variant::A, Variant::B, Variant::C];
    pub fn name(self) -> &'static str {
        match self {
            Variant::A => "A · Instrument ledger",
            Variant::B => "B · Attention first",
            Variant::C => "C · Large type",
        }
    }
    pub fn key(self) -> &'static str {
        match self {
            Variant::A => "a",
            Variant::B => "b",
            Variant::C => "c",
        }
    }
}

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
            self.fill(y, 0, self.w(), ' ', PARCHMENT, bg);
        }
    }
    fn right(&mut self, x_end: u16, y: u16, text: &str, fg: u8, bg: u8) {
        let n = text.chars().count() as u16;
        self.put(x_end.saturating_sub(n), y, text, fg, bg);
    }
}

// ---------------------------------------------------------------- big status type

fn glyph(c: char) -> (&'static [&'static str; 7], u16) {
    const A: [&str; 7] = [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"];
    const C: [&str; 7] = [" ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####"];
    const E: [&str; 7] = ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"];
    const I: [&str; 7] = ["###", " # ", " # ", " # ", " # ", " # ", "###"];
    const L: [&str; 7] = ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"];
    const N: [&str; 7] = ["#   #", "##  #", "##  #", "# # #", "#  ##", "#  ##", "#   #"];
    const O: [&str; 7] = [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "];
    const R: [&str; 7] = ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"];
    const T: [&str; 7] = ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "];
    const SP: [&str; 7] = ["  ", "  ", "  ", "  ", "  ", "  ", "  "];
    match c {
        'A' => (&A, 5),
        'C' => (&C, 5),
        'E' => (&E, 5),
        'I' => (&I, 3),
        'L' => (&L, 5),
        'N' => (&N, 5),
        'O' => (&O, 5),
        'R' => (&R, 5),
        'T' => (&T, 5),
        _ => (&SP, 2),
    }
}

/// Width in cells of `word` at `scale`.
fn big_width(word: &str, scale: u16) -> u16 {
    let px: u16 = word.chars().map(|c| glyph(c).1 + 1).sum::<u16>() - 1;
    px * scale
}

/// Draw `word` from a 5x7 pixel font. One pixel is `scale` cells wide and `scale`
/// half-cells tall; a 16x32 cell makes a half-cell square, so pixels stay square.
/// Returns the height in rows.
fn big(c: &mut Canvas, x: u16, y: u16, word: &str, scale: u16, fg: u8, bg: u8) -> u16 {
    let w = big_width(word, scale) as usize;
    let hh = (7 * scale) as usize; // half-rows
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
    let rows = (hh + 1) / 2;
    for r in 0..rows {
        for col in 0..w {
            let (t, b) = (on[2 * r][col], on[2 * r + 1][col]);
            let ch = match (t, b) {
                (true, true) => "█",
                (true, false) => "▀",
                (false, true) => "▄",
                _ => " ",
            };
            c.put(x + col as u16, y + r as u16, ch, fg, bg);
        }
    }
    rows as u16
}

// ---------------------------------------------------------------- shared pieces

fn header(c: &mut Canvas, s: &Snapshot, short: bool) {
    c.ground(0, 1, RAISED);
    let x = c.put(1, 0, "HOMELAB", BRASS, RAISED);
    if !short {
        c.put(x + 2, 0, "host health", SLATE, RAISED);
    }
    let tag = if short { "ILLUSTRATIVE" } else { "PROTOTYPE - ILLUSTRATIVE DATA, NOT LIVE" };
    let w = c.w();
    c.put(w / 2 - tag.len() as u16 / 2, 0, tag, AMBER, RAISED);
    let clock = format!("{}  {} ", s.date, s.clock);
    let clock = if short { format!("{} ", s.clock) } else { clock };
    c.right(w, 0, &clock, IVORY, RAISED);
}

fn footer(c: &mut Canvas, short: bool) {
    let y = c.h() - 1;
    c.ground(y, y + 1, RAISED);
    let mut x = c.put(1, y, "Ctrl+C", IVORY, RAISED);
    x = c.put(x + 1, y, "shell", SLATE, RAISED);
    if !short {
        x = c.put(x + 3, y, "dashboard", IVORY, RAISED);
        c.put(x + 1, y, "relaunch", SLATE, RAISED);
    }
    let night = if short { "dark 23-08 " } else { "screen dark 23:00-08:00, in 1h 18m " };
    let w = c.w();
    c.right(w, y, night, MOON, RAISED);
}

fn meter(c: &mut Canvas, x: u16, y: u16, cells: u16, pct: u8) -> u16 {
    let fill = ((pct as u32 * cells as u32 + 50) / 100) as u16;
    let col = heat(pct, 80, 90);
    c.fill(y, x, x + fill, '█', col, SOOT);
    c.fill(y, x + fill, x + cells, '░', ASH, SOOT);
    x + cells
}

fn heat(v: u8, warm: u8, hot: u8) -> u8 {
    if v >= hot {
        EMBER
    } else if v >= warm {
        AMBER
    } else {
        BRASS
    }
}

fn temp_colour(t: u8) -> u8 {
    heat(t, 70, 80)
}

/// Temperature history, one column per minute, half-block resolution, 40-95 °C.
fn chart(c: &mut Canvas, x: u16, y: u16, cols: u16, rows: u16, hist: &[Option<u8>]) {
    let (lo, hi) = (40.0, 95.0);
    let levels = (rows * 2) as f32;
    let start = hist.len().saturating_sub(cols as usize);
    let shown = &hist[start..];
    let x0 = x + cols - shown.len() as u16;
    for (i, v) in shown.iter().enumerate() {
        let cx = x0 + i as u16;
        match v {
            None => {
                c.put(cx, y + rows - 1, "·", SLATE, SOOT);
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
                    c.put(cx, y + r, ch, temp_colour(*t), SOOT);
                }
            }
        }
    }
    c.fill(y + rows, x, x + cols, '─', ASH, SOOT);
    c.put(x, y + rows + 1, &format!("-{}m", shown.len()), SLATE, SOOT);
    c.right(x + cols, y + rows + 1, "now", SLATE, SOOT);
}

fn marker(check: &Check) -> (&'static str, u8) {
    match check {
        Check::Ok { .. } => ("·", LICHEN),
        Check::Fail { .. } => ("■", EMBER),
    }
}

fn sync_text(a: &App) -> (&'static str, u8) {
    match a.sync {
        Sync::Synced => ("synced", HEATHER),
        Sync::OutOfSync => ("OutOfSync", HEATHER_HI),
    }
}

fn health_text(a: &App) -> (&'static str, u8) {
    match a.health {
        Health::Healthy => ("healthy", HEATHER),
        Health::Progressing => ("Progressing", HEATHER_HI),
        Health::Degraded => ("Degraded", EMBER),
    }
}

fn app_problem(a: &App) -> bool {
    a.sync != Sync::Synced || a.health != Health::Healthy || a.restarts.is_some()
}

fn status(s: &Snapshot) -> (&'static str, u8, u8) {
    if s.attention.is_empty() {
        ("ALL CLEAR", LICHEN_HI, SOOT)
    } else {
        ("ATTENTION", IVORY, EMBER_GROUND)
    }
}

fn summary(s: &Snapshot) -> Vec<(String, u8)> {
    let (ne, na) = (s.endpoints.len(), s.apps.len());
    if s.attention.is_empty() {
        vec![
            (format!("{} of {ne} endpoints respond", s.endpoints_ok()), IVORY),
            (format!("{} of {na} apps synced and healthy", s.apps_healthy()), IVORY),
            ("no active alerts".into(), IVORY),
            (String::new(), SLATE),
            ("all sources current, oldest 21s".into(), SLATE),
        ]
    } else {
        let services = s.attention.len();
        vec![
            (format!("{} signals on {services} services", s.signals), IVORY),
            (format!("{} of {ne} endpoints failing", ne - s.endpoints_ok()), IVORY),
            (
                format!(
                    "{} of {na} apps unhealthy, {} out of sync",
                    na - s.apps_healthy(),
                    na - s.apps_synced()
                ),
                IVORY,
            ),
            (format!("{} active alerts", s.alerts.len()), IVORY),
            ("all sources current, oldest 21s".into(), PARCHMENT),
        ]
    }
}

fn attention_line(c: &mut Canvas, x: u16, y: u16, a: &Attention, name_w: u16, bg: u8) -> u16 {
    let (m, col) = match a.severity {
        Severity::Fault => ("■", EMBER),
        Severity::Deploy => ("▲", HEATHER_HI),
    };
    c.put(x, y, m, col, bg);
    c.put(x + 2, y, a.service, IVORY, bg);
    let mut cx = x + 2 + name_w;
    for (i, p) in a.parts.iter().enumerate() {
        if i > 0 {
            cx = c.put(cx, y, "  ·  ", ASH, bg);
        }
        let pc = if p.starts_with("app") || p.contains("restarts") {
            HEATHER_HI
        } else if p.starts_with("alert") {
            AMBER
        } else if *p == "endpoint ok" {
            LICHEN
        } else {
            EMBER
        };
        cx = c.put(cx, y, p, pc, bg);
    }
    cx
}

// ---------------------------------------------------------------- A · Instrument ledger

pub fn draw(v: Variant, c: &mut Canvas, s: &Snapshot, scroll: u16) {
    c.ground(0, c.h(), SOOT);
    let fallback = match v {
        Variant::A => c.w() < 150 || c.h() < 45,
        Variant::B => c.w() < 100 || c.h() < 30,
        Variant::C => false,
    };
    if c.w() < 60 || c.h() < 20 {
        tiny(c, s);
    } else if fallback || v == Variant::C {
        large(c, s, scroll, fallback);
    } else if v == Variant::A {
        ledger(c, s, scroll);
    } else {
        attention_first(c, s, scroll);
    }
}

fn ledger(c: &mut Canvas, s: &Snapshot, scroll: u16) {
    header(c, s, false);
    let (word, wc, ground) = status(s);
    c.ground(2, 11, ground);
    big(c, 3, 3, word, 2, wc, ground);
    let sx = 3 + big_width(word, 2) + 6;
    for (i, (t, col)) in summary(s).iter().enumerate() {
        c.put(sx, 3 + i as u16 + (i >= 3) as u16, t, *col, ground);
    }

    // attention: fixed 4-row slot so the ledger never moves
    if s.attention.is_empty() {
        c.put(3, 12, "Nothing needs attention.", SLATE, SOOT);
    }
    for (i, a) in s.attention.iter().take(4).enumerate() {
        attention_line(c, 3, 12 + i as u16, a, 18, SOOT);
        c.right(c.w() - 2, 12 + i as u16, &format!("since {}", a.since), SLATE, SOOT);
    }
    c.fill(16, 1, c.w() - 1, '─', ASH, SOOT);

    // ledger: endpoints | deployment ; host on the right
    let (xm, xn, xc, xl, xd, xa, xs, xh) = (3, 5, 24, 40, 49, 51, 71, 83);
    let hx = 101;
    c.put(xm, 17, "ENDPOINTS", BRASS, SOOT);
    c.put(xm + 10, 17, "internal HTTP checks, every 30s", SLATE, SOOT);
    c.put(xa, 17, "DEPLOYMENT", BRASS, SOOT);
    c.put(xa + 11, 17, "argo cd", SLATE, SOOT);
    for (x, t) in [(xn, "service"), (xc, "check"), (xl, "latency"), (xa, "app"), (xs, "sync"), (xh, "health")] {
        c.put(x, 18, t, SLATE, SOOT);
    }

    // build rows: 16 endpoints in catalog order (gap every 4), then apps without endpoint
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
    for (i, r) in rows.iter().skip(scroll).take(avail).enumerate() {
        let y = top + i as u16;
        let app_cols = |c: &mut Canvas, a: &App, bg: u8| {
            let (st_, sc) = sync_text(a);
            let (ht, hc) = health_text(a);
            let idc = if app_problem(a) { IVORY } else { PARCHMENT };
            c.put(xa, y, a.id, idc, bg);
            c.put(xs, y, st_, sc, bg);
            c.put(xh, y, ht, hc, bg);
        };
        match r {
            Row::Gap => {}
            Row::Label(t) => {
                c.put(xa, y, t, SLATE, SOOT);
            }
            Row::Ep(e) => {
                let failing = matches!(e.check, Check::Fail { .. });
                let bg = if failing { EMBER_GROUND } else { SOOT };
                if failing {
                    c.fill(y, xm - 1, xd, ' ', PARCHMENT, bg);
                }
                let (m, mc) = marker(&e.check);
                c.put(xm, y, m, mc, bg);
                c.put(xn, y, e.name, if failing { IVORY } else { PARCHMENT }, bg);
                match &e.check {
                    Check::Ok { ms } => {
                        c.put(xc, y, "ok", LICHEN, bg);
                        c.right(xl + 6, y, &format!("{ms} ms"), SLATE, bg);
                    }
                    Check::Fail { what, for_ } => {
                        c.put(xc, y, what, EMBER, bg);
                        c.right(xl + 6, y, &format!("for {for_}"), IVORY, bg);
                    }
                }
                c.put(xd, y, "│", ASH, SOOT);
                match e.app.and_then(|id| s.app(id)) {
                    Some(a) => app_cols(c, a, SOOT),
                    None => {
                        c.put(xa, y, "no app (host)", SLATE, SOOT);
                    }
                }
            }
            Row::App(a) => {
                c.put(xd, y, "│", ASH, SOOT);
                app_cols(c, a, SOOT);
            }
        }
    }
    if scroll + avail < rows.len() {
        c.put(xn, bottom, &format!("↓ {} more rows", rows.len() - scroll - avail), AMBER, SOOT);
    }
    if scroll > 0 {
        c.right(xd - 1, 18, &format!("↑ {scroll} above"), AMBER, SOOT);
    }

    // host instruments
    c.fill(17, hx - 3, hx - 2, ' ', ASH, SOOT);
    for y in 17..c.h() - 2 {
        c.put(hx - 3, y, "│", ASH, SOOT);
    }
    c.put(hx, 17, "HOST", BRASS, SOOT);
    c.put(hx + 5, 17, "every 5s", SLATE, SOOT);
    let h = &s.host;
    let mw = 26;
    for (i, (label, pct, detail)) in [
        ("cpu", h.cpu, format!("{} threads", h.threads)),
        ("mem", h.mem, h.mem_detail.to_string()),
        ("root", h.root, h.root_detail.to_string()),
    ]
    .iter()
    .enumerate()
    {
        let y = 19 + i as u16 * 2;
        c.put(hx, y, label, PARCHMENT, SOOT);
        let x = meter(c, hx + 5, y, mw, *pct);
        c.right(x + 5, y, &format!("{pct}%"), IVORY, SOOT);
        c.put(x + 7, y, detail, SLATE, SOOT);
    }
    let ty = 26;
    c.put(hx, ty, "cpu temp", PARCHMENT, SOOT);
    match h.temp {
        Some(t) => {
            let x = c.put(hx + 10, ty, &format!("{t}°C"), if t < 70 { IVORY } else { temp_colour(t) }, SOOT);
            c.put(x + 2, ty, "Tctl, last hour", SLATE, SOOT);
        }
        None => {
            c.put(hx + 10, ty, "unavailable", SLATE, SOOT);
        }
    }
    let cols = (c.w() - hx - 6).min(60);
    for (lbl, r) in [("90°", 0u16), ("70°", 3), ("50°", 6)] {
        c.put(hx, ty + 2 + r, lbl, SLATE, SOOT);
    }
    chart(c, hx + 5, ty + 2, cols, 8, &h.temp_history);

    let sy = ty + 13;
    c.put(hx, sy, "SOURCES", BRASS, SOOT);
    for (i, src) in s.sources.iter().enumerate() {
        let y = sy + 1 + i as u16;
        c.put(hx, y, "·", LICHEN, SOOT);
        c.put(hx + 2, y, src.name, PARCHMENT, SOOT);
        c.right(hx + 22, y, src.age, SLATE, SOOT);
        c.put(hx + 24, y, "current", LICHEN, SOOT);
    }
    footer(c, false);
}

// ---------------------------------------------------------------- B · Attention first

fn attention_first(c: &mut Canvas, s: &Snapshot, scroll: u16) {
    header(c, s, false);
    let (word, wc, ground) = status(s);
    c.ground(1, 7, ground);
    big(c, 2, 2, word, 1, wc, ground);
    let sx = 2 + big_width(word, 1) + 4;
    for (i, (t, col)) in summary(s).iter().take(4).enumerate() {
        c.put(sx, 2 + i as u16, t, *col, ground);
    }
    let w = c.w();
    let mut y = 8;
    if s.attention.is_empty() {
        c.put(2, y, "Nothing needs attention.", SLATE, SOOT);
        y += 2;
    } else {
        c.put(2, y, "NEEDS ATTENTION", BRASS, SOOT);
        c.put(18, y, "worst first", SLATE, SOOT);
        y += 1;
        for a in &s.attention {
            attention_line(c, 2, y, a, 17, SOOT);
            c.right(w - 2, y, &format!("since {}", a.since), SLATE, SOOT);
            y += 1;
        }
        y += 1;
    }

    // healthy endpoints collapse to a name grid
    let ok: Vec<&Endpoint> = s.endpoints.iter().filter(|e| matches!(e.check, Check::Ok { .. })).collect();
    c.put(2, y, "ENDPOINTS", BRASS, SOOT);
    c.put(12, y, &format!("{} of {} respond", ok.len(), s.endpoints.len()), SLATE, SOOT);
    y += 1;
    let colw = (w - 4) / 4;
    let rows_needed = (ok.len() as u16 + 3) / 4;
    for (i, e) in ok.iter().enumerate() {
        let (col, row) = (i as u16 / rows_needed, i as u16 % rows_needed);
        let x = 2 + col * colw;
        c.put(x, y + row, "·", LICHEN, SOOT);
        c.put(x + 2, y + row, e.name, PARCHMENT, SOOT);
        if let Check::Ok { ms } = e.check {
            c.right(x + colw - 1, y + row, &format!("{ms}ms"), SLATE, SOOT);
        }
    }
    y += rows_needed + 1;
    let quiet: Vec<&str> = s.apps.iter().filter(|a| !app_problem(a)).map(|a| a.id).collect();
    c.put(2, y, "APPS", BRASS, SOOT);
    c.put(7, y, &format!("{} of {} synced and healthy", quiet.len(), s.apps.len()), SLATE, SOOT);
    y += 1;
    let no_ep: Vec<&str> = s.apps_without_endpoint().iter().map(|a| a.id).collect();
    let x = c.put(2, y, "no endpoint: ", SLATE, SOOT);
    c.put(x, y, &no_ep.join(", "), HEATHER, SOOT);
    let _ = scroll;

    // instrument band along the bottom
    let by = c.h() - 9;
    c.fill(by - 1, 1, w - 1, '─', ASH, SOOT);
    let h = &s.host;
    for (i, (label, pct)) in [("cpu", h.cpu), ("mem", h.mem), ("root", h.root)].iter().enumerate() {
        let yy = by + 1 + i as u16 * 2;
        c.put(2, yy, label, PARCHMENT, SOOT);
        let x = meter(c, 7, yy, 20, *pct);
        c.right(x + 5, yy, &format!("{pct}%"), IVORY, SOOT);
    }
    let tx = 38;
    c.put(tx, by, "cpu temp", PARCHMENT, SOOT);
    if let Some(t) = h.temp {
        c.put(tx + 9, by, &format!("{t}°C"), if t < 70 { IVORY } else { temp_colour(t) }, SOOT);
    }
    let cols = (w - tx - 2).min(60);
    chart(c, w - 2 - cols, by + 1, cols, 5, &h.temp_history);
    footer(c, false);
}

// ---------------------------------------------------------------- C · Large type

fn large(c: &mut Canvas, s: &Snapshot, scroll: u16, fallback: bool) {
    header(c, s, true);
    let (word, wc, ground) = status(s);
    c.ground(1, 7, ground);
    big(c, 2, 2, word, 1, wc, ground);
    let sx = 2 + big_width(word, 1) + 3;
    let lines: Vec<(String, u8)> = if s.attention.is_empty() {
        vec![
            (format!("{}/{} up", s.endpoints_ok(), s.endpoints.len()), IVORY),
            (format!("{}/{} apps ok", s.apps_healthy(), s.apps.len()), IVORY),
            ("0 alerts".into(), IVORY),
        ]
    } else {
        vec![
            (format!("{} signals", s.signals), IVORY),
            (format!("{} services", s.attention.len()), IVORY),
            (format!("{} alerts", s.alerts.len()), IVORY),
        ]
    };
    for (i, (t, col)) in lines.iter().enumerate() {
        c.put(sx, 2 + i as u16, t, *col, ground);
    }
    let w = c.w();
    let mut y = 8;
    for a in s.attention.iter().take(3) {
        let (m, col) = match a.severity {
            Severity::Fault => ("■", EMBER),
            Severity::Deploy => ("▲", HEATHER_HI),
        };
        c.put(2, y, m, col, SOOT);
        c.put(4, y, a.service, IVORY, SOOT);
        c.put(21, y, a.parts[0], col, SOOT);
        if a.parts.len() > 1 {
            c.put(35, y, &format!("+{}", a.parts.len() - 1), SLATE, SOOT);
        }
        c.right(w - 2, y, a.since, SLATE, SOOT);
        y += 1;
    }
    if s.attention.is_empty() {
        c.put(2, y, "Nothing needs attention.", SLATE, SOOT);
        y += 1;
    }
    c.fill(y, 1, w - 1, '─', ASH, SOOT);
    y += 1;

    // endpoints: two columns in catalog order, scrolls if the console is short
    let bottom = c.h() - 4;
    let per_col = ((s.endpoints.len() as u16) + 1) / 2;
    let avail = bottom.saturating_sub(y);
    let scroll = scroll.min(per_col.saturating_sub(avail));
    let colw = (w - 4) / 2;
    for (i, e) in s.endpoints.iter().enumerate() {
        let (col, row) = (i as u16 / per_col, i as u16 % per_col);
        if row < scroll || row - scroll >= avail {
            continue;
        }
        let (x, yy) = (2 + col * colw, y + row - scroll);
        let (m, mc) = marker(&e.check);
        let failing = matches!(e.check, Check::Fail { .. });
        c.put(x, yy, m, mc, SOOT);
        c.put(x + 2, yy, e.name, if failing { IVORY } else { PARCHMENT }, SOOT);
        if let Check::Fail { what, .. } = e.check {
            c.right(x + colw - 2, yy, what.split(' ').last().unwrap_or(what), EMBER, SOOT);
        }
    }
    if scroll + avail < per_col {
        c.right(w - 2, bottom - 1, &format!("↓ {}", per_col - scroll - avail), AMBER, SOOT);
    }
    let bad = s.apps.iter().filter(|a| app_problem(a)).count();
    let x = c.put(2, bottom, "apps", PARCHMENT, SOOT);
    c.put(x + 1, bottom, &format!("{} of {} synced and healthy", s.apps.len() - bad, s.apps.len()), HEATHER, SOOT);
    let h = &s.host;
    let iy = c.h() - 3;
    let mut x = c.put(2, iy, "cpu  ", PARCHMENT, SOOT);
    x = meter(c, x, iy, 10, h.cpu);
    x = c.put(x + 1, iy, &format!("{}%", h.cpu), IVORY, SOOT);
    x = c.put(x + 3, iy, "mem ", PARCHMENT, SOOT);
    x = meter(c, x, iy, 10, h.mem);
    c.put(x + 1, iy, &format!("{}%", h.mem), IVORY, SOOT);
    let iy = iy + 1;
    let mut x = c.put(2, iy, "root ", PARCHMENT, SOOT);
    x = meter(c, x, iy, 10, h.root);
    x = c.put(x + 1, iy, &format!("{}%", h.root), IVORY, SOOT);
    x = c.put(x + 3, iy, "temp ", PARCHMENT, SOOT);
    if let Some(t) = h.temp {
        c.put(x, iy, &format!("{t}°C"), if t < 70 { IVORY } else { temp_colour(t) }, SOOT);
    }
    if fallback {
        c.right(w, 0, "compact ", SLATE, RAISED);
    }
    footer(c, true);
}

fn tiny(c: &mut Canvas, s: &Snapshot) {
    let (word, wc, ground) = status(s);
    c.ground(0, c.h(), ground);
    c.put(1, 0, word, wc, ground);
    c.put(1, 1, &summary(s)[0].0, IVORY, ground);
    c.put(1, 2, "console too small for the dashboard", SLATE, ground);
}
