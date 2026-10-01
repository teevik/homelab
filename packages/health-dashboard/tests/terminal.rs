//! The real binary in a pseudo-terminal with TERM=linux: Ctrl+C is the only exit and
//! leaves the terminal as it found it. A PTY cannot prove real VT palette, font or
//! screen behaviour; that remains actual-laptop acceptance.

use health_dashboard::fixtures::{self, Scenario};
use std::io::{Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

struct Pty {
    master: std::fs::File,
    slave: OwnedFd,
}

fn openpty() -> Pty {
    let (mut master, mut slave) = (0, 0);
    let size = libc::winsize { ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0 };
    let rc = unsafe { libc::openpty(&mut master, &mut slave, std::ptr::null_mut(), std::ptr::null(), &size) };
    assert_eq!(rc, 0, "openpty: {}", std::io::Error::last_os_error());
    unsafe { Pty { master: std::fs::File::from_raw_fd(master), slave: OwnedFd::from_raw_fd(slave) } }
}

fn inputs(dir: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("health-dashboard-{dir}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let f = fixtures::fixture(Scenario::Mixed);
    std::fs::write(dir.join("catalog.json"), serde_json::to_vec(&f.catalog).unwrap()).unwrap();
    std::fs::write(dir.join("snapshot.json"), serde_json::to_vec(&f.snapshot).unwrap()).unwrap();
    std::fs::write(dir.join("night.json"), serde_json::to_vec(&f.night).unwrap()).unwrap();
    dir
}

fn spawn(pty: &Pty, dir: &std::path::Path) -> Child {
    let fd = |p: &Pty| Stdio::from(p.slave.try_clone().unwrap());
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_health-dashboard"));
    cmd.args(["--catalog", "--snapshot", "--night"].iter().zip(["catalog.json", "snapshot.json", "night.json"]).flat_map(|(f, n)| [f.to_string(), dir.join(n).display().to_string()]))
        .env("TERM", "linux")
        .env("TZ", "UTC")
        .stdin(fd(pty))
        .stdout(fd(pty))
        .stderr(fd(pty));
    unsafe {
        cmd.pre_exec(|| {
            // a session of its own with the pty as controlling terminal, like a login
            if libc::setsid() < 0 || libc::ioctl(0, libc::TIOCSCTTY, 0) < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    cmd.spawn().unwrap()
}

fn collect(pty: &Pty) -> Arc<Mutex<Vec<u8>>> {
    let out = Arc::new(Mutex::new(vec![]));
    let (mut master, sink) = (pty.master.try_clone().unwrap(), out.clone());
    std::thread::spawn(move || {
        let mut buf = [0u8; 4096];
        while let Ok(n) = master.read(&mut buf) {
            if n == 0 {
                break;
            }
            sink.lock().unwrap().extend_from_slice(&buf[..n]);
        }
    });
    out
}

fn wait_for(out: &Arc<Mutex<Vec<u8>>>, needle: &str) -> bool {
    let end = Instant::now() + Duration::from_secs(10);
    while Instant::now() < end {
        if String::from_utf8_lossy(&out.lock().unwrap()).contains(needle) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    false
}

fn exit_within(child: &mut Child, limit: Duration) -> Option<std::process::ExitStatus> {
    let end = Instant::now() + limit;
    while Instant::now() < end {
        if let Some(status) = child.try_wait().unwrap() {
            return Some(status);
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    None
}

fn finish_session(pty: &Pty, child: &mut Child, dir: PathBuf) {
    pty.master.try_clone().unwrap().write_all(b"\x03").unwrap();
    let status = exit_within(child, Duration::from_secs(5));
    if status.is_none() {
        child.kill().unwrap();
        child.wait().unwrap();
    }
    std::fs::remove_dir_all(dir).ok();
    assert!(status.expect("Ctrl+C exits").success());
}

fn termios(fd: &OwnedFd) -> libc::termios {
    let mut t: libc::termios = unsafe { std::mem::zeroed() };
    assert_eq!(unsafe { libc::tcgetattr(fd.as_raw_fd(), &mut t) }, 0);
    t
}

#[test]
fn ctrl_c_restores_the_terminal_and_hands_back_the_shell() {
    let pty = openpty();
    let before = termios(&pty.slave);
    assert!(before.c_lflag & libc::ICANON != 0 && before.c_lflag & libc::ECHO != 0);
    let dir = inputs("ctrl-c");
    let mut child = spawn(&pty, &dir);
    let out = collect(&pty);
    let mut master = pty.master.try_clone().unwrap();

    // palette load (last slot, text) and a drawn frame
    assert!(wait_for(&out, "\x1b]Pfcdd6f4"), "palette load");
    assert!(wait_for(&out, "Changedetection"), "first frame");
    let raw = termios(&pty.slave);
    assert_eq!(raw.c_lflag & (libc::ICANON | libc::ECHO), 0, "raw mode while running");

    // q is not an exit key
    master.write_all(b"q").unwrap();
    assert_eq!(exit_within(&mut child, Duration::from_millis(500)), None, "q must be ignored");

    master.write_all(b"\x03").unwrap();
    let status = exit_within(&mut child, Duration::from_secs(5)).expect("Ctrl+C exits");
    assert!(status.success(), "{status:?}");
    assert!(wait_for(&out, "Run `dashboard` to open it again."));
    let text = String::from_utf8_lossy(&out.lock().unwrap()).to_string();

    let after = termios(&pty.slave);
    assert_eq!(after.c_lflag & (libc::ICANON | libc::ECHO), before.c_lflag & (libc::ICANON | libc::ECHO), "echo and canonical input restored");
    let reset = text.rfind("\x1b]R").expect("palette reset");
    assert!(reset > text.rfind("\x1b]P0").unwrap(), "reset after the last load");
    assert!(text.contains("\x1b[?1049h") && text[reset.saturating_sub(64)..].contains("\x1b[?1049l"), "alternate screen left");
    assert!(text[reset.saturating_sub(64)..].contains("\x1b[?25h"), "cursor shown");
    let handoff = text.find("Dashboard closed. Monitoring and the night schedule keep running.").expect("handoff");
    assert!(handoff > reset, "handoff is printed after restoring");
    std::fs::remove_dir_all(dir).ok();
}

#[test]
fn a_missing_catalog_fails_before_touching_the_terminal() {
    let out = Command::new(env!("CARGO_BIN_EXE_health-dashboard"))
        .args(["--catalog", "/nonexistent/catalog.json", "--snapshot", "/nonexistent/s.json", "--night", "/nonexistent/n.json"])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(1));
    assert!(out.stdout.is_empty(), "no palette or screen sequences");
    assert!(String::from_utf8_lossy(&out.stderr).contains("catalog /nonexistent/catalog.json"));

    let usage = Command::new(env!("CARGO_BIN_EXE_health-dashboard")).arg("--catalog").output().unwrap();
    assert_eq!(usage.status.code(), Some(2));
}

#[test]
fn a_stopped_night_report_becomes_unavailable_and_reconnects_without_relaunch() {
    use health_dashboard::contract::NightState;
    use jiff::{SignedDuration, Timestamp};

    let pty = openpty();
    let dir = inputs("night-heartbeat");
    let mut night = fixtures::fixture(Scenario::Normal).night;
    night.state = NightState::Day { next_dark_at: Timestamp::now() + SignedDuration::from_hours(1) };
    let bytes = serde_json::to_vec(&night).unwrap();
    std::fs::write(dir.join("night.json"), &bytes).unwrap();
    let mut child = spawn(&pty, &dir);
    let out = collect(&pty);
    let initial = wait_for(&out, "screen dark 23:00-08:00");

    // Even a report whose schedule expiry is hours away loses its authority when
    // the translating collector stops. Use the public file interface, not Inputs.
    std::thread::sleep(Duration::from_secs(7));
    let unavailable = wait_for(&out, "night schedule state not reported");
    out.lock().unwrap().clear();
    std::fs::write(dir.join("night.new"), &bytes).unwrap();
    std::fs::rename(dir.join("night.new"), dir.join("night.json")).unwrap();
    let reconnected = wait_for(&out, "screen dark 23:00-08:00");
    finish_session(&pty, &mut child, dir);
    assert!(initial, "initial night report");
    assert!(unavailable, "a frozen file cannot confirm current night policy");
    assert!(reconnected, "a current report returns automatically");
}

#[test]
fn night_footer_uses_oslo_in_summer_and_winter_even_on_a_utc_host() {
    use health_dashboard::contract::NightState;
    for (case, morning) in [("summer", "2099-07-01T06:00:00Z"), ("winter", "2099-01-01T07:00:00Z")] {
        let pty = openpty();
        let dir = inputs(case);
        let mut night = fixtures::fixture(Scenario::Normal).night;
        night.state = NightState::QuietHours { until: morning.parse().unwrap(), wake_until: None };
        std::fs::write(dir.join("night.json"), serde_json::to_vec(&night).unwrap()).unwrap();
        let mut child = spawn(&pty, &dir);
        let out = collect(&pty);
        let correct = wait_for(&out, "quiet hours until 08:00");
        finish_session(&pty, &mut child, dir);
        assert!(correct, "{case}: the UTC host must still report the Oslo policy boundary at 08:00");
    }
}
