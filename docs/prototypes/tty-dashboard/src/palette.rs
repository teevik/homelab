//! The proposed 16-slot console palette (NixOS `console.colors`, slot order 0-15),
//! drawn from Catppuccin Mocha to match the owner's desktop (teevik/Config).
//!
//! Background use is limited to slots 0-7: the Linux VT folds `48;5;n` for n >= 8 back
//! onto 0-7. Slots 1 and 4 are therefore spent on grounds, not on text colours.
//! Red is reserved for failures; heat uses yellow/peach so it never reads as a fault.

pub const GROUND: u8 = 0; // base
pub const ALERT_GROUND: u8 = 1; // red at 25% over base (derived, not a Mocha swatch)
pub const OK: u8 = 2; // green
pub const LABEL: u8 = 3; // lavender, the single structural accent (as in hyprlock)
pub const BAR: u8 = 4; // mantle, header/footer ground
pub const DEPLOY: u8 = 5; // overlay2, quiet deployment (Argo) state
pub const META: u8 = 6; // overlay1, ages and units
pub const BODY: u8 = 7; // subtext1
pub const RULE: u8 = 8; // surface1, rules and empty meter cells
pub const FAIL: u8 = 9; // red
pub const BRAND: u8 = 10; // maroon, Noctalia's primary
pub const WARM: u8 = 11; // yellow
pub const COOL: u8 = 12; // blue, normal instrument readings
pub const DEPLOY_HI: u8 = 13; // mauve, deployment problem
pub const HOT: u8 = 14; // peach
pub const TEXT: u8 = 15; // text

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

pub fn hex(i: usize) -> String {
    let [r, g, b] = PALETTE[i];
    format!("{r:02x}{g:02x}{b:02x}")
}

/// Escape sequences that load the palette into the running terminal, and restore it.
pub fn load_sequences(linux: bool) -> (String, String) {
    let mut set = String::new();
    for i in 0..16 {
        if linux {
            set.push_str(&format!("\x1b]P{i:x}{}", hex(i)));
        } else {
            let [r, g, b] = PALETTE[i];
            set.push_str(&format!("\x1b]4;{i};rgb:{r:02x}/{g:02x}/{b:02x}\x1b\\"));
        }
    }
    let reset = if linux { "\x1b]R".to_string() } else { "\x1b]104\x1b\\".to_string() };
    (set, reset)
}
