//! The proposed 16-slot console palette (NixOS `console.colors`, slot order 0-15).
//!
//! Background use is limited to slots 0-7: the Linux VT folds `48;5;n` for n >= 8 back
//! onto 0-7. Slots 1 and 4 are therefore spent on dark grounds, not on text colours.

pub const SOOT: u8 = 0; // screen ground
pub const EMBER_GROUND: u8 = 1; // attention band ground
pub const LICHEN: u8 = 2; // ok, quiet
pub const BRASS: u8 = 3; // labels and structure
pub const RAISED: u8 = 4; // header/footer ground
pub const HEATHER: u8 = 5; // deployment (Argo) cue, quiet
pub const SLATE: u8 = 6; // metadata, ages, unknown
pub const PARCHMENT: u8 = 7; // body text
pub const ASH: u8 = 8; // rules, empty meter cells
pub const EMBER: u8 = 9; // failing
pub const LICHEN_HI: u8 = 10; // all clear
pub const AMBER: u8 = 11; // warm readings / heat
pub const MOON: u8 = 12; // night schedule note
pub const HEATHER_HI: u8 = 13; // deployment problem
pub const SLATE_HI: u8 = 14; // unknown, emphasised
pub const IVORY: u8 = 15; // primary values

pub const PALETTE: [[u8; 3]; 16] = [
    [0x13, 0x12, 0x0f],
    [0x4d, 0x22, 0x17],
    [0x9a, 0xac, 0x86],
    [0xc9, 0x96, 0x4f],
    [0x2a, 0x26, 0x20],
    [0x9d, 0x7d, 0x93],
    [0x71, 0x85, 0x8a],
    [0xc4, 0xba, 0xa2],
    [0x5a, 0x53, 0x47],
    [0xff, 0x8a, 0x5c],
    [0xc2, 0xd6, 0xa0],
    [0xf3, 0xbd, 0x62],
    [0x8e, 0xa3, 0xc4],
    [0xdb, 0xa6, 0xc9],
    [0xa6, 0xc1, 0xc2],
    [0xf1, 0xe7, 0xcd],
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
