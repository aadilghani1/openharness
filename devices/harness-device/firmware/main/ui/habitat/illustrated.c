#include "illustrated.h"
#include "../../../assets/companions/companion_art.h"
#include <string.h>

static void image(ht_scene_t *scene, int x, int y, const companion_asset_t *asset)
{
    if (scene->count >= HT_RUNS) return;
    ht_run_t *run = &scene->runs[scene->count++];
    memset(run, 0, sizeof *run);
    run->x = x + asset->x; run->y = y + asset->y; run->w = asset->width;
    run->sprite = (ht_sprite_t){.asset=asset, .revision=asset->offset+1,
        .width=asset->width, .height=asset->height};
}

bool ht_illustrated_tick(ht_character_motion_t *m, uint32_t now, ht_character_mood_t mood,
    bool quiet, bool visible, bool down, int x, unsigned level, uint32_t activity)
{
    if ((unsigned)mood >= HT_CHARACTER_MOODS) mood = HT_CHARACTER_IDLE;
    bool new_mood = !m->initialized || m->reaction.mood != mood;
    bool changed = ht_character_reaction_tick(&m->reaction, now, mood, quiet, visible,
                                             down, x, level, activity);
    unsigned step = mood == HT_CHARACTER_LISTENING ? 100 : companion_duration[mood];
    unsigned duration = step * (mood == HT_CHARACTER_LISTENING ? 4 : COMPANION_FRAMES);
    bool running = visible && !quiet && !down && mood != HT_CHARACTER_OFFLINE;
    bool finite = mood == HT_CHARACTER_DONE || mood == HT_CHARACTER_BOOPED;
    if (new_mood) m->phase = 0;
    else if (m->running && running) {
        uint32_t elapsed = now - m->last_ms;
        if (finite) m->phase = elapsed >= duration-1-m->phase ? duration-1 : m->phase+elapsed;
        else m->phase = (m->phase + elapsed % duration) % duration;
    }
    uint8_t previous = m->frame;
    m->frame = quiet || mood == HT_CHARACTER_OFFLINE ? 0 : m->phase / step;
    if (mood == HT_CHARACTER_LISTENING && !quiet) m->frame += m->reaction.pose.level * 4;
    m->initialized = true; m->running = running; m->last_ms = now;
    m->next_ms = m->reaction.next_ms;
    if (running && !(finite && m->phase == duration-1)) {
        uint32_t next = step - m->phase % step;
        if (next < m->next_ms) m->next_ms = next;
    }
    return changed || new_mood || m->frame != previous;
}

void ht_illustrated_draw(ht_scene_t *s, unsigned species, const ht_character_face_t *f,
    uint8_t frame, uint16_t ink, ht_character_size_t size, int y)
{
    (void)ink;
    if (species >= COMPANION_COUNT) return;
    unsigned small = size == HT_CHARACTER_BRIEF || size == HT_CHARACTER_READING || size == HT_CHARACTER_QUICK;
    unsigned mood = (unsigned)f->mood < HT_CHARACTER_MOODS ? f->mood : HT_CHARACTER_IDLE;
    // Expression order in the shared artwork adds blink after idle.
    unsigned expression = mood ? mood + 1 : 0;
    unsigned group = mood == HT_CHARACTER_WORKING ? 1 : mood == HT_CHARACTER_ATTENTION ? 2 :
        mood == HT_CHARACTER_DONE || mood == HT_CHARACTER_BOOPED ? 3 : 0;
    unsigned phase = (frame / 6) % 4, variant = 2;
    if (mood == HT_CHARACTER_LISTENING) { phase = frame % 4; variant = frame / 4; }
    else if ((mood == HT_CHARACTER_IDLE || mood == HT_CHARACTER_WORKING) && frame == 18) expression = 1;
    if (f->pose.pressed) {
        int gaze = f->pose.look + 2;
        variant = gaze < 0 ? 0 : gaze > 4 ? 4 : (unsigned)gaze;
        expression = 0; phase = 0;
    }
    if (variant > 4) variant = 4;
    int x = (HT_WIDTH - (small ? 108 : 240)) / 2;
    image(s, x, y, &companion_parts[small][species][group][phase][0]);
    image(s, x, y, &companion_bodies[small][species]);
    image(s, x, y, &companion_parts[small][species][group][phase][1]);
    image(s, x, y, &companion_faces[small][species][expression][variant]);
    if (f->pose.mail) image(s, x + companion_letter_anchor[small][species][0],
        y + companion_letter_anchor[small][species][1] - (f->pose.mail > 1 ? 4 : 0),
        &companion_letters[small]);
}
