//! Console-faithful PNG rendering of a Ratatui buffer.
//!
//! Emulates what Linux 6.18's VT + fbcon would show: 256-glyph PSF font looked up
//! through its Unicode table (or the kernel's default CP437 table for the built-in
//! font), foreground from palette slots 0-15, background only from slots 0-7
//! (crossterm emits `48;5;n`, which `rgb_background` folds to 3 bits). Anything the
//! real console could not show is reported instead of being drawn nicely.

use crate::palette::PALETTE;
use flate2::read::GzDecoder;
use ratatui::buffer::Buffer;
use ratatui::style::{Color, Modifier};
use std::collections::HashMap;
use std::io::Read;

pub struct Font {
    pub name: &'static str,
    pub w: usize,
    pub h: usize,
    /// glyph bitmaps, row-major, `(w + 7) / 8` bytes per row
    glyphs: Vec<Vec<u8>>,
    map: HashMap<char, usize>,
    scale: usize,
}

impl Font {
    pub fn cell(&self) -> (usize, usize) {
        (self.w * self.scale, self.h * self.scale)
    }

    fn lookup(&self, c: char) -> Option<usize> {
        self.map.get(&c).copied()
    }

    fn pixel(&self, g: usize, x: usize, y: usize) -> bool {
        let (x, y) = (x / self.scale, y / self.scale);
        let row = (self.w + 7) / 8;
        self.glyphs[g][y * row + x / 8] & (0x80 >> (x % 8)) != 0
    }
}

fn cp437_map() -> HashMap<char, usize> {
    let mut m = HashMap::new();
    for line in include_str!("../assets/cp437.uni").lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut parts = line.split_whitespace();
        let idx = usize::from_str_radix(parts.next().unwrap().trim_start_matches("0x"), 16).unwrap();
        for u in parts {
            let cp = u32::from_str_radix(u.trim_start_matches("U+"), 16).unwrap();
            m.entry(char::from_u32(cp).unwrap()).or_insert(idx);
        }
    }
    m
}

/// Kernel built-in TER16x32 (lib/fonts/font_ter16x32.c, Linux v6.18): what the laptop
/// shows today, because no `console.font` is configured.
pub fn builtin(scale: usize) -> Font {
    let data = include_bytes!("../assets/ter16x32.bin");
    let glyphs = data.chunks(64).map(|c| c.to_vec()).collect();
    Font {
        name: if scale == 1 { "kernel TER16x32" } else { "kernel TER16x32, doubled (32x64)" },
        w: 16,
        h: 32,
        glyphs,
        map: cp437_map(),
        scale,
    }
}

/// A gzipped PSF2 file with a Unicode table (Terminus 4.49 `ter-i24b`).
pub fn psf2(name: &'static str, gz: &[u8], scale: usize) -> Font {
    let mut d = Vec::new();
    GzDecoder::new(gz).read_to_end(&mut d).unwrap();
    let u = |o: usize| u32::from_le_bytes(d[o..o + 4].try_into().unwrap()) as usize;
    assert_eq!(&d[..4], &[0x72, 0xb5, 0x4a, 0x86]);
    let (hs, n, bpg, h, w) = (u(8), u(16), u(20), u(24), u(28));
    assert!(n <= 256, "a 512-glyph font halves the console's foreground colours");
    let glyphs = (0..n).map(|i| d[hs + i * bpg..hs + (i + 1) * bpg].to_vec()).collect();
    let mut map = HashMap::new();
    let mut off = hs + n * bpg;
    for g in 0..n {
        let start = off;
        while d[off] != 0xff {
            off += 1;
        }
        // entries are UTF-8 strings separated by 0xFE (sequence marker); take singles only
        for seq in d[start..off].split(|&b| b == 0xfe).take(1) {
            if let Ok(s) = std::str::from_utf8(seq) {
                for c in s.chars() {
                    map.entry(c).or_insert(g);
                }
            }
        }
        off += 1;
    }
    Font { name, w, h, glyphs, map, scale }
}

pub struct Report {
    pub missing: Vec<char>,
    pub bright_bg: usize,
    pub modifiers: usize,
}

fn index(c: Color, default: u8) -> u8 {
    match c {
        Color::Reset => default,
        Color::Indexed(n) if n < 16 => n,
        other => panic!("prototype must only use palette slots 0-15, got {other:?}"),
    }
}

pub fn render(buf: &Buffer, font: &Font, path: &str) -> Report {
    let (cw, ch) = font.cell();
    let area = buf.area;
    let (pw, ph) = (area.width as usize * cw, area.height as usize * ch);
    let mut px = vec![0u8; pw * ph * 3];
    let mut report = Report { missing: vec![], bright_bg: 0, modifiers: 0 };
    let fallback = font.lookup('\u{fffd}').or(font.lookup('?')).unwrap();
    for y in 0..area.height {
        for x in 0..area.width {
            let cell = &buf[(x, y)];
            let c = cell.symbol().chars().next().unwrap_or(' ');
            let g = match font.lookup(c) {
                Some(g) => g,
                None => {
                    if !report.missing.contains(&c) {
                        report.missing.push(c);
                    }
                    fallback
                }
            };
            if cell.modifier.intersects(Modifier::ITALIC | Modifier::UNDERLINED | Modifier::DIM | Modifier::REVERSED | Modifier::BOLD) {
                report.modifiers += 1;
            }
            let fg = index(cell.fg, 7);
            let mut bg = index(cell.bg, 0);
            if bg >= 8 {
                report.bright_bg += 1;
                bg -= 8;
            }
            let (f, b) = (PALETTE[fg as usize], PALETTE[bg as usize]);
            for py in 0..ch {
                for pxx in 0..cw {
                    let on = font.pixel(g, pxx, py);
                    let rgb = if on { f } else { b };
                    let o = ((y as usize * ch + py) * pw + x as usize * cw + pxx) * 3;
                    px[o..o + 3].copy_from_slice(&rgb);
                }
            }
        }
    }
    let file = std::fs::File::create(path).unwrap();
    let mut enc = png::Encoder::new(std::io::BufWriter::new(file), pw as u32, ph as u32);
    enc.set_color(png::ColorType::Rgb);
    enc.set_depth(png::BitDepth::Eight);
    enc.write_header().unwrap().write_image_data(&px).unwrap();
    report
}
