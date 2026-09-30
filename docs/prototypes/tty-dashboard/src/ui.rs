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
            self.fill(y, 0, self.w(), ' ', BODY, bg);
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
    c.ground(0, 1, BAR);
    let x = c.put(1, 0, "HOMELAB", BRAND, BAR);
    if !short {
        c.put(x + 2, 0, "host health", META, BAR);
    }
    let tag = if short { "ILLUSTRATIVE" } else { "PROTOTYPE - ILLUSTRATIVE DATA, NOT LIVE" };
    let w = c.w();
    c.put(w / 2 - tag.len() as u16 / 2, 0, tag, WARM, BAR);
    let clock = format!("{}  {} ", s.date, s.clock);
    let clock = if short { format!("{} ", s.clock) } else { clock };
    c.right(w, 0, &clock, TEXT, BAR);
}

fn footer(c: &mut Canvas, short: bool) {
    let y = c.h() - 1;
    c.ground(y, y + 1, BAR);
    let mut x = c.put(1, y, "Ctrl+C", TEXT, BAR);
    x = c.put(x + 1, y, "shell", META, BAR);
    if !short {
        x = c.put(x + 3, y, "dashboard", TEXT, BAR);
        c.put(x + 1, y, "relaunch", META, BAR);
    }
    let night = if short { "dark 23-08 " } else { "screen dark 23:00-08:00, in 1h 18m " };
    let w = c.w();
    c.right(w, y, night, COOL, BAR);
}

fn meter(c: &mut Canvas, x: u16, y: u16, cells: u16, pct: u8) -> u16 {
    let fill = ((pct as u32 * cells as u32 + 50) / 100) as u16;
    let col = heat(pct, 80, 90);
    c.fill(y, x, x + fill, '█', col, GROUND);
    c.fill(y, x + fill, x + cells, '░', RULE, GROUND);
    x + cells
}

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
    c.put(x, y + rows + 1, &format!("-{}m", shown.len()), META, GROUND);
    c.right(x + cols, y + rows + 1, "now", META, GROUND);
}

fn marker(check: &Check) -> (&'static str, u8) {
    match check {
        Check::Ok { .. } => ("·", OK),
        Check::Fail { .. } => ("■", FAIL),
    }
}

fn sync_text(a: &App) -> (&'static str, u8) {
    match a.sync {
        Sync::Synced => ("synced", DEPLOY),
        Sync::OutOfSync => ("OutOfSync", DEPLOY_HI),
    }
}

fn health_text(a: &App) -> (&'static str, u8) {
    match a.health {
        Health::Healthy => ("healthy", DEPLOY),
        Health::Progressing => ("Progressing", DEPLOY_HI),
        Health::Degraded => ("Degraded", FAIL),
    }
}

fn app_problem(a: &App) -> bool {
    a.sync != Sync::Synced || a.health != Health::Healthy || a.restarts.is_some()
}

fn status(s: &Snapshot) -> (&'static str, u8, u8) {
    if s.attention.is_empty() {
        ("ALL CLEAR", OK, GROUND)
    } else {
        ("ATTENTION", TEXT, ALERT_GROUND)
    }
}

fn summary(s: &Snapshot) -> Vec<(String, u8)> {
    let (ne, na) = (s.endpoints.len(), s.apps.len());
    if s.attention.is_empty() {
        vec![
            (format!("{} of {ne} endpoints respond", s.endpoints_ok()), TEXT),
            (format!("{} of {na} apps synced and healthy", s.apps_healthy()), TEXT),
            ("no active alerts".into(), TEXT),
            (String::new(), META),
            ("all sources current, oldest 21s".into(), META),
        ]
    } else {
        let services = s.attention.len();
        vec![
            (format!("{} signals on {services} services", s.signals), TEXT),
            (format!("{} of {ne} endpoints failing", ne - s.endpoints_ok()), TEXT),
            (
                format!(
                    "{} of {na} apps unhealthy, {} out of sync",
                    na - s.apps_healthy(),
                    na - s.apps_synced()
                ),
                TEXT,
            ),
            (format!("{} active alerts", s.alerts.len()), TEXT),
            ("all sources current, oldest 21s".into(), BODY),
        ]
    }
}

fn attention_line(c: &mut Canvas, x: u16, y: u16, a: &Attention, name_w: u16, bg: u8) -> u16 {
    let (m, col) = match a.severity {
        Severity::Fault => ("■", FAIL),
        Severity::Deploy => ("▲", DEPLOY_HI),
    };
    c.put(x, y, m, col, bg);
    c.put(x + 2, y, a.service, TEXT, bg);
    let mut cx = x + 2 + name_w;
    for (i, p) in a.parts.iter().enumerate() {
        if i > 0 {
            cx = c.put(cx, y, "  ·  ", RULE, bg);
        }
        let pc = if p.starts_with("app") || p.contains("restarts") {
            DEPLOY_HI
        } else if p.starts_with("alert") {
            WARM
        } else if *p == "endpoint ok" {
            OK
        } else {
            FAIL
        };
        cx = c.put(cx, y, p, pc, bg);
    }
    cx
}

// ---------------------------------------------------------------- A · Instrument ledger

pub fn draw(v: Variant, c: &mut Canvas, s: &Snapshot, scroll: u16) {
    c.ground(0, c.h(), GROUND);
    let fallback = match v {
        Variant::A => c.w() < 100 || c.h() < 30,
        Variant::B => c.w() < 100 || c.h() < 30,
        Variant::C => false,
    };
    if c.w() < 60 || c.h() < 20 {
        tiny(c, s);
    } else if fallback || v == Variant::C {
        large(c, s, scroll, fallback);
    } else if v == Variant::A && (c.w() < 150 || c.h() < 45) {
        ledger_medium(c, s, scroll);
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
        c.put(3, 12, "Nothing needs attention.", META, GROUND);
    }
    for (i, a) in s.attention.iter().take(4).enumerate() {
        attention_line(c, 3, 12 + i as u16, a, 18, GROUND);
        c.right(c.w() - 2, 12 + i as u16, &format!("since {}", a.since), META, GROUND);
    }
    c.fill(16, 1, c.w() - 1, '─', RULE, GROUND);

    // ledger: endpoints | deployment ; host on the right
    let (xm, xn, xc, xl, xd, xa, xs, xh) = (3, 5, 24, 40, 49, 51, 71, 83);
    let hx = 101;
    c.put(xm, 17, "ENDPOINTS", LABEL, GROUND);
    c.put(xm + 10, 17, "internal HTTP checks, every 30s", META, GROUND);
    c.put(xa, 17, "DEPLOYMENT", LABEL, GROUND);
    c.put(xa + 11, 17, "argo cd", META, GROUND);
    for (x, t) in [(xn, "service"), (xc, "check"), (xl, "latency"), (xa, "app"), (xs, "sync"), (xh, "health")] {
        c.put(x, 18, t, META, GROUND);
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
            let idc = if app_problem(a) { TEXT } else { BODY };
            c.put(xa, y, a.id, idc, bg);
            c.put(xs, y, st_, sc, bg);
            c.put(xh, y, ht, hc, bg);
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
                let (m, mc) = marker(&e.check);
                c.put(xm, y, m, mc, bg);
                c.put(xn, y, e.name, if failing { TEXT } else { BODY }, bg);
                match &e.check {
                    Check::Ok { ms } => {
                        c.put(xc, y, "ok", OK, bg);
                        c.right(xl + 6, y, &format!("{ms} ms"), META, bg);
                    }
                    Check::Fail { what, for_ } => {
                        c.put(xc, y, what, FAIL, bg);
                        c.right(xl + 6, y, &format!("for {for_}"), TEXT, bg);
                    }
                }
                c.put(xd, y, "│", RULE, GROUND);
                match e.app.and_then(|id| s.app(id)) {
                    Some(a) => app_cols(c, a, GROUND),
                    None => {
                        c.put(xa, y, "no app (host)", META, GROUND);
                    }
                }
            }
            Row::App(a) => {
                c.put(xd, y, "│", RULE, GROUND);
                app_cols(c, a, GROUND);
            }
        }
    }
    if scroll + avail < rows.len() {
        c.put(xn, bottom, &format!("↓ {} more rows", rows.len() - scroll - avail), WARM, GROUND);
    }
    if scroll > 0 {
        c.right(xd - 1, 18, &format!("↑ {scroll} above"), WARM, GROUND);
    }

    // host instruments
    c.fill(17, hx - 3, hx - 2, ' ', RULE, GROUND);
    for y in 17..c.h() - 2 {
        c.put(hx - 3, y, "│", RULE, GROUND);
    }
    c.put(hx, 17, "HOST", LABEL, GROUND);
    c.put(hx + 5, 17, "every 5s", META, GROUND);
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
        c.put(hx, y, label, BODY, GROUND);
        let x = meter(c, hx + 5, y, mw, *pct);
        c.right(x + 5, y, &format!("{pct}%"), TEXT, GROUND);
        c.put(x + 7, y, detail, META, GROUND);
    }
    let ty = 26;
    c.put(hx, ty, "cpu temp", BODY, GROUND);
    match h.temp {
        Some(t) => {
            let x = c.put(hx + 10, ty, &format!("{t}°C"), if t < 70 { TEXT } else { temp_colour(t) }, GROUND);
            c.put(x + 2, ty, "Tctl, last hour", META, GROUND);
        }
        None => {
            c.put(hx + 10, ty, "unavailable", META, GROUND);
        }
    }
    let cols = (c.w() - hx - 6).min(60);
    for (lbl, r) in [("90°", 0u16), ("70°", 3), ("50°", 6)] {
        c.put(hx, ty + 2 + r, lbl, META, GROUND);
    }
    chart(c, hx + 5, ty + 2, cols, 8, &h.temp_history);

    let sy = ty + 13;
    c.put(hx, sy, "SOURCES", LABEL, GROUND);
    for (i, src) in s.sources.iter().enumerate() {
        let y = sy + 1 + i as u16;
        c.put(hx, y, "·", OK, GROUND);
        c.put(hx + 2, y, src.name, BODY, GROUND);
        c.right(hx + 22, y, src.age, META, GROUND);
        c.put(hx + 24, y, "current", OK, GROUND);
    }
    footer(c, false);
}

// ------------------------------------------- A at 106x33 (24x48 font): same ledger, host strip

fn ledger_medium(c: &mut Canvas, s: &Snapshot, scroll: u16) {
    header(c, s, false);
    let w = c.w();
    let (word, wc, ground) = status(s);
    c.ground(1, 7, ground);
    big(c, 2, 2, word, 1, wc, ground);
    let sx = 2 + big_width(word, 1) + 5;
    let lines: Vec<(String, u8)> = summary(s).into_iter().filter(|(t, _)| !t.is_empty()).take(4).collect();
    for (i, (t, col)) in lines.iter().enumerate() {
        c.put(sx, 2 + i as u16, t, *col, ground);
    }

    // attention: fixed 3-row slot
    if s.attention.is_empty() {
        c.put(2, 7, "Nothing needs attention.", META, GROUND);
    }
    for (i, a) in s.attention.iter().take(3).enumerate() {
        attention_line(c, 2, 7 + i as u16, a, 17, GROUND);
        c.right(w - 2, 7 + i as u16, &format!("since {}", a.since), META, GROUND);
    }
    if s.attention.len() > 3 {
        c.right(w - 2, 10, &format!("+{} more", s.attention.len() - 3), WARM, GROUND);
    }
    c.fill(10, 1, w - 1, '─', RULE, GROUND);

    let (xm, xn, xc, xl, xd, xa, xs, xh) = (2, 4, 22, 36, 46, 48, 67, 79);
    c.put(xm, 11, "ENDPOINTS", LABEL, GROUND);
    c.put(xm + 10, 11, "http, every 30s", META, GROUND);
    c.put(xa, 11, "DEPLOYMENT", LABEL, GROUND);
    c.put(xa + 11, 11, "argo cd", META, GROUND);
    for (x, t) in [(xn, "service"), (xc, "check"), (xl, "latency"), (xa, "app"), (xs, "sync"), (xh, "health")] {
        c.put(x, 12, t, META, GROUND);
    }
    let top = 13;
    let avail = (c.h() - 4 - top) as usize;
    let n = s.endpoints.len();
    let scroll = (scroll as usize).min(n.saturating_sub(avail));
    for (i, e) in s.endpoints.iter().skip(scroll).take(avail).enumerate() {
        let y = top + i as u16;
        let failing = matches!(e.check, Check::Fail { .. });
        let bg = if failing { ALERT_GROUND } else { GROUND };
        if failing {
            c.fill(y, xm - 1, xd, ' ', BODY, bg);
        }
        let (m, mc) = marker(&e.check);
        c.put(xm, y, m, mc, bg);
        c.put(xn, y, e.name, if failing { TEXT } else { BODY }, bg);
        match &e.check {
            Check::Ok { ms } => {
                c.put(xc, y, "ok", OK, bg);
                c.right(xl + 7, y, &format!("{ms} ms"), META, bg);
            }
            Check::Fail { what, for_ } => {
                c.put(xc, y, what, FAIL, bg);
                c.right(xl + 7, y, &format!("for {for_}"), TEXT, bg);
            }
        }
        c.put(xd, y, "│", RULE, GROUND);
        match e.app.and_then(|id| s.app(id)) {
            Some(a) => {
                let (st_, sc) = sync_text(a);
                let (ht, hc) = health_text(a);
                c.put(xa, y, a.id, if app_problem(a) { TEXT } else { BODY }, GROUND);
                c.put(xs, y, st_, sc, GROUND);
                c.put(xh, y, ht, hc, GROUND);
            }
            None => {
                c.put(xa, y, "no app (host)", META, GROUND);
            }
        }
    }
    let ny = top + avail as u16;
    if scroll + avail < n {
        c.put(xn, ny - 1, &format!("↓ {} more", n - scroll - avail), WARM, GROUND);
    }
    let rest = s.apps_without_endpoint();
    let ids: Vec<&str> = rest.iter().map(|a| a.id).collect();
    let x = c.put(xm, ny, "no endpoint", META, GROUND);
    let x = c.put(x + 2, ny, &ids.join(" "), BODY, GROUND);
    if rest.iter().all(|a| !app_problem(a)) {
        c.put(x + 3, ny, "synced, healthy", DEPLOY, GROUND);
    }

    // host strip: meters left, temperature history right
    let h = &s.host;
    let (y1, y2) = (c.h() - 3, c.h() - 2);
    let mut x = c.put(2, y1, "cpu  ", BODY, GROUND);
    x = meter(c, x, y1, 14, h.cpu);
    x = c.put(x + 1, y1, &format!("{:>3}%", h.cpu), TEXT, GROUND);
    x = c.put(x + 3, y1, "mem  ", BODY, GROUND);
    x = meter(c, x, y1, 14, h.mem);
    c.put(x + 1, y1, &format!("{:>3}%", h.mem), TEXT, GROUND);
    let mut x = c.put(2, y2, "root ", BODY, GROUND);
    x = meter(c, x, y2, 14, h.root);
    x = c.put(x + 1, y2, &format!("{:>3}%", h.root), TEXT, GROUND);
    c.put(x + 3, y2, "sources current", OK, GROUND);
    let tx = 66;
    c.put(tx, y1, "temp", BODY, GROUND);
    if let Some(t) = h.temp {
        c.put(tx, y2, &format!("{t}°C"), if t < 70 { TEXT } else { temp_colour(t) }, GROUND);
    }
    mini_chart(c, tx + 6, y1, w - 2 - (tx + 6), 2, &h.temp_history);
    footer(c, false);
}

/// Chart without axis rows, for the host strip.
fn mini_chart(c: &mut Canvas, x: u16, y: u16, cols: u16, rows: u16, hist: &[Option<u8>]) {
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
                    let ch = if lvl >= 2 * (rb + 1) { "█" } else if lvl == 2 * rb + 1 { "▄" } else { "░" };
                    let col = if ch == "░" { RULE } else { temp_colour(*t) };
                    c.put(cx, y + r, ch, col, GROUND);
                }
            }
        }
    }
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
        c.put(2, y, "Nothing needs attention.", META, GROUND);
        y += 2;
    } else {
        c.put(2, y, "NEEDS ATTENTION", LABEL, GROUND);
        c.put(18, y, "worst first", META, GROUND);
        y += 1;
        for a in &s.attention {
            attention_line(c, 2, y, a, 17, GROUND);
            c.right(w - 2, y, &format!("since {}", a.since), META, GROUND);
            y += 1;
        }
        y += 1;
    }

    // healthy endpoints collapse to a name grid
    let ok: Vec<&Endpoint> = s.endpoints.iter().filter(|e| matches!(e.check, Check::Ok { .. })).collect();
    c.put(2, y, "ENDPOINTS", LABEL, GROUND);
    c.put(12, y, &format!("{} of {} respond", ok.len(), s.endpoints.len()), META, GROUND);
    y += 1;
    let colw = (w - 4) / 4;
    let rows_needed = (ok.len() as u16 + 3) / 4;
    for (i, e) in ok.iter().enumerate() {
        let (col, row) = (i as u16 / rows_needed, i as u16 % rows_needed);
        let x = 2 + col * colw;
        c.put(x, y + row, "·", OK, GROUND);
        c.put(x + 2, y + row, e.name, BODY, GROUND);
        if let Check::Ok { ms } = e.check {
            c.right(x + colw - 1, y + row, &format!("{ms}ms"), META, GROUND);
        }
    }
    y += rows_needed + 1;
    let quiet: Vec<&str> = s.apps.iter().filter(|a| !app_problem(a)).map(|a| a.id).collect();
    c.put(2, y, "APPS", LABEL, GROUND);
    c.put(7, y, &format!("{} of {} synced and healthy", quiet.len(), s.apps.len()), META, GROUND);
    y += 1;
    let no_ep: Vec<&str> = s.apps_without_endpoint().iter().map(|a| a.id).collect();
    let x = c.put(2, y, "no endpoint: ", META, GROUND);
    c.put(x, y, &no_ep.join(", "), DEPLOY, GROUND);
    let _ = scroll;

    // instrument band along the bottom
    let by = c.h() - 9;
    c.fill(by - 1, 1, w - 1, '─', RULE, GROUND);
    let h = &s.host;
    for (i, (label, pct)) in [("cpu", h.cpu), ("mem", h.mem), ("root", h.root)].iter().enumerate() {
        let yy = by + 1 + i as u16 * 2;
        c.put(2, yy, label, BODY, GROUND);
        let x = meter(c, 7, yy, 20, *pct);
        c.right(x + 5, yy, &format!("{pct}%"), TEXT, GROUND);
    }
    let tx = 38;
    c.put(tx, by, "cpu temp", BODY, GROUND);
    if let Some(t) = h.temp {
        c.put(tx + 9, by, &format!("{t}°C"), if t < 70 { TEXT } else { temp_colour(t) }, GROUND);
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
            (format!("{}/{} up", s.endpoints_ok(), s.endpoints.len()), TEXT),
            (format!("{}/{} apps ok", s.apps_healthy(), s.apps.len()), TEXT),
            ("0 alerts".into(), TEXT),
        ]
    } else {
        vec![
            (format!("{} signals", s.signals), TEXT),
            (format!("{} services", s.attention.len()), TEXT),
            (format!("{} alerts", s.alerts.len()), TEXT),
        ]
    };
    for (i, (t, col)) in lines.iter().enumerate() {
        c.put(sx, 2 + i as u16, t, *col, ground);
    }
    let w = c.w();
    let mut y = 8;
    for a in s.attention.iter().take(3) {
        let (m, col) = match a.severity {
            Severity::Fault => ("■", FAIL),
            Severity::Deploy => ("▲", DEPLOY_HI),
        };
        c.put(2, y, m, col, GROUND);
        c.put(4, y, a.service, TEXT, GROUND);
        c.put(21, y, a.parts[0], col, GROUND);
        if a.parts.len() > 1 {
            c.put(35, y, &format!("+{}", a.parts.len() - 1), META, GROUND);
        }
        c.right(w - 2, y, a.since, META, GROUND);
        y += 1;
    }
    if s.attention.is_empty() {
        c.put(2, y, "Nothing needs attention.", META, GROUND);
        y += 1;
    }
    c.fill(y, 1, w - 1, '─', RULE, GROUND);
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
        c.put(x, yy, m, mc, GROUND);
        c.put(x + 2, yy, e.name, if failing { TEXT } else { BODY }, GROUND);
        if let Check::Fail { what, .. } = e.check {
            c.right(x + colw - 2, yy, what.split(' ').last().unwrap_or(what), FAIL, GROUND);
        }
    }
    if scroll + avail < per_col {
        c.right(w - 2, bottom - 1, &format!("↓ {}", per_col - scroll - avail), WARM, GROUND);
    }
    let bad = s.apps.iter().filter(|a| app_problem(a)).count();
    let x = c.put(2, bottom, "apps", BODY, GROUND);
    c.put(x + 1, bottom, &format!("{} of {} synced and healthy", s.apps.len() - bad, s.apps.len()), DEPLOY, GROUND);
    let h = &s.host;
    let iy = c.h() - 3;
    let mut x = c.put(2, iy, "cpu  ", BODY, GROUND);
    x = meter(c, x, iy, 10, h.cpu);
    x = c.put(x + 1, iy, &format!("{}%", h.cpu), TEXT, GROUND);
    x = c.put(x + 3, iy, "mem ", BODY, GROUND);
    x = meter(c, x, iy, 10, h.mem);
    c.put(x + 1, iy, &format!("{}%", h.mem), TEXT, GROUND);
    let iy = iy + 1;
    let mut x = c.put(2, iy, "root ", BODY, GROUND);
    x = meter(c, x, iy, 10, h.root);
    x = c.put(x + 1, iy, &format!("{}%", h.root), TEXT, GROUND);
    x = c.put(x + 3, iy, "temp ", BODY, GROUND);
    if let Some(t) = h.temp {
        c.put(x, iy, &format!("{t}°C"), if t < 70 { TEXT } else { temp_colour(t) }, GROUND);
    }
    if fallback {
        c.right(w, 0, "compact ", META, BAR);
    }
    footer(c, true);
}

fn tiny(c: &mut Canvas, s: &Snapshot) {
    let (word, wc, ground) = status(s);
    c.ground(0, c.h(), ground);
    c.put(1, 0, word, wc, ground);
    c.put(1, 1, &summary(s)[0].0, TEXT, ground);
    c.put(1, 2, "console too small for the dashboard", META, ground);
}
