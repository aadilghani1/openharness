//! The list behind every overlay (C-b s, the palette, machines, new harness…): a query line, rows
//! matched as fzf matches them (fzf.rs), a cursor that stays on the same ITEM when the rows are
//! rebuilt under it, and group headings in the unfiltered view.

use std::time::Instant;

use std::collections::HashMap;

use ratatui::text::Span;

pub struct Row {
    pub id: String,
    /// The part drawn bold and highlighted where the query matched.
    pub label: String,
    /// Everything else typing should match (label is included automatically).
    pub extra: String,
    pub group: Option<String>,
    /// Drawn before the label (state dot, engine mark).
    pub lead: Vec<Span<'static>>,
    /// Drawn after the label, dim.
    pub detail: Vec<Span<'static>>,
    /// Right-aligned.
    pub right: String,
    pub disabled: bool,
    /// Ranked above equal matches (live harnesses over paused ones).
    pub boost: u32,
    /// What of the line changes while you look (a harness's doing-now line; how long it has been
    /// as it is, at the right column's end): no query matches it, so a row does not come and go.
    pub volatile_detail: bool,
    pub volatile_right: usize,
    /// How many of the label's first characters are dim (a buffer's `name: N bytes: `): part of
    /// the line, matched and scrolled with it.
    pub label_dim: usize,
    /// The right column in a narrow list (under NARROW columns), so the line keeps its room.
    pub right_narrow: Option<String>,
    /// Its line comes before its right column wherever both don't fit (a question, a failure).
    pub line_first: bool,
}

/// A list narrower than this shows a row's narrow right column.
pub const NARROW: usize = 56;

impl Row {
    /// The right column at [text_w]: its narrow form in a narrow list — or wherever the whole of it
    /// would cut the row's line (a question at 80 columns keeps its words; the age stays).
    pub fn right_at(&self, text_w: usize) -> &str {
        let Some(narrow) = self.right_narrow.as_deref() else { return &self.right };
        if text_w < NARROW { return narrow }
        use unicode_width::UnicodeWidthStr;
        let line: usize = self.detail.iter().map(|s| s.content.width()).sum();
        let lead: usize = self.lead.iter().map(|s| s.content.width()).sum();
        if self.line_first && line > 0 && lead + self.label.width() + 2 + line + 2 + self.right.width() > text_w { narrow } else { &self.right }
    }
}

impl Row {
    pub fn new(id: impl Into<String>, label: impl Into<String>) -> Row {
        Row { id: id.into(), label: label.into(), extra: String::new(), group: None, lead: vec![], detail: vec![], right: String::new(), disabled: false, boost: 0, volatile_detail: false, volatile_right: 0, label_dim: 0, right_narrow: None, line_first: false }
    }
    pub fn extra(mut self, text: impl Into<String>) -> Row { self.extra = text.into(); self }
    pub fn group(mut self, text: impl Into<String>) -> Row { self.group = Some(text.into()); self }
    pub fn lead(mut self, spans: Vec<Span<'static>>) -> Row { self.lead = spans; self }
    pub fn detail(mut self, spans: Vec<Span<'static>>) -> Row { self.detail = spans; self }
    pub fn right(mut self, text: impl Into<String>) -> Row { self.right = text.into(); self }
    pub fn boost(mut self, by: u32) -> Row { self.boost = by; self }
    /// The parts of its line that change as you look: the detail, and the right column's last
    /// [right_tail] characters.
    pub fn volatile(mut self, detail: bool, right_tail: usize) -> Row { self.volatile_detail = detail; self.volatile_right = right_tail; self }
    pub fn label_dim(mut self, chars: usize) -> Row { self.label_dim = chars; self }
    pub fn right_narrow(mut self, text: impl Into<String>) -> Row { self.right_narrow = Some(text.into()); self }
    pub fn line_first(mut self, on: bool) -> Row { self.line_first = on; self }
}

pub struct Picker {
    /// Rows on screen, for PgUp/PgDn (a page is what you see).
    pub page_rows: std::cell::Cell<i64>,
    /// The width a row's text had when last drawn (0 before): a live list's query matches what a
    /// row shows at it (its right column only where there is room for it).
    pub text_w: usize,
    /// The kill buffer (C-w, M-BSpace, M-d), for C-y.
    pub kill: String,
    /// How far the preview can scroll, its lines and its height (the preview sets them as it
    /// draws): fzf's offset goes until the last line is at the top, a page is the window's height.
    pub preview_max: std::cell::Cell<u16>,
    pub preview_lines: std::cell::Cell<usize>,
    pub preview_rows: std::cell::Cell<u16>,
    pub title: String,
    /// Words that say what this list is for (a task about to be sent), at the head of the header
    /// line, as fzf's --header carries them.
    pub heading: Option<String>,
    pub placeholder: String,
    pub query: String,
    pub rows: Vec<Row>,
    /// (row index, label char indices matched)
    pub visible: Vec<(usize, Vec<u32>)>,
    pub cursor: usize,
    pub selected_id: Option<String>,
    pub status: String,
    pub hints: Vec<(&'static str, &'static str)>,
    pub keep_order: bool,
    pub busy: Option<String>,
    pub flash: Option<(String, Instant)>,
    /// An action on a working harness waiting for its key again (M-r, M-p): which, on which row, when.
    pub armed_key: Option<(char, String, Instant)>,
    pub empty: String,
    pub scroll: usize,
    /// Where the terminal cursor goes: the end of the query.
    /// The query starts with a mode character (`>` `@` `#` `:` `*` `?`) that is not part of the match.
    pub prefixed: bool,
    /// Screen row → visible index, from the last draw (for clicks).
    pub row_at: Vec<(u16, usize)>,
    /// A row whose action needs a second Enter (a big download).
    pub armed: Option<String>,
    /// The query's cursor, in chars (fzf edits the query like readline), and where a query wider
    /// than its line is shown from (fzf's xoffset).
    pub qcursor: usize,
    pub xoffset: std::cell::Cell<usize>,
    /// Rows marked with Tab (fzf --multi), by id, in the order marked.
    pub marked: Vec<String>,
    /// The preview window, and how far it is scrolled — for the row it shows: another row's
    /// preview starts at its top, as fzf runs the preview again.
    pub preview: bool,
    pub preview_scroll: std::cell::Cell<u16>,
    preview_of: Option<String>,
    /// A row's preview not drawn yet (it starts where --preview-window's +N or follow says), and
    /// whether it follows its end (follow, until scrolled up from it).
    pub preview_fresh: std::cell::Cell<bool>,
    pub preview_following: std::cell::Cell<bool>,
    /// fzf's --wrap, toggled by toggle-wrap (M-/): a long row goes on over the lines below it —
    /// and the columns it was last wrapped at (0 before it is drawn so), for the page keys.
    pub wrap: bool,
    pub wrap_width: std::cell::Cell<usize>,
    /// fzf's numLinesCache: a wrapped row's lines (with --gap's) by row, and the room they were
    /// counted in, for the width they were counted at — kept until the width, --wrap or the rows
    /// change, and trusted, as fzf trusts it, for any room at least as big.
    pub line_cache: std::cell::RefCell<(usize, HashMap<usize, (i64, usize)>)>,
    /// The list's scrollbar as last drawn — its column, the list's rows (top, bottom), whether
    /// they run top-down, the thumb's length and the lines a row averages — and whether the mouse
    /// is dragging it.
    pub bar: std::cell::Cell<Option<(u16, u16, u16, bool, usize, usize)>>,
    pub bar_drag: bool,
    /// The prompt's line and where the query starts on it, and the rows the list's box spans (from
    /// the last draw), for the mouse.
    pub prompt_at: std::cell::Cell<(u16, u16)>,
    pub box_rows: std::cell::Cell<(u16, u16)>,
    /// Where the list and the preview window are (from the last draw): what the mouse is over.
    pub list_area: std::cell::Cell<ratatui::layout::Rect>,
    /// The whole of the list's window on screen (its margin, padding and border included).
    pub screen_area: std::cell::Cell<ratatui::layout::Rect>,
    pub preview_area: std::cell::Cell<Option<(ratatui::layout::Rect, char)>>,
    /// A drag in the preview (it scrolls: the row and offset it began at), or on its border (it
    /// resizes), and the size it was given that way (columns, or rows above and below).
    pub preview_drag: Option<(u16, u16)>,
    /// The preview's scrollbar (the last draw's: its column, top row, height, the lines, the
    /// thumb's length), and whether the mouse is dragging it.
    pub preview_bar: std::cell::Cell<Option<(u16, u16, usize, usize, usize)>>,
    pub preview_bar_drag: bool,
    pub border_drag: bool,
    pub preview_cells: Option<i64>,
    /// change-preview-window and toggle-preview-wrap: the preview window as they left it (and
    /// which of change-preview-window's alternatives is next); toggle-sort: sorting turned over.
    pub preview_window: Option<crate::theme::PreviewWindow>,
    /// A list ranked by what changes under it (the harnesses, by urgency): a refresh re-ranks it,
    /// the cursor staying on its row (fzf's --track), and a query matches the rows' names (with
    /// their keywords), not the lines that change every few seconds.
    pub live: bool,
    /// Whether the --preview-window's <N(…) alternative is the one in use (the last draw's), which
    /// toggle-preview then shows or hides.
    pub preview_alt: std::cell::Cell<bool>,
    pub pw_next: usize,
    pub sort_flipped: bool,
    /// toggle-track: --track turned the other way.
    pub track_flipped: bool,
}

impl Picker {
    /// toggle-preview, show-preview, hide-preview (fzf's activePreviewOpts.Toggle): the preview
    /// window in use — --preview-window's, or its <N(…) alternative — shown or hidden, as asked
    /// (None: the other way). A preview that starts hidden is shown this way.
    pub fn show_preview(&mut self, show: Option<bool>) {
        let mut pw = self.preview_window.clone().unwrap_or_else(|| crate::theme::fzf_opts().preview_window.clone());
        let active: &mut crate::theme::PreviewWindow = match (self.preview_alt.get(), pw.alternative.as_deref_mut()) { (true, Some(a)) => a, _ => &mut pw };
        active.hidden = match show { Some(s) => !s, None => !active.hidden };
        self.preview_window = Some(pw);
        self.preview = true;
        // Shown again: from its +N, as fzf's preview starts.
        self.preview_scroll.set(0);
        self.preview_fresh.set(true);
    }

    pub fn new(title: impl Into<String>, placeholder: impl Into<String>) -> Picker {
        Picker {
            title: title.into(),
            heading: None,
            placeholder: placeholder.into(),
            query: String::new(),
            rows: Vec::new(),
            visible: Vec::new(),
            cursor: 0,
            selected_id: None,
            status: String::new(),
            hints: Vec::new(),
            keep_order: false,
            busy: None,
            flash: None, armed_key: None,
            empty: String::new(),
            scroll: 0,
            prefixed: false,
            row_at: Vec::new(),
            armed: None,
            qcursor: 0,
            xoffset: Default::default(),
            marked: Vec::new(),
            preview: true,
            preview_scroll: Default::default(),
            list_area: Default::default(),
            screen_area: Default::default(),
            preview_area: Default::default(),
            preview_drag: None,
            preview_bar: Default::default(),
            preview_bar_drag: false,
            border_drag: false,
            preview_cells: None,
            preview_window: None,
            live: false,
            preview_alt: Default::default(),
            pw_next: 0,
            sort_flipped: false,
            track_flipped: false,
            preview_of: None,
            preview_fresh: std::cell::Cell::new(true),
            preview_following: Default::default(),
            wrap: crate::theme::fzf_opts().wrap,
            wrap_width: Default::default(),
            line_cache: Default::default(),
            bar: Default::default(),
            bar_drag: false,
            prompt_at: Default::default(),
            box_rows: Default::default(),
            preview_max: Default::default(),
            preview_lines: Default::default(),
            preview_rows: Default::default(),
            kill: String::new(),
            page_rows: std::cell::Cell::new(10),
            text_w: 0,
        }
    }

    pub fn set_rows(&mut self, mut rows: Vec<Row>) {
        // fzf's list stands still while you are in it: a refresh keeps the rows where they were
        // and adds new ones after them.
        if !self.rows.is_empty() && !self.live {
            let old: HashMap<&str, usize> = self.rows.iter().enumerate().map(|(i, r)| (r.id.as_str(), i)).collect();
            rows.sort_by_key(|r| old.get(r.id.as_str()).copied().unwrap_or(usize::MAX));
        }
        self.rows = rows;
        self.line_cache.borrow_mut().1.clear();
        self.refilter();
    }

    /// toggle-wrap (M-/): fzf's clearNumLinesCache with it.
    pub fn toggle_wrap(&mut self) {
        self.wrap = !self.wrap;
        self.line_cache.borrow_mut().1.clear();
    }

    pub fn refilter(&mut self) {
        // The query as fzf's pattern reads it: leading blanks and trailing unescaped ones aside
        // (`pane\ ` keeps its escaped space).
        let mut query = self.query.as_str();
        if self.prefixed && scope_of(query).is_some() { query = &query.trim_start()[1..] }
        // fzf sorts only when a term asks for something (`!x` alone keeps the input order).
        let mut sorted = false;
        if query.trim().is_empty() {
            self.visible = self.rows.iter().enumerate().map(|(i, _)| (i, Vec::new())).collect();
        } else {
            // fzf itself (fzf.rs, ported from fzf 0.67): the extended-search terms, FuzzyMatchV2's
            // scores and lit characters, the tiebreak — over the line as it is drawn.
            let o = crate::theme::fzf_opts();
            let case = match o.case { Some(true) => crate::fzf::Case::Respect, Some(false) => crate::fzf::Case::Ignore, None => crate::fzf::Case::Smart };
            let q = crate::fzf::Query::parse(query, case, !o.exact, !o.literal).searching(&o.tiebreak).v1(o.algo_v1);
            // (Each word's case read as fzf reads a term's: +i, -i, or smart — an upper-case letter.)
            let words: Vec<(String, bool)> = query.split_whitespace().map(|w| {
                let w = w.trim_start_matches('\'');
                let sensitive = o.case.unwrap_or(w != w.to_lowercase());
                (if sensitive { w.to_string() } else { w.to_lowercase() }, sensitive)
            }).collect();
            // `!word` (and `!'word`): not only a row whose line says it, but one whose keywords do.
            let negated: Vec<(String, bool)> = words.iter().filter_map(|(w, s)| w.strip_prefix('!').map(|r| (r.trim_start_matches(['\'', '^']).trim_end_matches('$').to_string(), *s))).filter(|(w, _)| !w.is_empty()).collect();
            // …and in a live list, where the line's changing parts are left out of matching (so a
            // row does not come and go as they change), an unanchored `!word` still keeps out a row
            // whose line says it where you can see it.
            let unanchored: Vec<(String, bool)> = words.iter().filter_map(|(w, s)| w.strip_prefix('!').map(|r| (r.trim_start_matches('\'').to_string(), *s))).filter(|(w, _)| !w.is_empty() && !w.starts_with('^') && !w.ends_with('$')).collect();
            let words: Vec<(String, bool)> = words.into_iter().filter(|(w, _)| !w.starts_with('!')).collect();
            // The keywords by fzf's OR groups (`webapp | api`: either).
            let mut groups: Vec<Vec<(String, bool)>> = Vec::new();
            let mut or_next = false;
            for (w, s) in words {
                // (A `|` with nothing before it is a term of its own, as fzf reads it — one no
                // keyword answers.)
                if w == "|" && !groups.is_empty() { or_next = true; continue }
                // (An anchored term is about the line as drawn: no keyword answers it.)
                let w = if w.starts_with('^') || w.ends_with('$') { String::new() } else { w };
                match groups.last_mut() { Some(g) if or_next => g.push((w, s)), _ => groups.push(vec![(w, s)]) }
                or_next = false;
            }
            let live_tiebreak: Vec<crate::fzf::Tiebreak> = o.tiebreak.iter().copied().filter(|t| *t != crate::fzf::Tiebreak::Length).collect();
            let mut scored: Vec<(Vec<i64>, usize, Vec<u32>)> = Vec::new();
            let mut hidden: Vec<usize> = Vec::new();
            for (index, row) in self.rows.iter().enumerate() {
                if row.disabled { continue }
                let keywords = format!("{} {}", row.label, row.extra);
                if negated.iter().any(|(w, s)| w.chars().count() >= 3 && names_word(&keywords, w, *s)) { continue }
                let chars: Vec<char> = if self.live { steady_line(row, self.text_w) } else { line(row).chars().collect() };
                // (A keyword hit still has to keep out of what the query excludes from the line.)
                let seen = if negated.is_empty() { String::new() } else { line(row) };
                let clear = |w: &str, sensitive: bool| if sensitive { !seen.contains(w) } else { !seen.to_lowercase().contains(w) };
                let shown = self.live && !unanchored.is_empty() && unanchored.iter().any(|(w, sensitive)| { let l = line(row); if *sensitive { l.contains(w.as_str()) } else { l.to_lowercase().contains(w.as_str()) } });
                match q.matches(&chars) {
                    Some(_) if shown => {}
                    Some(hit) => {
                        // A live list's rows are its order (by urgency), as fzf's are over lines
                        // drawn to one width: length decides nothing between them.
                        let mut rank = crate::fzf::rank(&hit, &chars, if self.live { &live_tiebreak } else { &o.tiebreak });
                        // --tac: the input read bottom-up, ties too.
                        rank.push(if o.tac { -(index as i64) } else { index as i64 });
                        scored.push((rank, index, hit.positions.iter().map(|p| *p as u32).collect()));
                    }
                    // The keywords behind a row (engine, machine, branch): whole words of three
                    // letters or more find it, after everything that matched what you see.
                    None if !groups.is_empty() && groups.iter().all(|g| g.iter().any(|(w, sensitive)| (w.chars().count() >= 3 || STATE_WORDS.contains(&w.as_str())) && names_word(&keywords, w, *sensitive))) && negated.iter().all(|(w, s)| clear(w, *s)) => hidden.push(index),
                    None => {}
                }
            }
            sorted = !self.keep_order && q.sortable() && (o.no_sort == self.sort_flipped);
            if sorted { scored.sort_by(|a, b| a.0.cmp(&b.0)) }
            // Rows its keywords name (`codex`: the Codex harnesses) come before rows the query
            // found only as letters scattered through the line (c…o…d…e…x in `gpu-box`).
            let plain: Vec<String> = groups.iter().flatten().filter(|(w, _)| w.chars().count() >= 3).map(|(w, _)| w.to_lowercase()).collect();
            let scattered = |i: usize| !plain.is_empty() && !plain.iter().any(|w| line(&self.rows[i]).to_lowercase().contains(w.as_str()));
            let (weak, strong): (Vec<_>, Vec<_>) = if hidden.is_empty() { (Vec::new(), scored) } else { scored.into_iter().partition(|(_, i, _)| scattered(*i)) };
            self.visible = strong.into_iter().map(|(_, i, hits)| (i, hits)).chain(hidden.into_iter().map(|i| (i, Vec::new()))).chain(weak.into_iter().map(|(_, i, hits)| (i, hits))).collect();
        }
        // --tac: the input order reversed (wherever the order is the input's).
        if crate::theme::fzf_opts().tac && !sorted { self.visible.reverse() }
        // Keep the cursor on the same item across a rebuild.
        let keep = self.selected_id.as_ref().and_then(|id| self.visible.iter().position(|(i, _)| &self.rows[*i].id == id));
        self.cursor = keep.unwrap_or(self.cursor.min(self.visible.len().saturating_sub(1)));
        self.skip_disabled(1);
    }

    fn skip_disabled(&mut self, direction: i64) {
        if self.visible.is_empty() { self.selected_id = None; self.preview_of = None; return }
        let n = self.visible.len() as i64;
        for _ in 0..n {
            if !self.rows[self.visible[self.cursor].0].disabled { break }
            self.cursor = ((self.cursor as i64 + direction).rem_euclid(n)) as usize;
        }
        self.selected_id = Some(self.rows[self.visible[self.cursor].0].id.clone());
        if self.selected_id != self.preview_of { self.preview_scroll.set(0); self.preview_fresh.set(true); self.preview_of = self.selected_id.clone() }
    }

    /// fzf's scrollPreviewBy: from the first line until the last one is at the top.
    pub fn preview_by(&mut self, by: i64) { self.preview_to(self.preview_scroll.get() as i64 + by) }

    /// scrollPreviewTo: kept in range, and following again once back at the end.
    pub fn preview_to(&mut self, to: i64) {
        let at = to.clamp(0, self.preview_max.get() as i64);
        self.preview_scroll.set(at as u16);
        self.preview_following.set(at >= self.preview_lines.get() as i64 - self.preview_rows.get() as i64);
    }

    /// preview-page-*: the window's height; preview-half-page-*: half of it.
    pub fn preview_page(&mut self, pages: i64, half: bool) {
        let rows = self.preview_rows.get() as i64;
        self.preview_by(pages * if half { rows / 2 } else { rows })
    }

    /// preview-bottom: the last line at the bottom.
    pub fn preview_bottom(&mut self) {
        let bottom = self.preview_lines.get().saturating_sub(self.preview_rows.get() as usize) as i64;
        self.preview_to(bottom);
    }

    /// fzf's vset: the cursor to [to], kept in the list (no --cycle), off a disabled row.
    pub fn vset(&mut self, to: i64, direction: i64) {
        if self.visible.is_empty() { return }
        self.cursor = to.clamp(0, self.visible.len() as i64 - 1) as usize;
        self.skip_disabled(if direction >= 0 { 1 } else { -1 });
    }

    pub fn move_by(&mut self, delta: i64) {
        if self.visible.is_empty() { return }
        let max = self.visible.len() as i64 - 1;
        let to = self.cursor as i64 + delta;
        // --cycle: one step past an end comes round to the other.
        self.cursor = if crate::theme::fzf_opts().cycle && delta.abs() == 1 && (to < 0 || to > max) { to.rem_euclid(max + 1) } else { to.clamp(0, max) } as usize;
        self.skip_disabled(if delta >= 0 { 1 } else { -1 });
    }

    /// The query was edited: the list is matched again. As fzf 0.67 does, the cursor keeps its
    /// place in the list (not the item it was on), kept within it; an edit that leaves the query
    /// as it was changes nothing.
    fn changed(&mut self, before: &str) {
        if self.query == before { return }
        // --no-input: there is no query to edit.
        if crate::theme::fzf_opts().no_input { self.query = before.to_string(); self.qcursor = self.qcursor.min(self.qlen()); return }
        // --track (or toggle-track): the item it was on, wherever it goes.
        if !self.tracking() { self.selected_id = None }
        self.refilter();
    }

    /// --track, as toggle-track last left it.
    pub fn tracking(&self) -> bool { crate::theme::fzf_opts().track != self.track_flipped }

    fn byte_at(&self, chars: usize) -> usize { self.query.char_indices().nth(chars).map(|(i, _)| i).unwrap_or(self.query.len()) }

    /// Where editing starts: after the mode character (`>` `@` `#` `:` `*` `?`), which reads as
    /// part of the prompt — C-u, C-w, C-a and the arrows stop at it, as at fzf's prompt.
    fn floor(&self) -> usize { usize::from(self.prefixed && scope_of(&self.query).is_some()) }
    fn qlen(&self) -> usize { self.query.chars().count() }

    pub fn type_char(&mut self, c: char) {
        let before = self.query.clone();
        self.qcursor = self.qcursor.min(self.qlen());
        let at = self.byte_at(self.qcursor);
        self.query.insert(at, c);
        self.qcursor += 1;
        self.changed(&before);
    }

    /// Backspace (or, with [word], C-w / M-BS: the word before the cursor).
    /// Backspace; C-w (word: back to whitespace, as unix-word-rubout); what a word-kill takes goes
    /// to the kill buffer for C-y.
    pub fn backspace(&mut self, word: bool) {
        let before = self.query.clone();
        self.qcursor = self.qcursor.min(self.qlen());
        let floor = self.floor();
        // At the mode character: BSpace on an empty filter leaves the mode; anything else stops,
        // as at the start of fzf's query.
        if self.qcursor <= floor && !(floor == 1 && self.qcursor == 1 && !word && self.qlen() == 1) { return }
        let chars: Vec<char> = self.query.chars().collect();
        let mut from = self.qcursor - 1;
        if word {
            while from > floor && chars[from].is_whitespace() { from -= 1 }
            while from > floor && !chars[from - 1].is_whitespace() { from -= 1 }
            self.kill = chars[from..self.qcursor].iter().collect();
        }
        self.query = chars[..from].iter().chain(chars[self.qcursor..].iter()).collect();
        self.qcursor = from;
        self.changed(&before);
    }

    /// M-BSpace (back) and M-d (forward): kill an alphanumeric word, as readline and fzf do.
    pub fn kill_word(&mut self, forward: bool) {
        let before = self.query.clone();
        let chars: Vec<char> = self.query.chars().collect();
        let at = self.qcursor.min(chars.len());
        let to = word_edge(&chars, at, forward);
        let to = if forward { to } else { to.max(self.floor()) };
        let (a, b) = if forward { (at, to) } else { (to, at) };
        if a == b { return }
        self.kill = chars[a..b].iter().collect();
        self.query = chars[..a].iter().chain(chars[b..].iter()).collect();
        self.qcursor = a;
        self.changed(&before);
    }

    /// C-y: put back what was last killed.
    pub fn yank(&mut self) {
        let kill = self.kill.clone();
        for c in kill.chars() { self.type_char(c) }
    }

    /// Delete / C-d: the character under the cursor.
    pub fn delete_forward(&mut self) {
        let before = self.query.clone();
        let chars: Vec<char> = self.query.chars().collect();
        if self.qcursor >= chars.len() { return }
        self.query = chars[..self.qcursor].iter().chain(chars[self.qcursor + 1..].iter()).collect();
        self.changed(&before);
    }

    /// kill-line: from the cursor to the end, into the kill buffer (for C-y), as fzf's.
    pub fn kill_line(&mut self) {
        let before = self.query.clone();
        let chars: Vec<char> = self.query.chars().collect();
        let at = self.qcursor.min(chars.len());
        if at < chars.len() {
            self.kill = chars[at..].iter().collect();
            self.query = chars[..at].iter().collect();
        }
        self.changed(&before);
    }

    /// C-u: everything before the cursor (after the mode character).
    pub fn clear_query(&mut self) {
        let before = self.query.clone();
        let chars: Vec<char> = self.query.chars().collect();
        let (floor, at) = (self.floor(), self.qcursor.min(chars.len()));
        if at <= floor { return }
        self.kill = chars[floor..at].iter().collect();
        self.query = chars[..floor].iter().chain(chars[at..].iter()).collect();
        self.qcursor = floor;
        self.changed(&before);
    }

    /// Move the query cursor: by chars, or (word) to the previous / next word boundary.
    pub fn qmove(&mut self, by: i64, word: bool) {
        let chars: Vec<char> = self.query.chars().collect();
        let mut at = self.qcursor.min(chars.len()) as i64;
        if word { at = word_edge(&chars, at as usize, by > 0) as i64 } else { at = (at + by).clamp(0, chars.len() as i64) }
        self.qcursor = (at as usize).max(self.floor());
    }
    pub fn qhome(&mut self) { self.qcursor = self.floor() }
    pub fn qend(&mut self) { self.qcursor = self.qlen() }

    /// Tab: mark or unmark the row under the cursor (fzf --multi).
    /// The current row marked or not, the other way: false when nothing changed (--multi=N full).
    pub fn toggle_mark(&mut self) -> bool {
        let Some(id) = self.current_id() else { return false };
        if let Some(at) = self.marked.iter().position(|m| *m == id) { self.marked.remove(at); return true }
        if !self.room_to_mark() { return false }
        self.marked.push(id);
        true
    }

    /// --multi=N: whether another row may be marked (fzf's selectItem).
    pub fn room_to_mark(&self) -> bool { let n = crate::theme::fzf_opts().multi_limit; n == 0 || self.marked.len() < n }

    /// select / deselect: the current row marked, or not, whichever it was.
    pub fn set_mark(&mut self, on: bool) {
        let Some(id) = self.current_id() else { return };
        if self.marked.contains(&id) != on { self.toggle_mark(); }
    }

    /// next-selected / prev-selected: the cursor to the next (or previous) marked row, round.
    pub fn to_marked(&mut self, next: bool) {
        let n = self.visible.len();
        if n == 0 || self.marked.is_empty() { return }
        for i in 1..=n {
            let at = if next { (self.cursor + i) % n } else { (self.cursor + n - i % n) % n };
            if self.marked.contains(&self.rows[self.visible[at].0].id) { self.move_by(at as i64 - self.cursor as i64); return }
        }
    }

    #[cfg_attr(not(test), allow(dead_code))]
    /// Replace the query outright (a mode switch, a history recall).
    pub fn set_query(&mut self, text: &str) {
        let before = self.query.clone();
        self.query = text.to_string();
        self.qcursor = self.qlen();
        self.changed(&before);
    }

    pub fn current(&self) -> Option<&Row> {
        self.visible.get(self.cursor).map(|(i, _)| &self.rows[*i]).filter(|r| !r.disabled)
    }

    pub fn current_id(&self) -> Option<String> { self.current().map(|r| r.id.clone()) }

    /// Put the cursor on the row drawn at screen row [y]; false when there is none.
    pub fn click(&mut self, y: u16) -> bool {
        let Some((_, vi)) = self.row_at.iter().find(|(row, _)| *row == y).copied() else { return false };
        self.vset(vi as i64, 1);
        true
    }

    /// fzf's scrollbar dragging: the thumb's middle to the mouse's row, the offset from it, and the
    /// cursor moved as far as the offset did. False when the mouse is not on the bar's column.
    pub fn drag_bar(&mut self, x: u16, y: u16, start: bool) -> bool {
        let Some((bx, top, bottom, reverse, thumb, per_line)) = self.bar.get() else { return false };
        if start && (x != bx || y < top || y >= bottom) { return false }
        if thumb == 0 || self.visible.is_empty() { return true }
        let max_items = (bottom - top) as i64;
        let line = if reverse { y as i64 - top as i64 } else { bottom as i64 - 1 - y as i64 };
        let new_start = (line - thumb as i64 / 2).clamp(0, (max_items - thumb as i64).max(0));
        let total = self.visible.len() as i64;
        let denom = max_items * per_line as i64 - thumb as i64;
        if denom <= 0 { return true }
        let offset = ((new_start * (total * per_line as i64 - max_items)) as f64 / denom as f64).ceil() as i64;
        let prev = self.scroll as i64;
        self.scroll = offset.max(0) as usize;
        self.vset(offset + self.cursor as i64 - prev, 1);
        true
    }

    /// The preview's scrollbar pressed or dragged (fzf's pbarDragging): its thumb's middle under
    /// the mouse, the preview's offset following. False when [start] is not on the bar.
    pub fn drag_preview_bar(&mut self, x: u16, y: u16, start: bool) -> bool {
        let Some((bx, top, height, total, thumb)) = self.preview_bar.get() else { return false };
        if start && (x != bx || y < top || (y as usize) >= top as usize + height) { return false }
        if thumb == 0 || height <= thumb || total <= height { return true }
        let at = (y as i64 - top as i64 - thumb as i64 / 2).clamp(0, (height - thumb) as i64);
        let offset = ((at as f64) * (total - height) as f64 / (height - thumb) as f64).ceil() as i64;
        self.preview_to(offset);
        true
    }

    pub fn say(&mut self, text: impl Into<String>) { self.flash = Some((text.into(), Instant::now())) }
}

/// The length of the line a row shows (fzf's length tiebreak is the whole line's).
/// A row's line as it is drawn, and as fzf would read it: the title, then the detail and the right
/// column (two spaces before each that is there). Hit positions are places in this.
pub fn line(row: &Row) -> String {
    let detail: String = row.detail.iter().map(|s| s.content.as_ref()).collect();
    let mut out = row.label.clone();
    if !detail.is_empty() { out.push_str("  "); out.push_str(&detail) }
    if !row.right.is_empty() { out.push_str("  "); out.push_str(&row.right) }
    out
}

/// Where an alphanumeric word ends, going back or forward from `at` (readline's M-b / M-f).
fn word_edge(chars: &[char], mut at: usize, forward: bool) -> usize {
    let word = |c: char| c.is_alphanumeric();
    if forward {
        while at < chars.len() && !word(chars[at]) { at += 1 }
        while at < chars.len() && word(chars[at]) { at += 1 }
    } else {
        while at > 0 && !word(chars[at - 1]) { at -= 1 }
        while at > 0 && word(chars[at - 1]) { at -= 1 }
    }
    at
}

/// A launcher list's scope, from the query's first character (`>` commands, `@` machines, `#`
/// projects …) — `#` and a digit is a pull request's number (#4807), not the projects'.
pub fn scope_of(query: &str) -> Option<char> {
    let mut chars = query.trim_start().chars();
    let c = chars.next().filter(|c| ['>', '@', '#', ':', '*', '?'].contains(c))?;
    if c == '#' && chars.next().map(|d| d.is_ascii_digit()).unwrap_or(false) { return None }
    Some(c)
}

/// A live row's line as a query sees it: as drawn (picker::line), its changing parts blanked —
/// what it is doing now, how long it has been as it is — so hits light where the row shows them.
fn steady_line(row: &Row, text_w: usize) -> Vec<char> {
    const OUT: char = '\u{1}';
    // The right column as drawn (ui's fzf_row): whole, where there is room for it beside the line.
    use unicode_width::UnicodeWidthStr;
    let lead: usize = row.lead.iter().map(|s| s.content.width()).sum();
    let shown = text_w == 0 || (row.right_at(text_w) == row.right && text_w >= lead + row.right.width() + 14);
    let mut out: Vec<char> = row.label.chars().collect();
    let detail: String = row.detail.iter().map(|s| s.content.as_ref()).collect();
    if !detail.is_empty() { out.extend("  ".chars()); out.extend(detail.chars().map(|c| if row.volatile_detail { OUT } else { c })) }
    if !row.right.is_empty() {
        out.extend("  ".chars());
        let n = row.right.chars().count();
        out.extend(row.right.chars().enumerate().map(|(i, c)| if !shown || i + row.volatile_right >= n { OUT } else { c }));
    }
    out
}

/// The state words among a harness's keywords: found whole (`work` is not `working`).
const STATE_WORDS: [&str; 15] = ["waiting", "needs-you", "failed", "done", "finished", "working", "starting", "idle", "paused", "offline", "pr", "open", "merged", "closed", "draft"];

/// A hidden keyword this word names from its start (`codex`, `gpu-box`).
fn names_word(hidden: &str, word: &str, case_sensitive: bool) -> bool {
    let hidden = if case_sensitive { hidden.to_string() } else { hidden.to_lowercase() };
    // A keyword whole (a branch with its slash: feat/rate-limit), without its `#` (a pull request's
    // number: 4807), or each part of it (rate-limit); a state word only whole.
    hidden.split_whitespace().any(|w| if STATE_WORDS.contains(&w) { w == word } else {
        w.starts_with(word) || w.trim_start_matches('#').starts_with(word.trim_start_matches('#')) || w.split(['/', '·']).any(|p| p.starts_with(word))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A keyword behind a row (its engine) finds it, and `!keyword` leaves it out.
    #[test]
    fn negated_keywords_leave_rows_out() {
        let mut p = Picker::new("t", "");
        p.set_rows(vec![Row::new("a", "Add rate limiting").extra("codex studio"), Row::new("b", "Fix flaky test").extra("claude studio")]);
        let ids = |p: &Picker| p.visible.iter().map(|(i, _)| p.rows[*i].id.clone()).collect::<Vec<_>>();
        p.set_query("codex");
        assert_eq!(ids(&p), ["a"]);
        p.set_query("!codex");
        assert_eq!(ids(&p), ["b"]);
        p.set_query("studio !flaky");
        assert_eq!(ids(&p), ["a"]);
        // A branch with its slash, a pull request's number without its #.
        p.set_rows(vec![Row::new("a", "Add rate limiting").extra("api feat/rate-limit #4807 draft"), Row::new("b", "Fix flaky test").extra("webapp fix/login-flake")]);
        p.set_query("feat/rate-limit");
        assert_eq!(ids(&p), ["a"]);
        p.set_query("'4807");
        assert_eq!(ids(&p), ["a"]);
        p.set_query("login-flake");
        assert_eq!(ids(&p), ["b"]);
    }

    /// A live list (C-b s) finds what its rows show but what changes as you look: the question,
    /// the error, the finished turn, the pull request, lit where they are; keywords by OR groups;
    /// state words whole; `#4807` a pull request's number.
    #[test]
    fn live_rows_match_what_they_show() {
        let span = |t: &str| ratatui::text::Span::raw(t.to_string());
        let mut p = Picker::new("t", "");
        p.live = true;
        p.prefixed = true;
        p.set_rows(vec![
            Row::new("a", "Add rate limiting to the API").detail(vec![span("Rate limit per API key or per IP?")]).right("#4807 draft  2m").extra("api feat/rate-limit claude waiting").volatile(false, 2),
            Row::new("b", "Refactor billing service").detail(vec![span("Invoices now use Decimal")]).right("5m").extra("billing main codex done").volatile(false, 2),
            Row::new("c", "Fix flaky test").detail(vec![span("Running cargo test")]).right("1m").extra("webapp fix/login-flake claude working").volatile(true, 2),
        ]);
        let ids = |p: &Picker| p.visible.iter().map(|(i, _)| p.rows[*i].id.clone()).collect::<Vec<_>>();
        p.set_query("per IP");
        assert_eq!(ids(&p), ["a"]);
        p.set_query("Decimal");
        assert_eq!(ids(&p), ["b"]);
        // A hit in the right column is lit there.
        p.set_query("4807");
        assert_eq!(ids(&p), ["a"]);
        let at = "Add rate limiting to the API".chars().count() + 2 + "Rate limit per API key or per IP?".chars().count() + 2 + 1;
        assert!(p.visible[0].1.contains(&(at as u32)));
        p.set_query("#4807");
        assert_eq!(ids(&p), ["a"]);
        // What it is doing now is not searched (it changes as you look), nor how long.
        p.set_query("'cargo");
        assert!(ids(&p).is_empty());
        // State words whole: `work` is not `working`.
        p.set_query("'work");
        assert!(ids(&p).is_empty());
        p.set_query("working");
        assert_eq!(ids(&p), ["c"]);
        // OR groups over the keywords too.
        p.set_query("webapp | billing");
        assert_eq!(ids(&p).len(), 2);
    }

    #[test]
    fn fuzzy_and_sticky_cursor() {
        let mut p = Picker::new("t", "");
        p.set_rows(vec![Row::new("a", "landing page"), Row::new("b", "login flake"), Row::new("c", "docs")]);
        p.type_char('l');
        p.type_char('f');
        assert_eq!(p.current_id().as_deref(), Some("b"));
        p.set_rows(vec![Row::new("z", "zeta"), Row::new("b", "login flake")]);
        assert_eq!(p.current_id().as_deref(), Some("b"));
    }

    #[test]
    fn extended_search() {
        let mut p = Picker::new("t", "");
        p.set_rows(vec![Row::new("a", "landing page"), Row::new("b", "login flake"), Row::new("c", "docs site")]);
        let ids = |p: &Picker| { let mut v: Vec<String> = p.visible.iter().map(|(i, _)| p.rows[*i].id.clone()).collect(); v.sort(); v };
        p.set_query("docs | flake"); assert_eq!(ids(&p), ["b", "c"]);
        p.set_query("!docs"); assert_eq!(ids(&p), ["a", "b"]);
        p.set_query("^lo"); assert_eq!(ids(&p), ["b"]);
        p.set_query("page$"); assert_eq!(ids(&p), ["a"]);
        p.set_query("'site"); assert_eq!(ids(&p), ["c"]);
        p.set_rows(vec![Row::new("f", "Fix flaky login test").extra("webapp main"), Row::new("g", "fix it")]);
        p.set_query("^Fix"); assert_eq!(ids(&p), ["f"]);
        p.set_query("test$"); assert_eq!(ids(&p), ["f"]);
        p.set_query("main$"); assert!(ids(&p).is_empty());
        p.set_query("Fix\\ flaky"); assert_eq!(ids(&p), ["f"]);
        p.set_query("!^Fix"); assert_eq!(ids(&p), ["g"]);
    }
}

#[cfg(test)]
mod fzf_tests {
    use super::*;

    fn ids(p: &Picker) -> Vec<String> { p.visible.iter().map(|(i, _)| p.rows[*i].id.clone()).collect() }

    /// fzf 0.67's --filter keeps only "split pane below" for `pane\ ` (and `'pane\ `).
    #[test]
    fn a_trailing_escaped_space_stays() {
        let mut p = Picker::new("t", "");
        p.set_rows(["split pane below", "panes", "kill pane", "the pane", "pane"].iter().map(|l| Row::new(*l, *l)).collect());
        p.set_query("pane\\ ");
        assert_eq!(ids(&p), ["split pane below"]);
        p.set_query("'pane\\ ");
        assert_eq!(ids(&p), ["split pane below"]);
        p.set_query(" pane");
        assert_eq!(ids(&p).len(), 5);
    }

    /// fzf 0.67 (seen in tmux): Up five times, then C-u with nothing before the cursor, keeps the
    /// cursor; typing keeps its place in the new list (row 7 stays row 7), not the item.
    #[test]
    fn the_cursor_keeps_its_place_as_fzf_does() {
        let mut p = Picker::new("t", "");
        p.set_rows((1..=100).map(|n| Row::new(n.to_string(), n.to_string())).collect());
        p.move_by(6);
        assert_eq!(p.cursor, 6);
        p.clear_query();
        assert_eq!(p.cursor, 6);
        p.type_char('1');
        assert_eq!((p.cursor, p.current_id().as_deref()), (6, Some("15")));
        p.type_char('9');
        assert_eq!(p.cursor, 0, "one match left: the cursor kept within the list");
    }

    /// The words behind a row are read with each word's case as fzf reads a term's: smart case
    /// by default (an upper-case letter asks for that case), +i and -i when they are given.
    #[test]
    fn hidden_words_keep_their_case() {
        let mut p = Picker::new("t", "");
        p.set_rows(vec![Row::new("a", "landing page").extra("Codex"), Row::new("b", "docs").extra("codex")]);
        p.set_query("codex");
        assert_eq!(ids(&p), ["a", "b"]);
        p.set_query("Codex");
        assert_eq!(ids(&p), ["a"]);
    }
}

#[cfg(test)]
mod colon_tests {
    use super::*;
    #[test]
    fn matches_times() {
        let mut p = Picker::new("t", "");
        p.prefixed = true;
        p.set_rows(vec![Row::new("a", "Terminal harness 9-25 13:53")]);
        for c in "13:53".chars() { p.type_char(c) }
        assert_eq!(p.visible.len(), 1, "13:53");
    }
}

