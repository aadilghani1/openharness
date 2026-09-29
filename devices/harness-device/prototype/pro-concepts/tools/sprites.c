#include "character.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    uint16_t *pixels = calloc(720 * 720, 2);
    if (!pixels) return 3;
    for (int id = 0; id < 2; ++id) {
        ht_character_t c = {0};
        ht_character_select(&c, id);
        for (int frame = 0; frame < 24; ++frame) {
            ht_scene_t scene;
            ht_scene_clear(&scene, 0);
            ht_character_tick(&c, 1000 + frame * 120, HT_CHARACTER_IDLE,
                              false, true, false, 360, 0, 0);
            ht_character_face_t face = {.mood=HT_CHARACTER_IDLE,
                .pose=c.motion.reaction.pose, .ink=ht_rgb(0xb09aff),
                .foreground=ht_rgb(0xffffff), .dim=ht_rgb(0x777777)};
            ht_character_portrait(&scene, &c, &face, face.ink, HT_CHARACTER_FULL, 0);
            ht_raster(&scene, (ht_rect_t){0,0,720,720}, pixels);
            char path[1024];
            snprintf(path, sizeof path, "%s/%s-%02d.ppm", argv[1], id ? "tux" : "tim", frame);
            FILE *out = fopen(path, "wb");
            if (!out) return 4;
            fprintf(out, "P6\n720 720\n255\n");
            for (int i=0;i<720*720;i++) {
                uint16_t v=pixels[i];
                unsigned char rgb[]={((v>>11)&31)*255/31,((v>>5)&63)*255/63,(v&31)*255/31};
                fwrite(rgb,1,3,out);
            }
            fclose(out);
        }
    }
    free(pixels);
    return 0;
}
