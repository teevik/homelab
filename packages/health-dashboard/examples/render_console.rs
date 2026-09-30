//! Visual review: console-faithful PNGs of the illustrative fixtures.
//!
//!   cargo run --example render_console -- <out-dir>
//!
//! Emulates what the Linux VT and fbcon show: the kernel's built-in 256-glyph
//! TER16x32 font looked up through the default CP437 table, foregrounds from palette
//! slots 0-15 and grounds folded onto slots 0-7. Anything the console could not show
//! is reported rather than drawn nicely. This is design evidence for the frame, not
//! proof of real fbcon behaviour or readability at a distance.

use health_dashboard::Dashboard;
use health_dashboard::contract::{CatalogEndpoint, Check, EndpointResult};
use health_dashboard::fixtures::{self, Fixture, Scenario, ago};
use health_dashboard::palette::PALETTE;
use jiff::tz::TimeZone;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier};
use std::collections::HashMap;

struct Font {
    glyphs: Vec<&'static [u8]>,
    map: HashMap<char, usize>,
}

fn font() -> Font {
    let mut map = HashMap::new();
    for line in include_str!("console/cp437.uni").lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut parts = line.split_whitespace();
        let idx = usize::from_str_radix(parts.next().unwrap().trim_start_matches("0x"), 16).unwrap();
        for u in parts {
            let cp = u32::from_str_radix(u.trim_start_matches("U+"), 16).unwrap();
            map.entry(char::from_u32(cp).unwrap()).or_insert(idx);
        }
    }
    Font { glyphs: include_bytes!("console/ter16x32.bin").chunks(64).collect(), map }
}

fn slot(c: Color) -> usize {
    match c {
        Color::Indexed(n) if n < 16 => n as usize,
        other => panic!("only palette slots 0-15 are allowed, got {other:?}"),
    }
}

fn png(buf: &Buffer, font: &Font, path: &str) {
    let (cw, ch) = (16, 32);
    let area = buf.area;
    let (pw, ph) = (area.width as usize * cw, area.height as usize * ch);
    let mut px = vec![0u8; pw * ph * 3];
    let (mut missing, mut bright, mut attrs) = (vec![], 0, 0);
    for y in 0..area.height {
        for x in 0..area.width {
            let cell = &buf[(x, y)];
            let c = cell.symbol().chars().next().unwrap_or(' ');
            let g = font.map.get(&c).copied().unwrap_or_else(|| {
                if !missing.contains(&c) {
                    missing.push(c);
                }
                font.map[&'?']
            });
            if cell.modifier != Modifier::empty() {
                attrs += 1;
            }
            let mut bg = slot(cell.bg);
            if bg >= 8 {
                bright += 1;
                bg -= 8;
            }
            let (f, b) = (PALETTE[slot(cell.fg)], PALETTE[bg]);
            for py in 0..ch {
                for pxx in 0..cw {
                    let on = font.glyphs[g][py * 2 + pxx / 8] & (0x80 >> (pxx % 8)) != 0;
                    let o = ((y as usize * ch + py) * pw + x as usize * cw + pxx) * 3;
                    px[o..o + 3].copy_from_slice(if on { &f } else { &b });
                }
            }
        }
    }
    let file = std::io::BufWriter::new(std::fs::File::create(path).unwrap());
    let mut enc = png::Encoder::new(file, pw as u32, ph as u32);
    enc.set_color(png::ColorType::Rgb);
    enc.set_depth(png::BitDepth::Eight);
    enc.write_header().unwrap().write_image_data(&px).unwrap();
    println!("{path}: missing glyphs {missing:?}, bright grounds {bright}, attributes {attrs}");
}

fn render(f: &Fixture, label: &str, w: u16, h: u16, scroll: usize) -> Buffer {
    let tz = TimeZone::get("Europe/Oslo").unwrap();
    let mut d = Dashboard::new(f.catalog.clone(), tz, f.snapshot.collector_started_at).with_label(label);
    d.set_snapshot(f.snapshot.clone());
    d.set_night(Some(f.night.clone()));
    let mut buf = Buffer::empty(Rect::new(0, 0, w, h));
    d.render(&mut buf, f.now);
    for _ in 0..scroll {
        d.key(crossterm::event::KeyEvent::from(crossterm::event::KeyCode::Down));
        d.render(&mut buf, f.now);
    }
    buf
}

/// Twelve more endpoints than today, with long live names and reasons.
fn grown() -> Fixture {
    let mut f = fixtures::fixture(Scenario::Mixed);
    for i in 1..=12 {
        let id = format!("extra-{i}");
        let name = if i == 3 { "A Considerably Longer Service Name".to_string() } else { format!("Extra service {i}") };
        f.catalog.endpoints.push(CatalogEndpoint { id: id.clone(), name, app: None });
        let check = if i % 5 == 0 {
            Check::Fail { reason: "TLS certificate verification failed for the upstream".into(), since: ago(f.now, 90) }
        } else {
            Check::Ok { latency_ms: 20 + i }
        };
        f.snapshot.endpoints.insert(id, EndpointResult { observed_at: ago(f.now, 21), check });
    }
    f
}

fn main() {
    let dir = std::env::args().nth(1).unwrap_or_else(|| "screenshots".into());
    std::fs::create_dir_all(&dir).unwrap();
    let font = font();
    for (i, sc) in Scenario::ALL.iter().enumerate() {
        let f = fixtures::fixture(*sc);
        png(&render(&f, sc.key(), 160, 50, 0), &font, &format!("{dir}/{:02}-{}.png", i + 1, sc.key()));
    }
    let g = grown();
    png(&render(&g, "grown catalog", 160, 50, 0), &font, &format!("{dir}/grown-160x50.png"));
    png(&render(&g, "grown catalog", 160, 50, 99), &font, &format!("{dir}/grown-160x50-scrolled.png"));
    png(&render(&g, "grown catalog", 150, 45, 0), &font, &format!("{dir}/grown-150x45.png"));
    for (sc, w, h) in [
        (Scenario::Mixed, 149, 45),
        (Scenario::Mixed, 106, 33),
        (Scenario::ManyHttp, 106, 33),
        (Scenario::Mixed, 80, 25),
        (Scenario::MonitoringDown, 80, 25),
        (Scenario::Normal, 60, 20),
        (Scenario::ColdStart, 60, 20),
        (Scenario::Mixed, 59, 20),
    ] {
        let f = fixtures::fixture(sc);
        png(&render(&f, sc.key(), w, h, 0), &font, &format!("{dir}/{}-{w}x{h}.png", sc.key()));
    }
}
