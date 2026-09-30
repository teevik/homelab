//! The dashboard's 16-slot role palette: Catppuccin Mocha swatches, scoped to the
//! dashboard's lifetime. It is loaded on entry and reset on exit; it must never be
//! installed as the global console palette, because slots 1 and 4 hold dark grounds.
//!
//! The Linux VT folds `48;5;n` for n >= 8 onto slots 0-7, so grounds use slots 0-7
//! only. Text attributes turn into colour changes on the VT, so none are used:
//! "dimmed" means drawn in overlay1 ([`META`]). Red means failing and nothing else;
//! heat uses blue, yellow and peach.

pub const GROUND: u8 = 0; // base: screen
pub const ALERT_GROUND: u8 = 1; // red at 25% over base (derived): attention band, failing rows
pub const OK: u8 = 2; // green: ok, ALL CLEAR
pub const LABEL: u8 = 3; // lavender: section labels
pub const BAR: u8 = 4; // mantle: header and footer
pub const DEPLOY: u8 = 5; // overlay2: quiet app state
pub const META: u8 = 6; // overlay1: metadata, retained ok values
pub const BODY: u8 = 7; // subtext1: body text
pub const RULE: u8 = 8; // surface1: rules, empty meter cells
pub const FAIL: u8 = 9; // red: failing, and only failing
pub const BRAND: u8 = 10; // maroon: the HOMELAB mark
pub const WARM: u8 = 11; // yellow: alerts, coverage gaps, UNKNOWN, warm readings
pub const COOL: u8 = 12; // blue: normal readings, night state
pub const DEPLOY_HI: u8 = 13; // mauve: deployment problems
pub const HOT: u8 = 14; // peach: hot readings
pub const TEXT: u8 = 15; // text: primary values

pub const PALETTE: [[u8; 3]; 16] = [
    [0x1e, 0x1e, 0x2e],
    [0x53, 0x39, 0x4c],
    [0xa6, 0xe3, 0xa1],
    [0xb4, 0xbe, 0xfe],
    [0x18, 0x18, 0x25],
    [0x93, 0x99, 0xb2],
    [0x7f, 0x84, 0x9c],
    [0xba, 0xc2, 0xde],
    [0x45, 0x47, 0x5a],
    [0xf3, 0x8b, 0xa8],
    [0xeb, 0xa0, 0xac],
    [0xf9, 0xe2, 0xaf],
    [0x89, 0xb4, 0xfa],
    [0xcb, 0xa6, 0xf7],
    [0xfa, 0xb3, 0x87],
    [0xcd, 0xd6, 0xf4],
];

/// Escape sequences that load the role palette, and that reset the terminal's own.
/// `linux` selects the Linux-console `ESC ] P nrrggbb` / `ESC ] R` pair; anything else
/// gets OSC 4 / OSC 104, for development in a graphical terminal.
pub fn sequences(linux: bool) -> (String, &'static str) {
    let mut load = String::new();
    for (i, [r, g, b]) in PALETTE.iter().enumerate() {
        if linux {
            load.push_str(&format!("\x1b]P{i:x}{r:02x}{g:02x}{b:02x}"));
        } else {
            load.push_str(&format!("\x1b]4;{i};rgb:{r:02x}/{g:02x}/{b:02x}\x1b\\"));
        }
    }
    (load, if linux { "\x1b]R" } else { "\x1b]104\x1b\\" })
}
