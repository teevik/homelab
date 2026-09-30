//! Foreground child of the existing shell. Collection and power policy have no UI lifecycle.
use std::io::{self, Write};
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, ExitCode};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

static CANCELLED: AtomicBool = AtomicBool::new(false);
extern "C" fn cancel(_: libc::c_int) {
    CANCELLED.store(true, Ordering::Relaxed);
}

struct Terminal {
    saved: libc::termios,
}
impl Terminal {
    fn save() -> io::Result<Self> {
        let mut saved = unsafe { std::mem::zeroed() };
        if unsafe { libc::tcgetattr(0, &mut saved) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Self { saved })
    }
    fn restore(&self) {
        unsafe {
            libc::tcsetattr(0, libc::TCSANOW, &self.saved);
        }
        let reset =
            health_dashboard::palette::sequences(std::env::var("TERM").as_deref() == Ok("linux")).1;
        let clear = if std::env::var("TERM").as_deref() == Ok("linux") {
            "\x1b[2J\x1b[H"
        } else {
            ""
        };
        let _ = write!(io::stdout(), "\x1b[?1049l\x1b[?25h\x1b[0m{reset}{clear}");
        let _ = io::stdout().flush();
    }
}
impl Drop for Terminal {
    fn drop(&mut self) {
        self.restore();
    }
}

fn handoff() {
    println!("Dashboard closed. Monitoring and the night schedule keep running.");
    println!("Run dashboard to open it again.");
}
fn main() -> ExitCode {
    let terminal = match Terminal::save() {
        Ok(t) => t,
        Err(e) => {
            eprintln!("dashboard: {e}");
            return ExitCode::FAILURE;
        }
    };
    unsafe {
        let mut action: libc::sigaction = std::mem::zeroed();
        action.sa_sigaction = cancel as *const () as usize;
        libc::sigemptyset(&mut action.sa_mask);
        libc::sigaction(libc::SIGINT, &action, std::ptr::null_mut());
        libc::sigaction(libc::SIGTERM, &action, std::ptr::null_mut());
    }
    let renderer =
        std::env::var("DASHBOARD_RENDERER").unwrap_or_else(|_| "health-dashboard".into());
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        args = [
            "--catalog",
            "/etc/homelab/health-catalog.json",
            "--snapshot",
            "/run/homelab-health/snapshot.json",
            "--night",
            "/run/homelab-health/night.json",
        ]
        .map(String::from)
        .to_vec();
    }
    for attempt in 0..3 {
        let result = Command::new(&renderer)
            .args(&args)
            .env("DASHBOARD_LAUNCHER", "1")
            .status();
        terminal.restore();
        let deliberate = result
            .as_ref()
            .is_ok_and(|s| s.success() || s.signal() == Some(libc::SIGINT));
        if deliberate || CANCELLED.load(Ordering::Relaxed) {
            handoff();
            return ExitCode::SUCCESS;
        }
        if attempt == 2 {
            break;
        }
        println!(
            "Dashboard stopped unexpectedly. Retrying in {}s; Ctrl+C returns to the shell.",
            attempt + 1
        );
        let until = Instant::now() + Duration::from_secs(attempt + 1);
        while Instant::now() < until {
            if CANCELLED.load(Ordering::Relaxed) {
                handoff();
                return ExitCode::SUCCESS;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    }
    println!("Dashboard could not stay running. Monitoring and the night schedule keep running.");
    println!("Run dashboard to open it again.");
    ExitCode::FAILURE
}
