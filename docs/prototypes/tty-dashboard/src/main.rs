//! THROWAWAY prototype for "Approve TTY health states and interaction details"
//! (teevik/homelab#71): the selected A · Instrument ledger at 160x50, stepped through
//! every health/data scenario. All readings are illustrative fixtures.
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
use ratatui::Terminal;
use std::io::Write;
use ui::Canvas;

fn proto_label(i: usize) -> String {
    let sc = Scenario::ALL[i];
    format!("PROTOTYPE {}/{} {} · ILLUSTRATIVE", i + 1, Scenario::ALL.len(), sc.label())
}

fn render_pngs(dir: &str) {
    std::fs::create_dir_all(dir).unwrap();
    let font = raster::builtin(1);
    for (i, sc) in Scenario::ALL.iter().enumerate() {
        let mut term = Terminal::new(TestBackend::new(160, 50)).unwrap();
        term.draw(|f| {
            let area = f.area();
            let mut c = Canvas { buf: f.buffer_mut(), area };
            ui::draw(&mut c, &data::snapshot(*sc), 0, &proto_label(i));
        })
        .unwrap();
        let name = format!("{dir}/{:02}-{}.png", i + 1, sc.key());
        let r = raster::render(term.backend().buffer(), &font, &name);
        println!("{name}: missing glyphs {:?}, bright grounds {}, modifiers {}", r.missing, r.bright_bg, r.modifiers);
    }
}

fn interactive() {
    let linux = std::env::var("TERM").as_deref() == Ok("linux");
    let (load, reset) = palette::load_sequences(linux);
    let mut terminal = ratatui::init();
    print!("{load}");
    std::io::stdout().flush().ok();
    let (mut i, mut scroll) = (0usize, 0u16);
    let n = Scenario::ALL.len();
    loop {
        terminal
            .draw(|f| {
                let area = f.area();
                let mut c = Canvas { buf: f.buffer_mut(), area };
                let label = format!("{}  ←/→", proto_label(i));
                ui::draw(&mut c, &data::snapshot(Scenario::ALL[i]), scroll, &label);
            })
            .unwrap();
        // redraw only on input or resize: the production UI adds new data and
        // freshness transitions, never a timer loop
        match event::read().unwrap() {
            Event::Key(k) if k.kind == KeyEventKind::Press => match k.code {
                KeyCode::Char('c') if k.modifiers.contains(KeyModifiers::CONTROL) => break,
                KeyCode::Right => (i, scroll) = ((i + 1) % n, 0),
                KeyCode::Left => (i, scroll) = ((i + n - 1) % n, 0),
                KeyCode::Down => scroll += 1,
                KeyCode::Up => scroll = scroll.saturating_sub(1),
                _ => {}
            },
            _ => {}
        }
    }
    print!("{reset}");
    ratatui::restore();
    // what the shell shows after Ctrl+C; the prototype stays stopped
    println!("Dashboard closed. Monitoring and the night schedule keep running.");
    println!("Run `dashboard` to open it again.");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("--png") => render_pngs(args.get(2).map(String::as_str).unwrap_or("screenshots/states")),
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
