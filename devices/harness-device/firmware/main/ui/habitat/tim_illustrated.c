#include "tim_illustrated.h"
#include "tim_art.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "miniz.h"
#include <assert.h>
#include <string.h>

extern const uint8_t tim_pack_start[] asm("_binary_tim_art_pack_start");
extern const uint8_t tim_pack_end[] asm("_binary_tim_art_pack_end");
typedef struct { uint8_t *memory;size_t capacity;uint32_t revision;ht_sprite_t sprite; } cache_t;
static cache_t portrait,letter;
void ht_tim_illustrated_init(void)
{
    if(portrait.memory)return;
    portrait.capacity=TIM_ART_HERO*TIM_ART_HERO*3;letter.capacity=44*44*3;
    portrait.memory=heap_caps_malloc(portrait.capacity,MALLOC_CAP_SPIRAM|MALLOC_CAP_8BIT);
    letter.memory=heap_caps_malloc(letter.capacity,MALLOC_CAP_SPIRAM|MALLOC_CAP_8BIT);
    assert(portrait.memory && letter.memory);
    ESP_LOGI("tim-art","illustrated Tim: 8 moods, 240/108 px, %u bytes PSRAM",(unsigned)(portrait.capacity+letter.capacity));
}
static void image(ht_scene_t *s,int x,int y,const tim_art_frame_t *a)
{
    if(s->count>=HT_RUNS)return;
    ht_run_t *r=&s->runs[s->count++];memset(r,0,sizeof *r);
    r->x=x;r->y=y;r->w=a->width;
    r->sprite=(ht_sprite_t){.asset=a,.revision=a->offset+1,.width=a->width,.height=a->height};
}
void ht_tim_illustrated_prepare(ht_scene_t *s)
{
    const tim_art_frame_t *selected[2]={0};
    for(unsigned i=0;i<s->count;i++){
        ht_sprite_t *sprite=&s->runs[i].sprite;
        if(!sprite->asset)continue;
        const tim_art_frame_t *a=sprite->asset;unsigned slot=a->width<=44;
        assert(!selected[slot] || selected[slot]->offset==a->offset);selected[slot]=a;
        cache_t *c=slot?&letter:&portrait;assert(c->memory);
        if(c->revision!=a->offset+1){
            size_t length=(size_t)(tim_pack_end-tim_pack_start);
            assert(a->offset<=length && a->length<=length-a->offset && a->raw_length<=c->capacity);
            size_t got=tinfl_decompress_mem_to_mem(c->memory,c->capacity,tim_pack_start+a->offset,
                                                 a->length,TINFL_FLAG_PARSE_ZLIB_HEADER);
            assert(got==a->raw_length && got==(size_t)a->width*a->height*3);
            c->sprite=(ht_sprite_t){.pixels=(const uint16_t*)c->memory,
                .alpha=c->memory+a->width*a->height*2,.asset=a,.revision=a->offset+1,
                .width=a->width,.height=a->height};c->revision=a->offset+1;
        }
        *sprite=c->sprite;
    }
}
bool ht_tim_illustrated_tick(ht_character_motion_t *m,uint32_t now,ht_character_mood_t mood,
        bool quiet,bool visible,bool down,int x,unsigned level,uint32_t activity)
{
    if((unsigned)mood>=HT_CHARACTER_MOODS)mood=HT_CHARACTER_IDLE;
    bool new_mood=!m->initialized || m->reaction.mood!=mood;
    bool changed=ht_character_reaction_tick(&m->reaction,now,mood,quiet,visible,down,x,level,activity);
    unsigned step=mood==HT_CHARACTER_LISTENING?100:tim_art_duration[mood];
    unsigned duration=step*(mood==HT_CHARACTER_LISTENING?4:TIM_ART_FRAMES);
    bool running=visible && !quiet && !down && mood!=HT_CHARACTER_OFFLINE;
    bool finite=mood==HT_CHARACTER_DONE || mood==HT_CHARACTER_BOOPED;
    if(new_mood)m->phase=0;
    else if(m->running && running){
        uint32_t elapsed=now-m->last_ms;
        if(finite)m->phase=elapsed>=duration-1-m->phase?duration-1:m->phase+elapsed;
        else m->phase=(m->phase+elapsed%duration)%duration;
    }
    uint8_t previous=m->frame;
    m->frame=quiet || mood==HT_CHARACTER_OFFLINE ? 0 : m->phase/step;
    if(mood==HT_CHARACTER_LISTENING && !quiet)m->frame+=m->reaction.pose.level*4;
    m->initialized=true;m->running=running;m->last_ms=now;m->next_ms=m->reaction.next_ms;
    if(running && !(finite && m->phase==duration-1)){
        uint32_t next=step-m->phase%step;if(next<m->next_ms)m->next_ms=next;
    }
    return changed || new_mood || m->frame!=previous;
}
void ht_tim_illustrated_draw(ht_scene_t *s,const ht_character_face_t *f,uint8_t frame,
        uint16_t ink,ht_character_size_t size,int y)
{
    (void)ink;
    unsigned small=size==HT_CHARACTER_BRIEF || size==HT_CHARACTER_READING || size==HT_CHARACTER_QUICK;
    unsigned mood=(unsigned)f->mood<HT_CHARACTER_MOODS?f->mood:HT_CHARACTER_IDLE;
    const tim_art_frame_t *a=&tim_art_frames[small][mood][frame%TIM_ART_FRAMES];
    if(f->pose.pressed){int gaze=f->pose.look+2;if(gaze<0)gaze=0;if(gaze>4)gaze=4;a=&tim_art_touch[small][gaze];}
    int x=(HT_WIDTH-a->width)/2;image(s,x,y,a);
    if(f->pose.mail){unsigned mail=f->pose.mail>1?2:0;
        image(s,x+tim_art_letter_anchor[small][0],y+tim_art_letter_anchor[small][1],&tim_art_letter[small][mail]);}
}
