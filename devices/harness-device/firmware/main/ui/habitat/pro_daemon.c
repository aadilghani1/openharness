#include "pro_daemon.h"

static const pro_daemon_definition_t definitions[] = {
#define PRO_DAEMON(symbol,key,name,scene,bob) {HT_CHARACTER_##symbol,key,name,PRO_SCENE_##scene,bob},
#include "pro_daemons.def"
#undef PRO_DAEMON
};
unsigned pro_daemon_count(void) { return sizeof definitions / sizeof definitions[0]; }
const pro_daemon_definition_t *pro_daemon_at(unsigned index)
{
    return &definitions[index < pro_daemon_count() ? index : 0];
}
unsigned pro_daemon_index(ht_character_id_t id)
{
    for (unsigned i=0;i<pro_daemon_count();i++) if (definitions[i].id==id) return i;
    return 0;
}
const pro_daemon_definition_t *pro_daemon_definition(ht_character_id_t id)
{
    return pro_daemon_at(pro_daemon_index(id));
}
const char *pro_scene_name(pro_scene_id_t scene)
{
    static const char *const names[]={"Match daemon","Meadow","Shore","Dusk","Paper"};
    return names[(unsigned)scene<PRO_SCENE_COUNT ? scene : PRO_SCENE_MATCH];
}
pro_scene_id_t pro_scene_resolve(pro_scene_id_t scene, ht_character_id_t daemon)
{
    return scene>PRO_SCENE_MATCH && scene<PRO_SCENE_COUNT ? scene : pro_daemon_definition(daemon)->scene;
}
bool pro_daemon_tick(ht_character_motion_t *m, uint32_t now, ht_character_mood_t mood,
                     bool quiet, bool visible, bool down, int x, unsigned level, uint32_t activity)
{
    static const uint16_t step_ms[HT_CHARACTER_MOODS]={150,90,140,55,180,220,35,100};
    if ((unsigned)mood>=HT_CHARACTER_MOODS) mood=HT_CHARACTER_IDLE;
    bool reset=!m->initialized || m->reaction.mood!=mood;
    uint8_t old_frame=m->frame;
    bool changed=ht_character_reaction_tick(&m->reaction,now,mood,quiet,visible,down,x,level,activity);
    bool running=visible && !quiet && !down && mood!=HT_CHARACTER_OFFLINE;
    uint32_t step=step_ms[mood], period=24*step;
    bool finite=mood==HT_CHARACTER_DONE || mood==HT_CHARACTER_BOOPED;
    if (reset) m->phase=0;
    else if (running && m->running) {
        uint32_t delta=now-m->last_ms;
        if (finite) m->phase=delta>=period-m->phase ? period-1 : m->phase+delta;
        else m->phase=(m->phase+delta%period)%period;
    }
    m->frame=quiet || mood==HT_CHARACTER_OFFLINE ? 0 : m->phase/step;
    m->last_ms=now; m->initialized=true; m->running=running;
    m->next_ms=m->reaction.next_ms;
    if (running && (!finite || m->frame<23)) {
        uint32_t next=step-m->phase%step;
        if (next<m->next_ms) m->next_ms=next;
    }
    return changed || reset || old_frame!=m->frame;
}
