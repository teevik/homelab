//! Console-safe text. Live names and reasons come from outside the renderer, so they
//! are sanitised before they reach the terminal and fitted at word boundaries.

/// Glyphs the 256-glyph 16x32 Terminus font carries beyond printable ASCII, and that
/// the approved design uses.
pub const APPROVED_GLYPHS: [char; 13] = ['█', '▀', '▄', '░', '─', '│', '·', '■', '▲', '↑', '↓', '°', ' '];

pub fn is_supported(c: char) -> bool {
    c.is_ascii_graphic() || APPROVED_GLYPHS.contains(&c)
}

/// Replace anything the console font cannot show (and every control character,
/// including escape sequences) so that live text cannot reach the terminal raw.
pub fn sanitize(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            c if c.is_whitespace() => {
                if !out.ends_with(' ') {
                    out.push(' ');
                }
            }
            c if is_supported(c) => out.push(c),
            _ => out.push('?'),
        }
    }
    out.trim().to_string()
}

/// Ages: seconds under a minute, then minutes (hours past sixty). Recomputed on each
/// redraw, never by a per-second timer.
pub fn age(d: jiff::SignedDuration) -> String {
    let s = d.as_secs().max(0);
    if s < 60 {
        format!("{s}s")
    } else if s < 3600 {
        format!("{}m", s / 60)
    } else {
        format!("{}h {}m", s / 3600, s / 60 % 60)
    }
}

pub fn width(s: &str) -> usize {
    s.chars().count()
}

/// The longest prefix of `s` that ends on a word boundary and, with "...", fits in
/// `max` cells; `None` when not even the first word fits.
pub fn fit_words(s: &str, max: usize) -> Option<String> {
    if width(s) <= max {
        return Some(s.to_string());
    }
    let room = max.checked_sub(3)?;
    let mut cut = None;
    for (n, (i, c)) in s.char_indices().enumerate() {
        if n > room {
            break;
        }
        if c == ' ' || c == ',' {
            cut = Some(i);
        }
    }
    let head = s[..cut?].trim_end_matches([' ', ',']);
    (!head.is_empty()).then(|| format!("{head}..."))
}

/// Fit `s` in `max` cells at a word boundary. Only a first word that is itself too
/// long for `max` is cut inside the word, since there is nothing else to show.
pub fn fit(s: &str, max: usize) -> String {
    fit_words(s, max).unwrap_or_else(|| {
        if max < 4 {
            s.chars().take(max).collect()
        } else {
            format!("{}...", s.chars().take(max - 3).collect::<String>())
        }
    })
}
