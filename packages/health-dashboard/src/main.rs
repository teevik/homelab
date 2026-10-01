//! health-dashboard: the laptop's console health display.
//!
//!   health-dashboard --catalog PATH --snapshot PATH --night PATH
//!   health-dashboard demo [SCENARIO]        an ILLUSTRATIVE fixture, no live data
//!   health-dashboard demo --json SCENARIO   that fixture's inputs, as JSON
//!
//! Ctrl+C is the only exit. The dashboard redraws on new data, freshness
//! transitions, resize and input; it has no animation and no per-second redraw.

use crossterm::event::{self, Event};
use crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::{cursor, execute};
use health_dashboard::contract::{Catalog, NightReport, Snapshot, VERSION};
use health_dashboard::fixtures::{self, Scenario};
use health_dashboard::{Dashboard, KeyOutcome, palette};
use jiff::tz::TimeZone;
use jiff::{SignedDuration, Timestamp};
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;
use serde::de::DeserializeOwned;
use std::io::{self, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::mpsc;
use std::time::Duration;
use std::time::Instant;

const USAGE: &str = "usage:
  health-dashboard --catalog PATH --snapshot PATH --night PATH
  health-dashboard demo [SCENARIO]
  health-dashboard demo --json SCENARIO";

/// How often input files are checked for replacement. A check is a `stat`; it only
/// leads to a redraw when the content changed.
const FILE_CHECK: Duration = Duration::from_secs(1);

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("demo") => demo(&args[1..]),
        Some("--help" | "-h") => {
            println!("{USAGE}");
            return ExitCode::SUCCESS;
        }
        _ => live(&args),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(Exit::Usage(msg)) => {
            eprintln!("health-dashboard: {msg}\n{USAGE}");
            ExitCode::from(2)
        }
        Err(Exit::Runtime(msg)) => {
            eprintln!("health-dashboard: {msg}");
            ExitCode::FAILURE
        }
    }
}

/// Why the program stops other than through Ctrl+C.
enum Exit {
    Usage(String),
    Runtime(String),
}

impl From<io::Error> for Exit {
    fn from(e: io::Error) -> Self {
        Exit::Runtime(e.to_string())
    }
}

// ---------------------------------------------------------------- entry points

struct Paths {
    catalog: PathBuf,
    snapshot: PathBuf,
    night: PathBuf,
}

fn parse(args: &[String]) -> Result<Paths, Exit> {
    let (mut catalog, mut snapshot, mut night) = (None, None, None);
    let mut it = args.iter();
    while let Some(flag) = it.next() {
        let slot = match flag.as_str() {
            "--catalog" => &mut catalog,
            "--snapshot" => &mut snapshot,
            "--night" => &mut night,
            other => return Err(Exit::Usage(format!("unknown argument {other:?}"))),
        };
        *slot = Some(PathBuf::from(it.next().ok_or_else(|| Exit::Usage(format!("{flag} needs a path")))?));
    }
    let need = |p: Option<PathBuf>, f: &str| p.ok_or_else(|| Exit::Usage(format!("{f} is required")));
    Ok(Paths { catalog: need(catalog, "--catalog")?, snapshot: need(snapshot, "--snapshot")?, night: need(night, "--night")? })
}

fn live(args: &[String]) -> Result<(), Exit> {
    let paths = parse(args)?;
    let catalog: Catalog = read(&paths.catalog).map_err(|e| Exit::Runtime(format!("catalog {}: {e}", paths.catalog.display())))?;
    let tz = TimeZone::get("Europe/Oslo").map_err(|e| Exit::Runtime(e.to_string()))?;
    let dashboard = Dashboard::new(catalog, tz, Timestamp::now());
    run(dashboard, Some(paths), None)?;
    if std::env::var_os("DASHBOARD_LAUNCHER").is_none() {
        println!("Dashboard closed. Monitoring and the night schedule keep running.");
        println!("Run `dashboard` to open it again.");
    }
    Ok(())
}

fn demo(args: &[String]) -> Result<(), Exit> {
    let scenario = |key: Option<&String>| match key {
        None => Ok(Scenario::Normal),
        Some(k) => Scenario::from_key(k).ok_or_else(|| {
            let keys: Vec<&str> = Scenario::ALL.iter().map(|s| s.key()).collect();
            Exit::Usage(format!("unknown scenario {k:?}; one of {}", keys.join(", ")))
        }),
    };
    if args.first().map(String::as_str) == Some("--json") {
        let f = fixtures::fixture(scenario(args.get(1))?);
        let doc = serde_json::json!({ "now": f.now, "catalog": f.catalog, "snapshot": f.snapshot, "night": f.night });
        println!("{}", serde_json::to_string_pretty(&doc).unwrap());
        return Ok(());
    }
    let sc = scenario(args.first())?;
    let f = fixtures::fixture(sc);
    let tz = TimeZone::get("Europe/Oslo").map_err(|e| Exit::Runtime(e.to_string()))?;
    let mut d = Dashboard::new(f.catalog, tz, f.snapshot.collector_started_at).with_label(sc.key());
    d.set_snapshot(f.snapshot);
    d.set_night(Some(f.night));
    run(d, None, Some(f.now))
}

// ---------------------------------------------------------------- inputs

fn read<T: DeserializeOwned>(path: &Path) -> Result<T, String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
    match value.get("version").and_then(|v| v.as_u64()) {
        Some(v) if v == VERSION as u64 => {}
        other => return Err(format!("unsupported contract version {other:?}, expected {VERSION}")),
    }
    serde_json::from_value(value).map_err(|e| e.to_string())
}

/// Identity of a file as last seen, so an unchanged file is not read again.
type Stamp = Option<(i64, i64, u64, u64)>;

fn stamp(path: &Path) -> Stamp {
    std::fs::metadata(path).ok().map(|m| (m.mtime(), m.mtime_nsec(), m.ino(), m.size()))
}

struct Inputs {
    paths: Paths,
    snapshot: Stamp,
    night: Stamp,
    first: bool,
    last_snapshot_change: Instant,
    night_deadline: Option<Instant>,
}

impl Inputs {
    /// Re-read whatever changed; returns whether the dashboard changed.
    fn refresh(&mut self, d: &mut Dashboard, now: Timestamp) -> bool {
        let mut changed = false;
        let s = stamp(&self.paths.snapshot);
        if self.first || s != self.snapshot {
            self.last_snapshot_change = Instant::now();
            self.snapshot = s;
            changed |= match (s, read::<Snapshot>(&self.paths.snapshot)) {
                (_, Ok(snapshot)) => d.set_snapshot(snapshot),
                (None, _) => d.snapshot_lost(now, "no collector snapshot; is the collector running?"),
                (Some(_), Err(e)) => d.snapshot_lost(now, &format!("collector snapshot unreadable: {e}")),
            };
        }
        if s.is_some() && self.last_snapshot_change.elapsed() > Duration::from_secs(15) {
            changed |= d.snapshot_lost(now, "collector heartbeat stopped; awaiting reconnect");
        }
        let n = stamp(&self.paths.night);
        if self.first || n != self.night {
            // Preserve only the file's remaining heartbeat lifetime on launch
            // or replacement, then track expiry monotonically across clock changes.
            self.night_deadline = std::fs::metadata(&self.paths.night).ok()
                .and_then(|metadata| metadata.modified().ok())
                .and_then(|modified| modified.elapsed().ok())
                .and_then(|age| Duration::from_secs(15).checked_sub(age))
                .map(|remaining| Instant::now() + remaining);
            self.night = n;
            changed |= d.set_night(read::<NightReport>(&self.paths.night).ok());
        }
        if self.night_deadline.is_none_or(|deadline| Instant::now() >= deadline) {
            changed |= d.set_night(None);
        }
        self.first = false;
        changed
    }
}

// ---------------------------------------------------------------- terminal

/// Raw mode, alternate screen, hidden cursor and the role palette, undone on drop
/// (normal exit or error) and by the panic hook.
struct Session {
    terminal: Terminal<CrosstermBackend<io::Stdout>>,
}

fn linux_console() -> bool {
    std::env::var("TERM").as_deref() == Ok("linux")
}

fn restore() {
    let (_, reset) = palette::sequences(linux_console());
    let mut out = io::stdout();
    // the Linux VT has no alternate screen, so clear what the dashboard drew
    let clear = if linux_console() { "\x1b[0m\x1b[2J\x1b[H" } else { "\x1b[0m" };
    let _ = execute!(out, LeaveAlternateScreen, cursor::Show);
    let _ = write!(out, "{reset}{clear}");
    let _ = out.flush();
    let _ = terminal::disable_raw_mode();
}

impl Session {
    fn start() -> io::Result<Session> {
        let default_hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            restore();
            default_hook(info);
        }));
        terminal::enable_raw_mode()?;
        let mut out = io::stdout();
        let (load, _) = palette::sequences(linux_console());
        execute!(out, EnterAlternateScreen, cursor::Hide)?;
        write!(out, "{load}")?;
        out.flush()?;
        Ok(Session { terminal: Terminal::new(CrosstermBackend::new(out))? })
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        restore();
    }
}

// ---------------------------------------------------------------- the loop

enum Wake {
    Terminal(Event),
    InputError(String),
}

fn run(mut d: Dashboard, paths: Option<Paths>, fixed_now: Option<Timestamp>) -> Result<(), Exit> {
    let now = || fixed_now.unwrap_or_else(Timestamp::now);
    let mut inputs = paths.map(|paths| Inputs { paths, snapshot: None, night: None, first: true, last_snapshot_change: Instant::now(), night_deadline: None });
    if let Some(i) = &mut inputs {
        i.refresh(&mut d, now());
    }
    let mut session = Session::start()?;
    #[cfg(feature = "test-panic")]
    if std::env::var("HEALTH_DASHBOARD_TEST_PANIC").as_deref() == Ok("1") {
        panic!("injected renderer panic");
    }

    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        loop {
            let wake = match event::read() {
                Ok(e) => Wake::Terminal(e),
                Err(e) => Wake::InputError(e.to_string()),
            };
            let stop = matches!(wake, Wake::InputError(_));
            if tx.send(wake).is_err() || stop {
                break;
            }
        }
    });

    let mut dirty = true;
    let mut due = now();
    loop {
        if dirty || now() >= due {
            let t = now();
            session.terminal.draw(|f| d.render(f.buffer_mut(), t))?;
            due = d.next_redraw(t);
            dirty = false;
        }
        let until_due = due.duration_since(now()).max(SignedDuration::ZERO).unsigned_abs();
        let wait = if inputs.is_some() { until_due.min(FILE_CHECK) } else { until_due };
        match rx.recv_timeout(wait) {
            Ok(Wake::Terminal(Event::Key(k))) => match d.key(k) {
                KeyOutcome::Exit => return Ok(()),
                KeyOutcome::Redraw => dirty = true,
                KeyOutcome::Ignore => {}
            },
            Ok(Wake::Terminal(Event::Resize(..))) => {
                session.terminal.autoresize()?;
                dirty = true;
            }
            Ok(Wake::Terminal(_)) | Err(mpsc::RecvTimeoutError::Timeout) => {}
            Ok(Wake::InputError(e)) => return Err(Exit::Runtime(format!("terminal input failed: {e}"))),
            Err(mpsc::RecvTimeoutError::Disconnected) => return Err(Exit::Runtime("terminal input stopped".into())),
        }
        if let Some(i) = &mut inputs {
            dirty |= i.refresh(&mut d, now());
        }
    }
}
