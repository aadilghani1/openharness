#include "focus.h"
#include "theme.h"
#include <stdio.h>
#include <string.h>

/*
 * THE FOCUS FACE — the agent screen, laid out like the octopus's (owner, 2026-10-01).
 *
 * The session's name curves along the top edge in the octopus's own arc (ht_arc_title, GeistMono 24);
 * the engine's mark stands where the octopus does, 56 px (focus_marks.c); under it the recap in a card
 * that always holds four lines of geist_med_28 — as many as the octopus reads — a shorter recap centred
 * in it. With no recap there is no card: the working line, or a resting line ("Let's build it", …),
 * is centred on the glass. In every state the mark stands halfway between the name and what is under
 * it, so the gap above it equals the gap below. There is no tab pill and no microphone: a tap anywhere
 * on the face talks to the agent, a hold opens the tabs, a tap on the name opens the panes
 * (ui_habitat.c).
 *
 * The fonts are the LVGL firmware's (assets/lvgl/SPEC.md), laid out by ht_lv_label — LVGL's own wrap,
 * centring and LONG_DOT.
 *
 * ── the rule that decides the SHAPE of this file ────────────────────────────────────────────────
 *
 * ht_damage() diffs run index against run index and repaints the whole 466x466 the moment the count
 * or the order changes (terminal.c). So the home face emits the SAME TEN RUNS IN THE SAME ORDER on
 * every frame — name, mark, card, recap ×4, status, resting line ×2 — each empty where it has
 * nothing to say. Do not make one conditional.
 */
// The card is the old Focus card (radius 28, padded 18 x 19) grown to four lines: 384 x 192 at
// (41, 179), ending at y 371, above the bell at 400; its rounded bottom corners stay inside r 230.
// TITLE_BOTTOM is the foot of the arc's cells at the top of the curve, where the mark is measured from.
enum { MARK_SIZE = 56, TITLE_BOTTOM = HT_ARC_Y + HT_ARC_CELL_HEIGHT, CARD_X = 41, CARD_Y = 179, CARD_W = 384, CARD_H = 192,
       CARD_R = 28, CARD_PAD_H = 18, CARD_PAD_V = 19, BODY_W = CARD_W - 2 * CARD_PAD_H - 2,
       RECAP_LINES = 4, EMPTY_W = 276 };
#define FOCUS_CARD     0x23252fu
#define FOCUS_CARD_RIM 0x3d3f47u   // #a6a6a6 at 20% over the card
#define FOCUS_FG      0xeaeaf0u
#define FOCUS_EMPTY   0x585863u
#define FOCUS_VOICE   0x00ff2fu

/*
 * WHAT AN AGENT WITH NOTHING YET SAYS, in place of "No activity yet" (owner, 2026-10-01): an
 * invitation rather than a report. One per agent, picked by its name, so the line does not change
 * every time the face is drawn but two agents side by side read differently. Each fits two lines of
 * geist_reg_38 at EMPTY_W.
 */
static const char *const RESTING[] = {
    "Let's build it", "Do anything", "What's next?", "Ready when you are",
    "Tap to talk", "Say the word", "Make it happen", "Start something",
};
static const char *resting_line(const char *name)
{
    uint32_t h = 2166136261u;   // FNV-1a
    for (const char *p = name ? name : ""; *p; p++) h = (h ^ (uint8_t)*p) * 16777619u;
    return RESTING[h % (sizeof RESTING / sizeof RESTING[0])];
}

/*
 * THE ENGINE'S OWN MARK.
 *
 * Order matches ENGINES in scripts/gen_habitat_fonts.py, which is what assigns the codepoints; the
 * two lists are one list in two files and must be changed together. `engine` is twelve bytes on the
 * wire (cable_client.c) and was stored and drawn nowhere until this face.
 *
 * An unknown engine gets no badge rather than a wrong one — a mark that means "some engine" teaches
 * a person to stop reading it.
 */
static const char *const ENGINES[] = {
    "claude", "codex", "cursor", "opencode", "grok", "copilot", "amp",
    "devin", "kilo", "pi", "hermes", "muse", "agy", "commandcode",
};

/*
 * And the colour it is drawn in — one per engine, in the order above.
 *
 * A badge is a single text cell, and ht_run_t.colors is per CELL, so a mark gets exactly one colour;
 * a two-tone logo (the Codex ring, the Antigravity gradient) is flattened to its dominant hue and
 * that is a real limit, not a choice. What IS a choice is which colour, and the old firmware's answer
 * is the one kept here: it recoloured Claude alone, to 0xcc7c5e, and let every other vendored asset
 * keep its own — which for ten of these fourteen meant white. Measured off those assets, only Codex,
 * Kilo, Muse and Antigravity ever carried a hue at all. Painting all fourteen in the accent, as the
 * first draft of this face did, made every engine look like the same lilac smudge and told a person
 * nothing; 0 here means "no colour of its own", and the mark is drawn in the row's ink.
 */
static const uint32_t ENGINE_INK[] = {
    0xcc7c5e, 0x7090f0, 0, 0, 0, 0, 0,
    0, 0xf0f070, 0, 0, 0x2d9bf0, 0x3080f0, 0,
};
_Static_assert(sizeof ENGINE_INK / sizeof ENGINE_INK[0] == sizeof ENGINES / sizeof ENGINES[0],
               "one ink per engine");

int ht_focus_engine_index(const char *engine)
{
    if (!engine || !*engine) return -1;
    for (unsigned i = 0; i < sizeof ENGINES / sizeof ENGINES[0]; i++)
        if (!strcmp(engine, ENGINES[i])) return (int)i;
    return -1;
}
_Static_assert(sizeof ht_icon_engine20 / sizeof ht_icon_engine20[0] == sizeof ENGINES / sizeof ENGINES[0],
               "one icon per engine");

bool ht_focus_engine_mark(const char *engine, char out[4], uint32_t *ink)
{
    if (!engine || !*engine) return false;
    for (unsigned i = 0; i < sizeof ENGINES / sizeof ENGINES[0]; i++) {
        if (strcmp(engine, ENGINES[i])) continue;
        uint32_t cp = HT_ENGINE_FIRST + i;
        *ink = ENGINE_INK[i];
        out[0] = (char)(0xe0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3f));
        out[2] = (char)(0x80 | (cp & 0x3f));
        out[3] = 0;
        return true;
    }
    return false;
}

/*
 * THE VOICE SCREEN: the waveform, or the three sparkles, and nothing else.
 *
 * The device drew it this way before habitat — a green meter on black while it listens, then three
 * marks while the words are on their way — and there is nothing else worth saying on a screen whose
 * whole job is to show that it is hearing you. So this branch emits the face's eight runs with the
 * other six empty, which is what keeps ht_damage() on its cheap path; see the note at the top.
 *
 * Nine bars from six heights, indexed by the 0..4 level that already reaches every skin through
 * pose.level. The shape is a hill: loud makes it taller, not wider.
 */
/*
 * THE RECORDING METER, as the old firmware drew it.
 *
 * Seven bars, six pixels wide, on a 22.4 px pitch about the screen's middle, resting at heights
 * 16/52/79/121/79/52/16 — the Figma measurements the deleted ui_screens.c carried — with a crest
 * travelling left to right. There it was seven LVGL rectangles whose heights an animation timer
 * drove every 40 ms; here each bar is one run of ht_wave, whose cell IS one bar in sixteen heights,
 * so the same picture costs seven runs and no allocation.
 *
 * The travelling wave is a table rather than a sine at runtime. The old tick advanced a phase 12°
 * every 40 ms and offset each bar by 40°, scaling its rest height between 0.35x and 1.0x; that is a
 * closed form over fifteen frames and seven bars, so it is evaluated once, by
 * scripts/gen_habitat_fonts.py's sibling arithmetic, and lives here as 105 bytes of level indices.
 * No trigonometry, no floating point, and the cycle is the old 1.2 s exactly — see
 * ht_focus_motion_tick for why fifteen frames at this duration land there.
 */
enum { WAVE_BARS = 7, WAVE_FRAMES = 15, WAVE_PITCH_X10 = 224 };
static const uint8_t WAVE[WAVE_FRAMES][WAVE_BARS] = {
    {  1,  6, 10, 14,  8,  3,  1 },
    {  1,  6, 10, 13,  6,  3,  0 },
    {  2,  6,  9, 11,  5,  2,  0 },
    {  2,  6,  8,  9,  4,  2,  1 },
    {  2,  6,  7,  7,  3,  2,  1 },
    {  2,  5,  5,  6,  3,  3,  1 },
    {  1,  4,  4,  5,  4,  4,  1 },
    {  1,  3,  3,  5,  5,  4,  2 },
    {  1,  2,  3,  6,  6,  5,  2 },
    {  1,  2,  4,  8,  7,  6,  2 },
    {  1,  2,  4, 10,  9,  6,  2 },
    {  0,  2,  6, 12,  9,  6,  1 },
    {  0,  3,  7, 14, 10,  6,  1 },
    {  1,  4,  8, 15,  9,  5,  1 },
    {  1,  5,  9, 15,  9,  4,  1 },
};

// One ht_wave codepoint as UTF-8. Sixteen levels, so this is never a multi-branch encoder.
static void wave_glyph(unsigned level, char out[4])
{
    uint32_t cp = HT_WAVE_FIRST + (level >= HT_WAVE_LEVELS ? HT_WAVE_LEVELS - 1 : level);
    out[0] = (char)(0xe0 | (cp >> 12));
    out[1] = (char)(0x80 | ((cp >> 6) & 0x3f));
    out[2] = (char)(0x80 | (cp & 0x3f));
    out[3] = 0;
}

static void voice_face(ht_scene_t *s, const ht_character_face_t *f, uint8_t frame)
{
    bool listening = f->mood == HT_CHARACTER_LISTENING;

    /*
     * TEN RUNS, ALWAYS, IN THIS ORDER — seven bars then three sparkles — whichever half is showing.
     *
     * ht_damage() diffs run index against run index and repaints all 466x466 the moment the count or
     * the order moves, so the half that is idle is emitted empty rather than skipped. Recording and
     * sending are then a change of text and colour, not a reshape, and the damage is the cells that
     * actually moved.
     */
    int mid_y = (HT_HEIGHT - ht_wave.height) / 2;
    uint16_t voice = ht_rgb(HT_THEME_VOICE);
    for (int k = 0; k < WAVE_BARS; k++) {
        char bar[4] = {0};
        if (listening) wave_glyph(WAVE[frame % WAVE_FRAMES][k], bar);
        int x = HT_WIDTH / 2 + (k - WAVE_BARS / 2) * WAVE_PITCH_X10 / 10 - ht_wave.width / 2;
        ht_text(s, x, mid_y, ht_wave.width, &ht_wave, voice, s->background, bar);
    }

    /*
     * And the sending sweep: three filled sparkles on a 66 px pitch, the lit one travelling across
     * them. That pitch and that artwork are the old screen's; what is gone is its 1.3x pop on the
     * lit mark, because a glyph has one size and scaling it would mean a second atlas for a state
     * that already reads from the colour alone. White idle, the meter's own green lit.
     */
    int spark_y = (HT_HEIGHT - ht_spark.height) / 2;
    int lit = (frame % WAVE_FRAMES) / 5;      // three steps, 200 ms each, per the old busy sweep
    for (int i = 0; i < 3; i++)
        ht_text(s, HT_WIDTH / 2 + (i - 1) * 66 - ht_spark.width / 2, spark_y,
                ht_spark.width, &ht_spark,
                listening ? s->background : i == lit ? voice : f->foreground, s->background,
                listening ? "" : HT_SPARK);

}

/*
 * The microphone level, in one run.
 *
 * Nine cells, indexed by the 0..4 level that already reaches every skin through pose.level (fed from
 * audio_client_input_level()). Deliberately NOT a background-filled bar whose width tracks the
 * level: a run whose `w` changes every frame trips the reshape path in ht_damage() and forfeits
 * banded damage for the entire scene. A fixed-width string changes only its cells.
 */
static const char *meter(unsigned level)
{
    // Nine cells that grow outward from the middle. A mono cell has one height, so this is a shape
    // that widens rather than a waveform that rises — the honest version of the old face's bars.
    static const char *const bars[5] = {
        "    -    ", "   -|-   ", "  -|I|-  ", " -|III|- ", "-|IIIII|-"
    };
    return bars[level > 4 ? 4 : level];
}

// Placeholders that keep the run count constant: an invisible box and an empty text run.
static void no_box(ht_scene_t *s) { ht_box(s, 0, 0, 1, 1, 0, s->background, s->background); }
static void no_text(ht_scene_t *s, const ht_font_t *font)
{
    ht_text(s, 0, 0, 1, font, s->background, s->background, "");
}
/*
 * A laid-out label's lines as runs, `runs` of them always: line n at (x + its centring, y + n *
 * pitch). The line's bytes are the label's own, trailing space and all, because LVGL centred on them.
 */
static void label_runs(ht_scene_t *s, const ht_lv_label_t *l, int runs, int x, int y, int pitch,
                       const ht_font_t *font, uint16_t ink, uint16_t bg)
{
    for (int n = 0; n < runs; n++) {
        if (n >= l->lines || !l->line[n].len) { no_text(s, font); continue; }
        const ht_lv_line_t *ln = &l->line[n];
        char text[HT_TEXT_BYTES];
        size_t len = ln->len < sizeof text ? ln->len : sizeof text - 1;
        memcpy(text, l->text + ln->at, len);
        while (len && (text[len - 1] == '\n' || text[len - 1] == '\r')) len--;
        text[len] = 0;
        ht_text(s, x + ln->x, y + n * pitch, ln->w > 0 ? ln->w : 1, font, ink, bg, text);
    }
}

// "34s", then "1m 05s" — the old firmware's fmt_elapsed.
static void elapsed_text(char *out, size_t cap, unsigned sec)
{
    if (sec < 60) snprintf(out, cap, "%us", sec);
    else snprintf(out, cap, "%um %02us", sec / 60, sec % 60);
}

/*
 * THE WORKING LINE. The verb is the engine's own when the cable carried one; "Working" — the
 * placeholder render_home() uses when it did not — becomes the old firmware's rotating gerund,
 * one every six seconds, so a long turn does not read as stuck on a word.
 */
static const char *const GERUNDS[] = {
    "Working", "Brewing", "Cooking", "Churning", "Frosting", "Simmering", "Tinkering",
    "Conjuring", "Composing", "Percolating", "Wrangling", "Hatching", "Concocting", "Puttering",
};
static void status_text(char *out, size_t cap, const ht_character_face_t *f)
{
    const char *verb = f->activity;
    if (!strcmp(verb, "Working"))
        verb = GERUNDS[(f->elapsed / 6) % (sizeof GERUNDS / sizeof GERUNDS[0])];
    if (!f->elapsed) { snprintf(out, cap, "%s\xe2\x80\xa6", verb); return; }
    char when[16];
    elapsed_text(when, sizeof when, f->elapsed);
    snprintf(out, cap, "%s\xe2\x80\xa6 %s", verb, when);
}

/*
 * The recap as the face reads it: cut to the octopus's ninety codepoints, then a glyph at a time until
 * it fits four lines with its "…" — measured, since ninety short words can still need five.
 */
static void recap_cut(char *out, size_t cap, const char *recap, const ht_font_t *font, int width)
{
    size_t n = 0, glyphs = 0;
    while (recap[n] && glyphs < HT_CHARACTER_RECAP_CHARS) {
        size_t k = n + 1;
        while (recap[k] && ((uint8_t)recap[k] & 0xc0) == 0x80) k++;
        if (k + 4 > cap) break;
        n = k;
        glyphs++;
    }
    bool clipped = recap[n] != 0;
    memcpy(out, recap, n);
    out[n] = 0;
    ht_lv_label_t l;
    for (;;) {
        char probe[HT_TEXT_BYTES + 4];
        snprintf(probe, sizeof probe, "%s%s", out, clipped ? "\xe2\x80\xa6" : "");
        if (ht_lv_label(&l, font, probe, width, RECAP_LINES, false) <= RECAP_LINES || !out[0]) break;
        size_t k = strlen(out);
        do k--; while (k > 0 && ((uint8_t)out[k] & 0xc0) == 0x80);
        while (k > 0 && out[k - 1] == ' ') k--;
        out[k] = 0;
        clipped = true;
    }
    if (clipped) strcat(out, "\xe2\x80\xa6");
}

void ht_focus_face(ht_scene_t *s, const ht_character_face_t *f, uint8_t frame, uint16_t ink,
                   const char *recap)
{
    (void)ink;
    if (f->voice) { voice_face(s, f, frame); return; }
    bool has_recap = recap && *recap;
    bool working = !has_recap && f->activity && *f->activity;
    bool retry = !has_recap && !working && f->status && *f->status;

    // The live line: listening meter, the working verb and its seconds, or a status of its own.
    const ht_font_t *sf = &ht_lv_geist_med_32.base, *ef = &ht_lv_geist_reg_38.base,
                    *rf = &ht_lv_geist_med_28.base;
    char status[HT_TEXT_BYTES] = "";
    if (!has_recap && f->mood == HT_CHARACTER_LISTENING) snprintf(status, sizeof status, "%s", meter(f->pose.level));
    else if (working) status_text(status, sizeof status, f);
    else if (retry) snprintf(status, sizeof status, "%s", f->status);
    bool empty = !has_recap && !status[0];

    // The body, laid out first: a recap is centred in its card; without one the line is centred on
    // the glass.
    ht_lv_label_t body;
    int body_h = 0;
    if (has_recap) {
        char cut[HT_TEXT_BYTES];
        recap_cut(cut, sizeof cut, recap, rf, BODY_W);
        int n = ht_lv_label(&body, rf, cut, BODY_W, RECAP_LINES, false);
        body_h = (n < RECAP_LINES ? n : RECAP_LINES) * rf->height;
    } else if (status[0]) {
        ht_lv_label(&body, sf, status, CARD_W, 1, true);   // no card around it: the full width
        body_h = sf->height;
    } else {
        int n = ht_lv_label(&body, ef, resting_line(f->recipient), EMPTY_W, 2, false);
        body_h = (n < 2 ? n : 2) * ef->height;
    }
    int body_y = has_recap ? CARD_Y + (CARD_H - body_h) / 2 : HT_HEIGHT / 2 - body_h / 2;
    // The mark halfway between the name and the card, or the line: equal gaps above and below.
    int below = has_recap ? CARD_Y : body_y;
    int mark_top = TITLE_BOTTOM + (below - TITLE_BOTTOM - MARK_SIZE) / 2;

    // The name on the top curve, the octopus's arc; a tap there opens the pane list.
    ht_arc_title(s, ht_rgb(FOCUS_FG), f->recipient && *f->recipient ? f->recipient : "\xe2\x80\xa6");

    // The engine's mark, where the octopus stands. An unknown engine leaves the place empty.
    int engine = ht_focus_engine_index(f->engine);
    int mark_x = (HT_WIDTH - MARK_SIZE) / 2;
    if (engine >= 0) ht_icon(s, mark_x, mark_top, &ht_icon_engine56[engine]);
    else no_text(s, rf);

    // The card only holds a recap; its lines are drawn on its fill.
    uint16_t card = ht_rgb(FOCUS_CARD);
    if (has_recap) ht_box(s, CARD_X, CARD_Y, CARD_W, CARD_H, CARD_R, card, ht_rgb(FOCUS_CARD_RIM));
    else no_box(s);

    if (has_recap) label_runs(s, &body, RECAP_LINES, (HT_WIDTH - BODY_W) / 2, body_y, rf->height, rf,
                              ht_rgb(FOCUS_FG), card);
    else for (int n = 0; n < RECAP_LINES; n++) no_text(s, rf);

    if (status[0])
        label_runs(s, &body, 1, CARD_X, body_y, 0, sf,
                   ht_rgb(retry ? FOCUS_FG : FOCUS_VOICE), s->background);
    else no_text(s, sf);

    // Nothing yet: said in the resting grey.
    if (empty) label_runs(s, &body, 2, (HT_WIDTH - EMPTY_W) / 2, body_y, ef->height, ef,
                          ht_rgb(FOCUS_EMPTY), s->background);
    else { no_text(s, ef); no_text(s, ef); }
}

void ht_focus_portrait(ht_scene_t *s, const ht_character_face_t *f, uint8_t frame, uint16_t ink,
                       ht_character_size_t size, int y)
{
    (void)frame;
    (void)size;
    const char *name = f->recipient ? f->recipient : "";
    ht_center(s, y, &ht_mono_28, ink, name);
}

bool ht_focus_motion_tick(ht_character_motion_t *m, uint32_t now, ht_character_mood_t mood,
                          bool quiet, bool visible, bool down, int x, unsigned level,
                          uint32_t activity)
{
    /*
     * Fifteen frames, and only the voice screen spends them.
     *
     * Nothing on the home face moves — a skin whose subject is the work should not fidget. These are
     * the recording meter and the sending sweep, both of which the old firmware animated, and the
     * duration is picked so each lands on the cadence it had there.
     *
     * ht_character_motion_step halves the rate while the mood is LISTENING or IDLE, which is exactly
     * the mood ui_habitat.c reports while the microphone is open. So 600 ms of phase over fifteen
     * frames is 40 ms a frame recording — the old wave_tick's timer period, 1.2 s for a full
     * travelling cycle — and 20 ms a frame sending, where the sweep steps every fifth frame and so
     * holds each sparkle for the same 200 ms the old busy sweep did.
     *
     * `ends` are cumulative marks in that phase, not frame numbers. An earlier version listed
     * 1..6 against a 900 ms duration, which put every frame boundary inside the first six
     * milliseconds and left the animation parked on its last frame for the rest of the cycle —
     * a screen that looked as dead as the `frames = 1` it replaced.
     */
    static const uint16_t ends[] = { 40, 80, 120, 160, 200, 240, 280, 320,
                                     360, 400, 440, 480, 520, 560, 600 };
    static const ht_character_animation_t sweep = { 15, 600, ends };
    return ht_character_motion_step(m, &sweep, now, mood, quiet, visible, down, x, level,
                                    activity, true);
}
