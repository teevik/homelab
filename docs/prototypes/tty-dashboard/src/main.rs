//! THROWAWAY prototype for "Choose the final TTY layout, typography, and palette"
//! (teevik/homelab#70). Three variants of the chosen Terminal-instruments direction,
//! switchable with left/right. All readings are illustrative fixtures.
//!
//!   cargo run --release                 interactive, in the current terminal
//!   cargo run --release -- --png out    console-faithful PNGs at 2560x1600

mod data;
mod palette;
mod raster;
mod ui;

use data::Scenario;
use ratatui::backend::TestBackend;
use ratatui::crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::Terminal;
use std::io::Write;
use ui::{Canvas, Variant};

/// The three real console geometries on the 2560x1600 panel with 256-glyph Terminus.
fn consoles() -> Vec<(&'static str, u16, u16, raster::Font)> {
    vec![
        ("160x50", 160, 50, raster::builtin(1)),
        ("106x33", 106, 33, raster::psf2("Terminus ter-i24b, doubled (24x48)", include_bytes!("../assets/ter-i24b.psf.gz"), 2)),
        ("80x25", 80, 25, raster::builtin(2)),
    ]
}

fn render_pngs(dir: &str) {
    std::fs::create_dir_all(dir).unwrap();
    for (size, w, h, font) in consoles() {
        for v in Variant::ALL {
            for sc in [Scenario::Normal, Scenario::Mixed] {
                let mut term = Terminal::new(TestBackend::new(w, h)).unwrap();
                term.draw(|f| {
                    let area = f.area();
                    let mut c = Canvas { buf: f.buffer_mut(), area };
                    ui::draw(v, &mut c, &data::snapshot(sc), 0);
                })
                .unwrap();
                let name = format!("{dir}/{}-{}-{size}.png", v.key(), if sc == Scenario::Normal { "normal" } else { "mixed" });
                let r = raster::render(term.backend().buffer(), &font, &name);
                let (cw, ch) = font.cell();
                println!(
                    "{name}: {} ({cw}x{ch} cells), missing glyphs {:?}, bright grounds {}, modifiers {}",
                    font.name, r.missing, r.bright_bg, r.modifiers
                );
            }
        }
    }
}

fn interactive() {
    let linux = std::env::var("TERM").as_deref() == Ok("linux");
    let (load, reset) = palette::load_sequences(linux);
    let mut terminal = ratatui::init();
    print!("{load}");
    std::io::stdout().flush().ok();
    let (mut vi, mut sc, mut scroll) = (0usize, Scenario::Mixed, 0u16);
    loop {
        let v = Variant::ALL[vi];
        terminal
            .draw(|f| {
                let area = f.area();
                let mut c = Canvas { buf: f.buffer_mut(), area };
                ui::draw(v, &mut c, &data::snapshot(sc), scroll);
                // prototype switcher: not part of the design
                let bar = format!(
                    " ◄ {} ►  n/m {}  {}x{}  PROTOTYPE ",
                    v.name(),
                    sc.label(),
                    area.width,
                    area.height
                );
                let x = area.width.saturating_sub(bar.chars().count() as u16) / 2;
                let y = area.height.saturating_sub(1);
                f.buffer_mut().set_string(x, y, bar, Style::new().fg(Color::Indexed(0)).bg(Color::Indexed(3)));
                let _ = Rect::default();
            })
            .unwrap();
        if let Event::Key(k) = event::read().unwrap() {
            if k.kind != KeyEventKind::Press {
                continue;
            }
            match k.code {
                KeyCode::Char('c') if k.modifiers.contains(KeyModifiers::CONTROL) => break,
                KeyCode::Char('q') => break,
                KeyCode::Right => (vi, scroll) = ((vi + 1) % 3, 0),
                KeyCode::Left => (vi, scroll) = ((vi + 2) % 3, 0),
                KeyCode::Char('n') => sc = Scenario::Normal,
                KeyCode::Char('m') => sc = Scenario::Mixed,
                KeyCode::Down => scroll += 1,
                KeyCode::Up => scroll = scroll.saturating_sub(1),
                _ => {}
            }
        }
    }
    print!("{reset}");
    ratatui::restore();
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("--png") => render_pngs(args.get(2).map(String::as_str).unwrap_or("screenshots")),
        Some("--nixos-colors") => {
            println!("console.colors = [");
            for i in 0..16 {
                println!("  \"{}\"", palette::hex(i));
            }
            println!("];");
        }
        _ => interactive(),
    }
}
