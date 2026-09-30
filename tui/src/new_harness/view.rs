//! Terminal rendering of the compact desktop form.
use super::*;
use unicode_segmentation::UnicodeSegmentation;

// Keep the recovery instruction readable, including long project names and wide glyphs.
fn error_lines(text: &str, width: usize) -> Vec<String> {
    let mut lines = Vec::new();
    let mut line = String::new();
    for word in text.split_whitespace() {
        if !line.is_empty() && line.width() + 1 + word.width() > width {
            lines.push(std::mem::take(&mut line));
        }
        if !line.is_empty() {
            line.push(' ');
        }
        for glyph in word.graphemes(true) {
            if !line.is_empty() && line.width() + glyph.width() > width {
                lines.push(std::mem::take(&mut line));
            }
            line.push_str(glyph);
        }
    }
    lines.push(line);
    lines
}

fn put(buf: &mut Buffer, x: u16, y: u16, width: u16, text: &str, style: Style) {
    if width == 0 {
        return;
    }
    let mut out = String::new();
    let mut used = 0;
    let limit = width as usize;
    let trunc = text.width() > limit;
    for ch in text.chars().filter(|c| !c.is_control()) {
        let w = ch.width().unwrap_or(0);
        if used + w > limit.saturating_sub(usize::from(trunc)) {
            break;
        }
        out.push(ch);
        used += w;
    }
    if trunc {
        out.push('…');
    }
    buf.set_stringn(x, y, out, width as usize, style);
}

/// The form's surface, as the settings panel draws its own: filled, no border.
fn panel(buf: &mut Buffer, r: Rect, base: Style) { crate::settings::fill(buf, r, base) }

pub fn draw(buf: &mut Buffer, body: Rect, form: &mut Form) -> Option<Position> {
    form.hits.clear();
    form.area = Rect::default();
    form.child_area = Rect::default();
    if body.width < 22 || body.height < 5 {
        put(
            buf,
            body.x,
            body.y,
            body.width,
            "New Harness · resize or Esc",
            Style::default(),
        );
        return None;
    }
    // The settings panel's colours, and its quiet backdrop over the working panes.
    let crate::settings::Chrome { base, muted, accent, backdrop, .. } = crate::settings::chrome();
    crate::settings::backdrop(buf, body, backdrop);
    // The form is the menus' panel: centred, the one size whatever is open — and a chooser (an
    // agent, a machine, a folder…) opens in its place, as a section of Appearance does, so
    // nothing moves.
    let side = false;
    let r = crate::settings::area(body);
    let (x, y, form_w, form_h) = (r.x, r.y, r.width, r.height);
    let (child_w, child_h) = (form_w, form_h);
    let fields = form.fields();
    let errors = error_lines(&form.error, form_w.saturating_sub(4) as usize);
    let error_h = errors.len().min(form_h.saturating_sub(4).max(1) as usize) as u16;
    form.area = r;
    if form.child.is_none() || side || !form.child_active {
        panel(buf, r, base);
        let fields_h = form_h - error_h + 1;
        let error_y = r.bottom() - 1 - error_h;
        let gap = if fields_h >= fields.len() as u16 * 2 + 3 {
            2
        } else {
            1
        };
        let capacity = ((fields_h.saturating_sub(5) / gap) + 1) as usize;
        let focus = fields.iter().position(|f| *f == form.focus).unwrap_or(0);
        let skip = focus.saturating_sub(capacity - 1);
        for (row, field) in fields.iter().skip(skip).take(capacity).enumerate() {
            let fy = r.y + if form_h < 5 { 0 } else { 2 } + row as u16 * gap;
            if fy >= error_y {
                break;
            }
            let active = *field == form.focus;
            let st = if form.blocked(*field).is_some() {
                muted
            } else if active {
                accent
            } else {
                base
            };
            let (label, value) = form.describe(*field);
            put(buf, r.x + 1, fy, 1, if active { "›" } else { " " }, accent);
            let label_w = if r.width < 45 { 10 } else { 12 };
            put(
                buf,
                r.x + 3,
                fy,
                label_w,
                label,
                if *field == Field::Create {
                    st.add_modifier(Modifier::BOLD)
                } else {
                    muted
                },
            );
            put(
                buf,
                r.x + 3 + label_w,
                fy,
                r.width.saturating_sub(6 + label_w),
                &value,
                st,
            );
            form.hits
                .push((Rect::new(r.x + 1, fy, r.width - 2, 1), *field));
        }
        for (row, line) in errors.iter().take(error_h as usize).enumerate() {
            put(buf, r.x + 2, error_y + row as u16, r.width - 4, line,
                base.patch(theme::fg(theme::DANGER)));
        }
    }
    if !side && !form.child_active {
        return None;
    }
    let Some(c) = &mut form.child else {
        return None;
    };
    let r = Rect::new(if side { x + form_w + 2 } else { x }, y, child_w, child_h);
    form.child_area = r;
    panel(buf, r, base);
    let query_x = r.x + 4;
    let query_y = r.y + 2;
    let query_w = r.width.saturating_sub(6) as usize;
    put(buf, r.x + 2, query_y, 1, "›", accent);
    let chars: Vec<_> = c.picker.query.chars().collect();
    let at = c.picker.qcursor.min(chars.len());
    let mut from = at;
    let mut width = 0;
    while from > 0 && width + chars[from - 1].width().unwrap_or(0) < query_w {
        from -= 1;
        width += chars[from].width().unwrap_or(0);
    }
    let query: String = chars[from..].iter().collect();
    put(
        buf,
        query_x,
        query_y,
        query_w as u16,
        if query.is_empty() {
            &c.picker.placeholder
        } else {
            &query
        },
        if query.is_empty() { muted } else { base },
    );
    c.picker.row_at.clear();
    if !c.kind.editing() {
        let rows = r.height.saturating_sub(6) as usize;
        c.picker.page_rows.set(rows as i64);
        c.picker.scroll = c
            .picker
            .scroll
            .min(c.picker.cursor)
            .max(c.picker.cursor.saturating_sub(rows.saturating_sub(1)));
        if c.picker.visible.is_empty() {
            put(
                buf,
                r.x + 3,
                r.y + 3,
                r.width - 6,
                c.picker.busy.as_deref().unwrap_or(&c.picker.empty),
                muted,
            );
        }
        let mut separator = 0;
        for (row, (index, _)) in c
            .picker
            .visible
            .iter()
            .enumerate()
            .skip(c.picker.scroll)
            .take(rows)
        {
            if c.kind == Choice::Project
                && c.picker.query.is_empty()
                && c.picker.rows[*index].id.starts_with("at:")
                && row > 0
                && !c.picker.rows[c.picker.visible[row - 1].0]
                    .id
                    .starts_with("at:")
            {
                separator = 1;
            }
            let at_y = r.y + 4 + (row - c.picker.scroll) as u16 + separator;
            if at_y >= r.bottom() - 2 {
                break;
            }
            let selected = row == c.picker.cursor;
            put(
                buf,
                r.x + 1,
                at_y,
                1,
                if selected { "›" } else { " " },
                accent,
            );
            put(
                buf,
                r.x + 3,
                at_y,
                r.width - 6,
                &c.picker.rows[*index].label,
                if c.picker.rows[*index].disabled {
                    muted
                } else if selected {
                    accent
                } else {
                    base
                },
            );
            c.picker.row_at.push((at_y, row));
        }
        let total = c.picker.visible.len();
        if total > rows && rows > 0 {
            let thumb = (rows * rows / total).max(1);
            let top = (rows - thumb) * c.picker.scroll / (total - rows);
            for dy in top..top + thumb {
                put(buf, r.right() - 2, r.y + 4 + dy as u16, 1, "│", muted);
            }
        }
    }
    let hint = if !form.error.is_empty() {
        &form.error
    } else {
        c.picker.busy.as_deref().unwrap_or("")
    };
    put(buf, r.x + 2, r.bottom() - 2, r.width - 4, hint, muted);
    form.child_active.then(|| {
        Position::new(
            query_x + (width as u16).min(r.width.saturating_sub(7)),
            query_y,
        )
    })
}
