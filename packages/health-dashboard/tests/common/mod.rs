//! Snapshot -> derived view -> rendered frame, through Ratatui's TestBackend.
#![allow(dead_code)]

use health_dashboard::Dashboard;
use health_dashboard::fixtures::{self, Fixture, Scenario};
use health_dashboard::text::is_supported;
use jiff::Timestamp;
use jiff::tz::TimeZone;
use ratatui::Terminal;
use ratatui::backend::TestBackend;
use ratatui::buffer::Buffer;
use ratatui::style::{Color, Modifier};

pub fn oslo() -> TimeZone {
    TimeZone::get("Europe/Oslo").unwrap()
}

pub fn dashboard(f: &Fixture) -> Dashboard {
    let mut d = Dashboard::new(f.catalog.clone(), oslo(), f.snapshot.collector_started_at);
    d.set_snapshot(f.snapshot.clone());
    d.set_night(Some(f.night.clone()));
    d
}

pub fn draw(d: &mut Dashboard, w: u16, h: u16, now: Timestamp) -> Screen {
    let mut term = Terminal::new(TestBackend::new(w, h)).unwrap();
    term.draw(|frame| d.render(frame.buffer_mut(), now)).unwrap();
    Screen(term.backend().buffer().clone())
}

pub fn render(sc: Scenario) -> Screen {
    render_at(sc, 160, 50)
}

pub fn render_at(sc: Scenario, w: u16, h: u16) -> Screen {
    let f = fixtures::fixture(sc);
    draw(&mut dashboard(&f), w, h, f.now)
}

/// Foreground and ground of the block-letter status word (its first pixel on row 3).
pub fn status_colours(s: &Screen) -> (u8, u8) {
    let x = s.line(3).chars().position(|c| c != ' ').expect("status word") as u16;
    (s.fg((x, 3)), s.bg((x, 3)))
}

pub struct Screen(pub Buffer);

impl Screen {
    pub fn line(&self, y: u16) -> String {
        (0..self.0.area.width).map(|x| self.0[(x, y)].symbol()).collect::<String>()
    }

    /// Cells `x0..x1` of row `y`.
    pub fn cols(&self, y: u16, x0: u16, x1: u16) -> String {
        (x0..x1.min(self.0.area.width)).map(|x| self.0[(x, y)].symbol()).collect()
    }

    pub fn lines(&self) -> Vec<String> {
        (0..self.0.area.height).map(|y| self.line(y)).collect()
    }

    pub fn text(&self) -> String {
        self.lines().join("\n")
    }

    pub fn contains(&self, needle: &str) -> bool {
        self.find(needle).is_some()
    }

    /// Cell position of the first occurrence of `needle`.
    pub fn find(&self, needle: &str) -> Option<(u16, u16)> {
        self.lines().iter().enumerate().find_map(|(y, l)| {
            l.find(needle).map(|b| (l[..b].chars().count() as u16, y as u16))
        })
    }

    pub fn at(&self, needle: &str) -> (u16, u16) {
        self.find(needle).unwrap_or_else(|| panic!("{needle:?} not on screen:\n{}", self.text()))
    }

    pub fn fg(&self, (x, y): (u16, u16)) -> u8 {
        slot(self.0[(x, y)].fg)
    }

    pub fn bg(&self, (x, y): (u16, u16)) -> u8 {
        slot(self.0[(x, y)].bg)
    }

    /// Only approved glyphs, foregrounds in slots 0-15, grounds in 0-7, no attributes.
    pub fn assert_console_safe(&self) {
        for y in 0..self.0.area.height {
            for x in 0..self.0.area.width {
                let c = &self.0[(x, y)];
                for ch in c.symbol().chars() {
                    assert!(is_supported(ch), "unsupported glyph {ch:?} at {x},{y}:\n{}", self.text());
                }
                assert!(slot(c.fg) < 16, "foreground {:?} at {x},{y}", c.fg);
                assert!(slot(c.bg) < 8, "background {:?} at {x},{y}", c.bg);
                assert_eq!(c.modifier, Modifier::empty(), "attribute at {x},{y}");
            }
        }
    }
}

fn slot(c: Color) -> u8 {
    match c {
        Color::Indexed(n) => n,
        other => panic!("colour {other:?} is not a palette slot"),
    }
}
