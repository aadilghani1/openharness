// The public character contract: reaction state, every mood/size, swapping, and
// DMA damage replay. Uses the same immutable assets and renderer as the board.
#include "../main/ui/habitat/character.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint16_t full[HT_WIDTH * HT_HEIGHT], partial[HT_WIDTH * HT_HEIGHT];
static uint16_t scratch[HT_WIDTH * HT_HEIGHT];
static unsigned redraws;

static void redraw(const ht_scene_t *before, const ht_scene_t *after)
{
    ht_damage_t d; ht_damage(before, after, &d);
    for (unsigned i = 0; i < d.count; i++) {
        ht_rect_t r = d.rect[i];
        assert(r.x >= 0 && r.y >= 0 && r.x + r.w <= HT_WIDTH && r.y + r.h <= HT_HEIGHT);
        assert(!((r.x | r.y | r.w | r.h) & 1));
        ht_raster(after, r, scratch);
        for (int y = 0; y < r.h; y++)
            memcpy(partial + (r.y + y) * HT_WIDTH + r.x, scratch + y * r.w, r.w * 2);
    }
    ht_raster(after, (ht_rect_t){0, 0, HT_WIDTH, HT_HEIGHT}, full);
    assert(!memcmp(full, partial, sizeof full));
    redraws++;
}

static void tick(ht_character_t *c, uint32_t now, ht_character_mood_t mood,
                 bool quiet, bool visible, bool down, unsigned level)
{
    ht_character_tick(c, now, mood, quiet, visible, down, 330, level, now / 100);
    assert(c->motion.next_ms >= 1 && c->motion.next_ms <= 1000);
    assert(c->motion.frame < c->motion.animation->frames);
}

static void clocks(void)
{
    for (int id = 0; id < HT_CHARACTER_COUNT; id++) {
        ht_character_t c = {0}; assert(ht_character_select(&c, id));
        tick(&c, UINT32_MAX - 49, HT_CHARACTER_WORKING, false, true, false, 0);
        tick(&c, 50, HT_CHARACTER_WORKING, false, true, false, 0);
        assert(c.motion.phase == 100);
        tick(&c, 80, HT_CHARACTER_WORKING, false, true, true, 0);
        uint16_t held = c.motion.phase;
        tick(&c, 3000, HT_CHARACTER_WORKING, false, true, true, 0);
        assert(c.motion.phase == held && c.motion.reaction.pose.pressed && c.motion.reaction.pose.look == 2);
        tick(&c, 4000, HT_CHARACTER_WORKING, false, true, false, 0);
        assert(c.motion.phase == held); // No backlog on release.
        tick(&c, 4100, HT_CHARACTER_LISTENING, false, true, false, 99);
        assert(c.motion.reaction.pose.level == 4);
        held = c.motion.phase;
        for (uint32_t t = 4101; t < 4225; t++) {
            tick(&c, t, HT_CHARACTER_LISTENING, false, true, false, 0);
            assert(c.motion.reaction.pose.level == 4 && c.motion.phase == held);
        }
        tick(&c, 4225, HT_CHARACTER_LISTENING, false, true, false, 0);
        assert(!c.motion.reaction.pose.level && c.motion.phase == held);
        for (int state = 0; state < 4; state++) {
            ht_character_mood_t mood = state == 2 ? HT_CHARACTER_ASLEEP :
                state == 3 ? HT_CHARACTER_OFFLINE : HT_CHARACTER_WORKING;
            tick(&c, 5000, mood, state == 0, state != 1, false, 0);
            held = c.motion.phase;
            for (uint32_t t = 5001; t < 5100; t++) {
                tick(&c, t, mood, state == 0, state != 1, false, 0);
                assert(c.motion.phase == held && c.motion.next_ms == 1000);
            }
        }
        // A full idle cycle runs at half speed for either character.
        memset(&c.motion, 0, sizeof c.motion);
        tick(&c, 0, HT_CHARACTER_IDLE, false, true, false, 0);
        unsigned duration = c.motion.animation->duration;
        bool seen[256] = {0};
        for (unsigned t = 0; t <= duration * 2; t++) {
            tick(&c, t, HT_CHARACTER_IDLE, false, true, false, 0);
            seen[c.motion.frame] = true;
        }
        assert(!c.motion.phase && !c.motion.frame);
        for (unsigned i = 0; i < c.motion.animation->frames; i++) assert(seen[i]);
        ht_character_motion_t before = c.motion;
        assert(ht_character_select(&c, id));
        assert(!memcmp(&before, &c.motion, sizeof before));
        assert(!ht_character_select(&c, HT_CHARACTER_COUNT) && c.id == (ht_character_id_t)id);
        assert(!ht_character_select(&c, (ht_character_id_t)-1));
        assert(ht_character_select(&c, (id + 1) % HT_CHARACTER_COUNT));
        assert(!c.motion.initialized && !c.motion.reaction.initialized);
        tick(&c, 10000, (ht_character_mood_t)255, false, true, false, 0);
        assert(c.motion.reaction.mood == HT_CHARACTER_IDLE);
    }
}

static void portraits(void)
{
    ht_scene_t a, b;
    ht_character_t c = {0};
    ht_character_face_t f = {.recipient = "Parser helper", .status = "Working", .hint = "tap to talk",
        .detail = "A carried paragraph", .foreground = 0xffff, .ink = 0xafe0, .dim = 0x7777, .roomy_reading = true};
    ht_scene_clear(&a, ht_rgb(0x181818)); redraw(NULL, &a);
    for (int id = 0; id < HT_CHARACTER_COUNT; id++) {
        ht_character_select(&c, id);
        for (int size = HT_CHARACTER_FULL; size <= HT_CHARACTER_QUICK; size++) {
            for (int mood = HT_CHARACTER_IDLE; mood < HT_CHARACTER_MOODS; mood++) {
                f.mood = mood;
                for (unsigned frame = 0; frame < 8; frame++) {
                    c.motion.frame = frame;
                    c.delivery.lift = (frame >> 1) & 1;
                    f.pose = (ht_character_pose_t){.blink = frame == 0, .look = (int)(frame % 5) - 2,
                        .pressed = frame == 3, .level = frame % 5};
                    ht_scene_clear(&b, a.background);
                    ht_character_portrait(&b, &c, &f, ht_rgb(0xc8a9f0), size, 98);
                    assert(b.count && b.count <= HT_RUNS - 9);
                    redraw(&a, &b); a = b;
                    uint16_t bg = (b.background << 8) | (b.background >> 8);
                    unsigned pixels = 0;
                    for (int y = 0; y < HT_HEIGHT; y++) for (int x = 0; x < HT_WIDTH; x++) {
                        if (full[y * HT_WIDTH + x] == bg) continue;
                        assert((x - 233) * (x - 233) + (y - 233) * (y - 233) < 230 * 230);
                        pixels++;
                    }
                    assert(pixels > 100);
                    f.focus = size == HT_CHARACTER_COMPACT;
                    f.straight_title = frame & 1; f.unread = frame & 2;
                    const char *recap = size == HT_CHARACTER_BRIEF ? "Fixed the parser. All tests pass." :
                        size == HT_CHARACTER_READING ? "Fixed the parser. All tests pass. Voice input now sends to the selected agent, including after switching characters or reading another pane." : NULL;
                    ht_scene_clear(&b, a.background);
                    ht_character_face(&b, &c, &f, ht_rgb(0xc8a9f0), recap);
                    assert(b.count <= HT_RUNS - 1); // Reading fits; voice puts the letter away for Discard.
                    redraw(&a, &b); a = b;
                }
            }
        }
    }
    // Changing only a cell's colour must repaint it. Compare against separate
    // uniform text runs so this also checks the palette and clipped raster path.
    const uint16_t red_blue[] = {0xf800, 0x001f}, green_blue[] = {0x07e0, 0x001f};
    ht_scene_clear(&a, 0);
    int w = ht_mono_20.width;
    assert(ht_ascii_text(&a, 200, 210, w * 2, &ht_mono_20, 0xffff, 0, "##", 2));
    a.runs[0].colors = red_blue; redraw(NULL, &a);
    b = a; b.runs[0].colors = green_blue; redraw(&a, &b);
    ht_scene_t reference; ht_scene_clear(&reference, 0);
    assert(ht_text(&reference, 200, 210, w, &ht_mono_20, 0x07e0, 0, "#"));
    assert(ht_text(&reference, 200 + w, 210, w, &ht_mono_20, 0x001f, 0, "#"));
    ht_raster(&reference, (ht_rect_t){0, 0, HT_WIDTH, HT_HEIGHT}, scratch);
    assert(!memcmp(full, scratch, sizeof full));
}

static void delivery_and_caption(void)
{
    for (int id = 0; id < HT_CHARACTER_COUNT; id++) {
        ht_character_t c = {0}; ht_character_select(&c, id);
        c.motion.next_ms = 1000;
        assert(!ht_character_delivery_tick(&c, 100, true, 0, true)); // Restored mail only holds.
        assert(!c.delivery.moving);
        ht_character_delivery_tick(&c, 200, true, 1, true);
        assert(c.delivery.moving && c.motion.next_ms == 160);
        ht_character_delivery_tick(&c, 360, true, 1, true); assert(c.delivery.lift == 1);
        ht_character_delivery_tick(&c, 400, true, 2, true); // Burst coalesces.
        ht_character_delivery_tick(&c, 1480, true, 2, true); assert(!c.delivery.moving && !c.delivery.lift);
        ht_character_delivery_tick(&c, 1600, true, 3, false);
        ht_character_delivery_tick(&c, 1760, true, 3, true); assert(!c.delivery.moving); // No replay on wake.
        ht_character_delivery_tick(&c, UINT32_MAX - 79, true, UINT32_MAX, true);
        ht_character_delivery_tick(&c, 80, true, UINT32_MAX, true); assert(c.delivery.lift == 1);
        ht_character_delivery_tick(&c, 81, false, 0, true); assert(!c.delivery.moving && !c.delivery.lift);
    }
    ht_character_caption_t c = {0};
    ht_character_caption_tick(&c, 100, "a", false); assert(!c.activity && c.opacity == 255);
    ht_character_caption_tick(&c, 200, "a", true); assert(!c.activity && c.opacity == 255);
    ht_character_caption_tick(&c, 3080, "a", true); assert(!c.activity && c.opacity < 255);
    ht_character_caption_tick(&c, 3200, "a", true); assert(c.activity && !c.opacity);
    ht_character_caption_tick(&c, 3500, "a", true); assert(c.activity && c.opacity == 255);
    ht_character_caption_tick(&c, 6500, "a", true); assert(!c.activity && c.opacity == 255);
    ht_character_caption_tick(&c, 9600, "a", true); assert(c.activity);
    ht_character_caption_tick(&c, 9601, "a", false); assert(!c.activity && c.opacity == 255);
    ht_character_caption_tick(&c, UINT32_MAX - 1499, "a", true);
    ht_character_caption_tick(&c, 1700, "a", true); assert(c.activity);
    ht_character_caption_tick(&c, 1701, "b", true); assert(!c.activity && c.opacity == 255);
    assert(ht_character_caption_ink(0xffff, 0x18c3, 0) == 0x18c3);
    assert(ht_character_caption_ink(0xffff, 0x18c3, 255) == 0xffff);
}

static void recap_budget(void)
{
    for (int id = 0; id < HT_CHARACTER_COUNT; id++) for (int unicode = 0; unicode < 2; unicode++)
        for (int length = 89; length <= 91; length++) {
            ht_character_t c = {0}; ht_character_select(&c, id);
            ht_character_face_t f = {.roomy_reading=true, .single_label=true, .foreground=0xffff};
            char input[400] = "", visible[400] = "";
            for (int i = 0; i < length; i++) strcat(input, unicode ? "\xc3\xa9" : "x");
            ht_scene_t scene; ht_scene_clear(&scene, 0);
            ht_character_face(&scene, &c, &f, 0xffff, input);
            int rows = 0, chars = 0;
            for (int i = 0; i < scene.count; i++) if (scene.runs[i].font == &ht_mono_28) {
                if (scene.runs[i].text[0]) rows++;
                strcat(visible, scene.runs[i].text);
            }
            for (const char *p = visible; *p; chars++) {
                uint32_t cp = ht_utf8_next(&p);
                assert(cp == (unicode ? 0xe9u : 'x') || cp == '.');
            }
            assert(rows <= 4 && chars <= 90);
            if (length <= 90) assert(!strcmp(input, visible));
            else assert(!strcmp(visible + strlen(visible) - 3, "..."));
        }
}

int main(void)
{
    assert(!strcmp(ht_character_name(HT_CHARACTER_TIM), "Tim"));
    assert(!strcmp(ht_character_name(HT_CHARACTER_TUX), "Tux"));
    clocks(); portraits(); delivery_and_caption(); recap_budget();
    printf("Characters: both adapters, eight moods, five sizes, pause/mic/wrap/swap and %u exact incremental redraws PASS\n", redraws);
}
