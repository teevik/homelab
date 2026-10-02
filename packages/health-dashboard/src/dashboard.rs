//! Presentation and input state: the inputs last read, the scroll position, and when
//! the next frame is due. Frames are drawn on new data, freshness transitions, resize
//! and input, never on a timer loop.

use crate::contract::{Catalog, Failure, NightReport, NightState, Snapshot, SourceReport, Sources, VERSION};
use crate::health::{self, Health};
use crate::ui::{self, View};
use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use jiff::tz::TimeZone;
use jiff::{SignedDuration, Timestamp};
use ratatui::buffer::Buffer;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum KeyOutcome {
    /// Ctrl+C: leave the dashboard deliberately.
    Exit,
    /// The key changed what is shown.
    Redraw,
    /// Everything else, including `q`.
    Ignore,
}

pub struct Dashboard {
    catalog: Catalog,
    snapshot: Snapshot,
    night: Option<NightReport>,
    tz: TimeZone,
    label: Option<String>,
    scroll: usize,
    overflow: bool,
}

impl Dashboard {
    /// Before the collector's first snapshot every source is waiting.
    pub fn new(catalog: Catalog, tz: TimeZone, started: Timestamp) -> Self {
        let waiting = SourceReport::default();
        let snapshot = Snapshot {
            version: VERSION,
            collector_started_at: started,
            sources: Sources { host: waiting.clone(), http: waiting.clone(), argo: waiting.clone(), alerts: waiting },
            host: Default::default(),
            endpoints: Default::default(),
            apps: Default::default(),
            workloads: vec![],
            alerts: vec![],
            recoveries: vec![],
        };
        Dashboard { catalog, snapshot, night: None, tz, label: None, scroll: 0, overflow: false }
    }

    /// Demo entry point only: name the illustrative fixture in the header.
    pub fn with_label(mut self, label: &str) -> Self {
        self.label = Some(label.to_string());
        self
    }

    /// A new collector snapshot. Returns whether anything changed.
    pub fn set_snapshot(&mut self, s: Snapshot) -> bool {
        let changed = s != self.snapshot;
        self.snapshot = s;
        changed
    }

    /// The collector's snapshot is gone or unreadable. Every source becomes
    /// unavailable at once, keeping the last values it had as retained results, so a
    /// disconnected collector can never leave a frozen ALL CLEAR.
    pub fn snapshot_lost(&mut self, since: Timestamp, reason: &str) -> bool {
        let mut s = self.snapshot.clone();
        let sources = &mut s.sources;
        for src in [&mut sources.host, &mut sources.http, &mut sources.argo, &mut sources.alerts] {
            if src.failure.as_ref().is_none_or(|f| f.reason != reason) {
                src.failure = Some(Failure { since, reason: reason.to_string() });
            }
        }
        self.set_snapshot(s)
    }

    /// The night-policy controller's report, or `None` when it is missing.
    pub fn set_night(&mut self, n: Option<NightReport>) -> bool {
        let changed = n != self.night;
        self.night = n;
        changed
    }

    pub fn key(&mut self, k: KeyEvent) -> KeyOutcome {
        if k.kind == KeyEventKind::Release {
            return KeyOutcome::Ignore;
        }
        match k.code {
            KeyCode::Char('c') if k.modifiers.contains(KeyModifiers::CONTROL) => KeyOutcome::Exit,
            KeyCode::Down if self.overflow => {
                self.scroll += 1;
                KeyOutcome::Redraw
            }
            KeyCode::Up if self.scroll > 0 => {
                self.scroll -= 1;
                KeyOutcome::Redraw
            }
            _ => KeyOutcome::Ignore,
        }
    }

    pub fn health(&self, now: Timestamp) -> Health {
        health::derive(&self.catalog, &self.snapshot, now)
    }

    pub fn render(&mut self, buf: &mut Buffer, now: Timestamp) {
        let health = self.health(now);
        let view = View { health: &health, snapshot: &self.snapshot, night: self.night.as_ref(), now, tz: &self.tz, label: self.label.as_deref() };
        let drawn = ui::draw(buf, &view, self.scroll);
        self.scroll = drawn.scroll;
        self.overflow = drawn.overflow;
    }

    /// When the next frame is due without new input: the next freshness boundary,
    /// recovery expiry or night-state change, or the next minute for the clock.
    pub fn next_redraw(&self, now: Timestamp) -> Timestamp {
        let minute = SignedDuration::from_mins(1);
        let into_minute = SignedDuration::from_nanos(now.as_nanosecond().rem_euclid(minute.as_nanos()) as i64);
        let mut next = now - into_minute + minute;
        let mut consider = |t: Timestamp| {
            if t > now && t < next {
                next = t;
            }
        };
        if let Some(t) = self.health(now).next_change {
            consider(t);
        }
        if let Some(n) = &self.night {
            match &n.state {
                NightState::Away { wake_until } => {
                    wake_until.map(&mut consider);
                },
                NightState::Day { next_dark_at } => consider(*next_dark_at),
                NightState::QuietHours { until, wake_until } | NightState::Bedtime { until, wake_until } => {
                    consider(*until);
                    wake_until.map(&mut consider);
                }
            }
        }
        next
    }
}
