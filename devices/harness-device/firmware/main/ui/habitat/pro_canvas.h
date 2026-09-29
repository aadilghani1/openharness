#pragma once
#include "terminal.h"

typedef struct { uint32_t offset; uint8_t width, advance; } ht_pro_glyph_t;
struct ht_pro_font {
    uint16_t first, last;
    uint8_t height;
    const ht_pro_glyph_t *glyphs;
    const uint8_t *alpha;
};
extern const ht_pro_font_t ht_pro_24, ht_pro_32, ht_pro_42, ht_pro_56;
int ht_pro_width(const ht_pro_font_t *font, const char *text);
int ht_pro_text_rows(const char *text, const ht_pro_font_t *font, int width);
bool ht_pro_text(ht_scene_t *s, int x, int y, int width, const ht_pro_font_t *font,
                 uint16_t ink, const char *text);
int ht_pro_wrap(ht_scene_t *s, int x, int y, int width, int rows, int skip,
                const ht_pro_font_t *font, uint16_t ink, const char *text);
void ht_pro_center(ht_scene_t *s, int y, const ht_pro_font_t *font, uint16_t ink, const char *text);
bool ht_pro_rect(ht_scene_t *s, int x, int y, int w, int h, int radius, uint16_t ink);
bool ht_pro_image(ht_scene_t *s, int x, int y, const ht_pro_bitmap_t *bitmap);
void ht_pro_raster(const ht_run_t *run, ht_rect_t clip, uint16_t *out);
