#include "illustrated.h"
#include "../../../assets/companions/companion_art.h"
#include <assert.h>
#ifdef ESP_PLATFORM
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "miniz.h"
#else
#include <stdlib.h>
#include <zlib.h>
#endif

extern const uint8_t companion_pack_start[] __asm__("_binary_companion_art_pack_start");
extern const uint8_t companion_pack_end[] __asm__("_binary_companion_art_pack_end");
typedef struct { uint8_t *memory; uint32_t revision; ht_sprite_t sprite; } cache_t;
static cache_t cache[COMPANION_ROLES];

void ht_illustrated_init(void)
{
    for (unsigned i = 0; i < COMPANION_ROLES; i++) {
        if (cache[i].memory) continue;
#ifdef ESP_PLATFORM
        cache[i].memory = heap_caps_malloc(companion_capacity[i], MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
#else
        cache[i].memory = malloc(companion_capacity[i]);
#endif
        assert(cache[i].memory);
    }
}

void ht_illustrated_prepare(ht_scene_t *scene)
{
    const companion_asset_t *selected[COMPANION_ROLES] = {0};
    for (unsigned i = 0; i < scene->count; i++) {
        ht_sprite_t *sprite = &scene->runs[i].sprite;
        if (!sprite->asset) continue;
        const companion_asset_t *asset = sprite->asset;
        assert(asset->role < COMPANION_ROLES);
        unsigned role = asset->role;
        assert(!selected[role] || selected[role]->offset == asset->offset);
        selected[role] = asset;
        cache_t *c = &cache[role];
        assert(c->memory);
        if (c->revision != asset->offset + 1) {
            size_t length = (size_t)(companion_pack_end - companion_pack_start);
            size_t raw = (size_t)asset->width * asset->height * 3;
            assert(asset->offset <= length && asset->length <= length - asset->offset);
            assert(raw <= companion_capacity[role]);
#ifdef ESP_PLATFORM
            size_t got = tinfl_decompress_mem_to_mem(c->memory, companion_capacity[role],
                companion_pack_start + asset->offset, asset->length, TINFL_FLAG_PARSE_ZLIB_HEADER);
            assert(got == raw);
#else
            uLongf got = companion_capacity[role];
            int result = uncompress(c->memory, &got, companion_pack_start + asset->offset, asset->length);
            assert(result == Z_OK && got == raw);
#endif
            c->sprite = (ht_sprite_t){.pixels=(const uint16_t *)c->memory,
                .alpha=c->memory + raw/3*2, .asset=asset, .revision=asset->offset+1,
                .width=asset->width, .height=asset->height};
            c->revision = asset->offset + 1;
        }
        *sprite = c->sprite;
    }
}
