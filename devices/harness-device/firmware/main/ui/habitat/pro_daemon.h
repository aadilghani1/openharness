#pragma once
#include "character.h"

// Saved values. Append; never reorder or reuse an ID.
typedef enum {
    PRO_SCENE_MATCH=0, PRO_SCENE_MEADOW=1, PRO_SCENE_SHORE=2,
    PRO_SCENE_DUSK=3, PRO_SCENE_PAPER=4, PRO_SCENE_COUNT
} pro_scene_id_t;
typedef struct {
    ht_character_id_t id;
    const char *key, *name;
    pro_scene_id_t scene;
    uint8_t bob;
} pro_daemon_definition_t;

unsigned pro_daemon_count(void);
const pro_daemon_definition_t *pro_daemon_at(unsigned index);
const pro_daemon_definition_t *pro_daemon_definition(ht_character_id_t id);
unsigned pro_daemon_index(ht_character_id_t id);
const char *pro_scene_name(pro_scene_id_t scene);
pro_scene_id_t pro_scene_resolve(pro_scene_id_t choice, ht_character_id_t daemon);
// One motion/reaction contract for every bitmap adapter, independent of UI actions.
bool pro_daemon_tick(ht_character_motion_t *, uint32_t, ht_character_mood_t,
                     bool quiet, bool visible, bool down, int x, unsigned level,
                     uint32_t activity);
