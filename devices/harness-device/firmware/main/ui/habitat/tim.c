#include "tim.h"
#include <stdio.h>
#include <string.h>

static bool due(uint32_t now, uint32_t deadline) { return (int32_t)(now - deadline) >= 0; }
static void deadline(ht_tim_motion_t *m, uint32_t now, uint32_t at)
{
    uint32_t left = due(now, at) ? 1 : at - now;
    if (left < m->next_ms) m->next_ms = left;
}
bool ht_tim_motion_tick(ht_tim_motion_t *m, uint32_t now, ht_tim_mood_t mood,
                        bool quiet, bool visible, bool down, int x, unsigned level, uint32_t activity)
{
    ht_tim_pose_t old = m->pose, p = {0};
    m->next_ms = 1000;
    if (!m->initialized) {
        m->initialized = true;
        m->next_blink = now + 5700;
        m->blink_until = m->reaction_until = m->release_until = now;
        m->mood = mood; m->activity = activity;
    }
    if (!visible || quiet || mood == HT_TIM_ASLEEP || mood == HT_TIM_OFFLINE) {
        m->next_blink = now + 5700;
        m->blink_until = m->reaction_until = m->release_until = now;
    } else {
        if ((activity != m->activity || mood != m->mood) &&
            (mood == HT_TIM_WORKING || mood == HT_TIM_DONE || mood == HT_TIM_ATTENTION)) {
            // Repeated tool packets cannot restart an endless busy animation.
            bool completed = mood == HT_TIM_DONE && m->mood != HT_TIM_DONE;
            if (completed || (due(now, m->reaction_until) && (!m->reaction_at || now - m->reaction_at >= 2000))) {
                m->reaction_at = now;
                m->reaction_until = now + (completed ? 1320 : 720);
            }
        }
        if (down) {
            int gaze = (x - 233) / 40;
            p.look = gaze < -2 ? -2 : gaze > 2 ? 2 : gaze;
            p.pressed = true;
            m->release_until = now + 400;
        } else if (m->was_down || !due(now, m->release_until)) {
            p.look = old.look;
            deadline(m, now, m->release_until);
        }
        if (!down && due(now, m->next_blink)) {
            m->blink_until = now + 110;
            m->sequence++;
            m->next_blink = now + 5700 + (m->sequence % 5) * 413;
        }
        p.blink = !down && !due(now, m->blink_until);
        if (!down) deadline(m, now, p.blink ? m->blink_until : m->next_blink);
        if (!due(now, m->reaction_until)) {
            p.hands = (uint8_t)(1 + (now - m->reaction_at) / 120 % 2);
            if (mood == HT_TIM_DONE && !down) {
                // A brief glance right, glance left, then a blink and smile.
                // The completion event owns this finite cue; repeated status
                // packets cannot sustain it, and touch always keeps its gaze.
                uint32_t age = now - m->reaction_at;
                p.look = age < 360 ? 2 : age < 720 ? -2 : 0;
                p.blink = age >= 840 && age < 960;
            }
            deadline(m, now, now + 120 - (now - m->reaction_at) % 120);
        }
        if (mood == HT_TIM_LISTENING) {
            p.level = old.level;
            if (m->mood != mood || now - m->level_at >= 125) {
                p.level = level > 4 ? 4 : (uint8_t)level;
                m->level_at = now;
            }
            deadline(m, now, m->level_at + 125);
        }
    }
    m->pose = p; m->mood = mood; m->activity = activity; m->was_down = down;
    return p.look != old.look || p.hands != old.hands || p.level != old.level ||
           p.blink != old.blink || p.pressed != old.pressed;
}
static void portrait(ht_scene_t *s, int y, ht_tim_mood_t mood, ht_tim_pose_t p, uint16_t ink, bool carrying)
{
    static const char eyes[] = {'o', 'o', '?', '^', 'x', '-', 'O', 'O'};
    static const char *mouth[] = {"\\_/", "---", " o ", "\\_/", "/-\\", " . ", " O ", " . "};
    static const char *levels[] = {" . ", " - ", " o ", " O ", "(O)"};
    static const char flags[] = {'*', '#', '!', '*', '!', '~', '*', '*'};
    if ((unsigned)mood > HT_TIM_LISTENING) mood = HT_TIM_CONTENT;
    char eye = p.blink ? '-' : p.pressed ? 'O' : eyes[mood];
    char left[6] = "     ", right[6] = "     ";
    int offset = 2 + (p.look < -2 ? -2 : p.look > 2 ? 2 : p.look);
    left[offset] = right[offset] = eye;
    char lhand = p.hands == 1 || mood == HT_TIM_DONE ? '\\' : '-';
    char rhand = p.hands == 2 || mood == HT_TIM_DONE ? '/' : '-';
    if (mood == HT_TIM_LISTENING || p.pressed) { lhand = '\\'; rhand = '/'; }
    char rows[6][24] = {"   ___________   ", "  |     |     |  ", "", "", "", "    /_\\   /_\\    "};
    snprintf(rows[2], sizeof(rows[2]), " %c|%s|%s|%c ", lhand, left, right, rhand);
    snprintf(rows[3], sizeof(rows[3]), "  |    %s    |  ", mood == HT_TIM_LISTENING ? levels[p.level > 4 ? 4 : p.level] : mouth[mood]);
    snprintf(rows[4], sizeof(rows[4]), "  |_[0]_tim%c__|  ", flags[mood]);
    if (carrying) snprintf(rows[4], sizeof(rows[4]), "  |_[=]_tim%c__|  ", flags[mood]);
    for (int i = 0; i < 6; i++) {
        if (i != 2) { ht_center(s, y + i * 28, &ht_mono_20, ink, rows[i]); continue; }
        // Independent eyes/arms keep a blink from repainting the space between them.
        static const int cells[] = {3, 5, 1, 5, 3};
        int cell = 0, x = (HT_WIDTH - 17 * ht_mono_20.width) / 2;
        for (int j = 0; j < 5; j++) {
            char part[6] = {0}; memcpy(part, rows[i] + cell, (size_t)cells[j]);
            ht_text(s, x + cell * ht_mono_20.width, y + i * 28, cells[j] * ht_mono_20.width,
                    &ht_mono_20, ink, s->background, part);
            cell += cells[j];
        }
    }
}
void ht_tim_portrait(ht_scene_t *s, int y, ht_tim_mood_t mood, uint16_t ink)
{
    portrait(s, y, mood, (ht_tim_pose_t){0}, ink, false);
}
static void lines(ht_scene_t *s, int y, int width, int count, const ht_font_t *font,
                  uint16_t ink, const char *text)
{
    if (!text) text = "";
    int start = s->count;
    ht_wrap(s, (HT_WIDTH - width) / 2, y, width, count, 0, font, ink, text);
    if (!ht_can_display(text, font, width, count) && s->count > start) {
        char *p = s->runs[s->count - 1].text;
        int keep = width / font->width - 3;
        for (int i = 0; *p && i < keep; i++) { const char *next = p; ht_utf8_next(&next); p = (char *)next; }
        strcpy(p, "...");
    }
    for (int i = start; i < s->count; i++) {
        ht_run_t *r = &s->runs[i]; const char *p = r->text; int n = 0;
        while (*p) { ht_utf8_next(&p); n++; }
        r->w = n * font->width; r->x = (HT_WIDTH - r->w) / 2;
    }
}
void ht_tim_face(ht_scene_t *s, const ht_tim_face_t *f)
{
    lines(s, 61, 300, 2, &ht_mono_20, f->foreground, f->recipient);
    if (f->focus) {
        char eye = f->pose.blink ? '-' : f->pose.pressed ? 'O' :
                   f->mood == HT_TIM_ATTENTION ? '?' : f->mood == HT_TIM_WORKING ? '=' :
                   f->mood == HT_TIM_ASLEEP ? '-' : f->mood == HT_TIM_OFFLINE ? 'x' : 'o';
        char mini[16]; snprintf(mini, sizeof(mini), "[ %c | %c ]", eye, eye);
        int x = (HT_WIDTH - 9 * ht_mono_20.width) / 2;
        for (int i = 0; i < 3; i++) {
            char part[4] = {0}; memcpy(part, mini + i * 3, 3);
            ht_text(s, x + i * 3 * ht_mono_20.width, 135, 3 * ht_mono_20.width,
                    &ht_mono_20, f->ink, s->background, part);
        }
        lines(s, 194, 340, 3, &ht_mono_28, f->foreground,
              f->detail && *f->detail ? f->detail : f->status);
    } else {
        portrait(s, 128, f->mood, f->pose, f->ink, f->carrying);
        lines(s, 310, 340, 1, &ht_mono_16, f->dim, f->detail);
    }
    lines(s, 349, 336, 1, &ht_mono_20, f->ink, f->status);
    lines(s, 395, 280, 1, &ht_mono_16, f->dim, f->hint);
}
