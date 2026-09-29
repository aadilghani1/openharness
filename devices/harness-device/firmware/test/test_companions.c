// Decode the shipped assets and prove dirty rectangles reproduce a full frame,
// including alpha layering, changes of species, small portraits and held mail.
#include "character.h"
#include "illustrated.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint16_t full[HT_WIDTH * HT_HEIGHT], partial[HT_WIDTH * HT_HEIGHT];
static uint16_t strip[HT_WIDTH * HT_HEIGHT];
static unsigned scenes;

static void redraw(const ht_scene_t *before, ht_scene_t *after)
{
    ht_illustrated_prepare(after);
    ht_damage_t damage;
    ht_damage(before, after, &damage);
    for (unsigned i = 0; i < damage.count; i++) {
        ht_rect_t r = damage.rect[i];
        assert(r.x >= 0 && r.y >= 0 && r.x+r.w <= HT_WIDTH && r.y+r.h <= HT_HEIGHT);
        ht_raster(after, r, strip);
        for (int y = 0; y < r.h; y++)
            memcpy(partial + (r.y+y)*HT_WIDTH+r.x, strip+y*r.w, r.w*2);
    }
    ht_raster(after, (ht_rect_t){0,0,HT_WIDTH,HT_HEIGHT}, full);
    assert(!memcmp(partial, full, sizeof full));
    scenes++;
}

int main(int argc, char **argv)
{
    static const char *ids[] = {"tim","gnu","lynx","mutt","yak","gopher","bug","tux","auk","beastie"};
    ht_illustrated_init();
    ht_scene_t before, after;
    ht_scene_clear(&before, ht_rgb(0x181818)); redraw(NULL, &before);
    ht_character_t character = {0};
    ht_character_face_t face = {.recipient="Đang làm · GNU", .status="Working", .foreground=0xffff,
        .ink=0xafe0, .dim=0x7777, .roomy_reading=true};
    for (unsigned species = 0; species < 10; species++) {
        ht_character_id_t id = ht_character_companion(ids[species]);
        assert(id >= HT_CHARACTER_ILLUSTRATED_TIM && id < HT_CHARACTER_COUNT);
        assert(!strcmp(ht_character_species(id), ids[species]));
        assert(ht_character_select(&character, id));
        for (unsigned mood = 0; mood < HT_CHARACTER_MOODS; mood++) {
            face.mood = mood;
            for (unsigned variation = 0; variation < 8; variation++) {
                for (unsigned small = 0; small < 2; small++) {
                    character.motion.frame = variation * 3;
                    face.unread = variation & 1;
                    face.pose = (ht_character_pose_t){.pressed=variation==2, .look=(int)species%5-2};
                    ht_scene_clear(&after, before.background);
                    ht_character_face(&after, &character, &face, 0xffff,
                        small ? "The companion follows your desktop choice." : NULL);
                    redraw(&before, &after);
                    if (!mood && !variation && !small && argc > 1) {
                        char path[1024]; snprintf(path, sizeof path, "%s/%s.ppm", argv[1], ids[species]);
                        FILE *file=fopen(path,"wb"); assert(file);
                        fprintf(file,"P6\n%d %d\n255\n",HT_WIDTH,HT_HEIGHT);
                        for(unsigned px=0;px<HT_WIDTH*HT_HEIGHT;px++) {
                            uint16_t rgb=(full[px]>>8)|(full[px]<<8);
                            uint8_t bytes[]={(rgb>>11)*255/31,((rgb>>5)&63)*255/63,(rgb&31)*255/31};
                            assert(fwrite(bytes,1,3,file)==3);
                        }
                        fclose(file);
                    }
                    before=after;
                }
            }
        }
        // Touch freezes motion, quiet mode remains still, and switching resets it.
        ht_character_tick(&character, 0, HT_CHARACTER_WORKING, false, true, false, 233, 0, 0);
        ht_character_tick(&character, 100, HT_CHARACTER_WORKING, false, true, true, 330, 0, 0);
        uint16_t held=character.motion.phase;
        ht_character_tick(&character, 5000, HT_CHARACTER_WORKING, false, true, true, 330, 0, 0);
        assert(character.motion.phase==held && character.motion.reaction.pose.pressed);
        ht_character_tick(&character, 6000, HT_CHARACTER_WORKING, true, true, false, 233, 0, 0);
        assert(character.motion.frame==0);
    }
    assert(ht_character_companion(NULL)==HT_CHARACTER_COUNT && ht_character_companion("unknown")==HT_CHARACTER_COUNT);
    assert(ht_character_select(&character, HT_CHARACTER_FOCUS));
    ht_scene_clear(&after, before.background); ht_character_face(&after,&character,&face,0xffff,NULL);
    redraw(&before,&after);
    printf("Illustrated companions: ten species, eight moods, two layouts; %u exact incremental redraws PASS\n",scenes);
}
