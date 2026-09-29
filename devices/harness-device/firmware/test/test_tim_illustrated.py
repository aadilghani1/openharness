"""Actual round sprite renderer, damage, eight moods and shared character registry."""
from pathlib import Path
import os
import subprocess
import tempfile

FW=Path(__file__).resolve().parent.parent
NATIVE=FW/'main/ui/habitat'
GENERATED=FW.parent/'prototype/tim-illustrated/generated'
CODE=r'''
#include "tim_illustrated.h"
#include "tim_art.h"
#include "character.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
extern const uint8_t pack[] asm("_binary_tim_art_pack_start");
static unsigned allocations,decodes,checked;
static uint16_t pixels[466*466],oracle[466*466],incremental[466*466],strip[466*466];
void *test_allocate(size_t n){allocations++;return malloc(n);}
size_t test_inflate(void *d,size_t cap,const void *s,size_t n){uLongf size=cap;decodes++;return uncompress(d,&size,s,n)==Z_OK?size:(size_t)-1;}
static uint16_t swap(uint16_t p){return p<<8|p>>8;}
static uint16_t over(uint16_t fg,uint16_t bg,unsigned a){
    fg=swap(fg);bg=swap(bg);unsigned out=0;
    const unsigned shifts[]={11,5,0},masks[]={31,63,31};
    for(int k=0;k<3;k++)out|=(((((fg>>shifts[k])&masks[k])*a+((bg>>shifts[k])&masks[k])*(255-a)+127)/255)<<shifts[k]);
    return swap(out);
}
static void verify(ht_scene_t *s,const ht_scene_t *previous){
    ht_scene_t text=*s;for(unsigned i=0;i<text.count;i++)if(text.runs[i].sprite.width){
        text.runs[i].sprite=(ht_sprite_t){0};text.runs[i].font=&ht_mono_20;text.runs[i].bg=text.background;
    }
    ht_raster(&text,(ht_rect_t){0,0,466,466},oracle);
    for(unsigned k=0;k<s->count;k++){
        const ht_run_t *r=&s->runs[k];const tim_art_frame_t *a=r->sprite.asset;if(!a)continue;
        uint8_t *raw=malloc(a->raw_length);assert(raw);uLongf size=a->raw_length;
        assert(uncompress(raw,&size,pack+a->offset,a->length)==Z_OK && size==a->raw_length);
        const uint16_t *color=(const uint16_t*)raw;const uint8_t *alpha=raw+a->width*a->height*2;
        for(int y=0;y<a->height;y++)for(int x=0;x<a->width;x++){
            int px=x+r->x,py=y+r->y;if(px<0||px>=466||py<0||py>=466)continue;
            unsigned at=y*a->width+x;oracle[py*466+px]=over(color[at],oracle[py*466+px],alpha[at]);
        }
        free(raw);
    }
    ht_tim_illustrated_prepare(s);ht_raster(s,(ht_rect_t){0,0,466,466},pixels);
    assert(!memcmp(pixels,oracle,sizeof pixels));
    ht_damage_t damage;ht_damage(previous,s,&damage);
    for(unsigned k=0;k<damage.count;k++){
        ht_rect_t r=damage.rect[k];ht_raster(s,r,strip);
        for(int y=0;y<r.h;y++)memcpy(incremental+(r.y+y)*466+r.x,strip+y*r.w,r.w*2);
    }
    assert(!memcmp(pixels,incremental,sizeof pixels));checked++;
}
static void preview(const char *folder,unsigned n){
    char path[1024];snprintf(path,sizeof path,"%s/%02u.ppm",folder,n);FILE *f=fopen(path,"wb");assert(f);
    fprintf(f,"P6\n466 466\n255\n");
    for(int i=0;i<466*466;i++){uint16_t p=swap(pixels[i]);uint8_t c[]={((p>>11)&31)*255/31,((p>>5)&63)*255/63,(p&31)*255/31};fwrite(c,1,3,f);}fclose(f);
}
int main(int argc,char **argv){
    assert(argc==2);ht_tim_illustrated_init();ht_tim_illustrated_init();assert(allocations==2);
    ht_scene_t last={0},next;bool first=true;ht_character_t c={0};
    ht_character_face_t f={.roomy_reading=true,.single_label=true,.recipient="A little company",.foreground=0xffff,.dim=0x8410};
    for(unsigned small=0;small<2;small++)for(unsigned mood=0;mood<8;mood++)for(unsigned frame=0;frame<24;frame++){
        f.mood=mood;f.pose.mail=frame%3;unsigned old=decodes;
        ht_scene_clear(&next,ht_rgb(0x181818));
        ht_tim_illustrated_draw(&next,&f,frame,0,small?HT_CHARACTER_READING:HT_CHARACTER_FULL,small?82:100);
        ht_center(&next,small?230:364,&ht_mono_28,ht_rgb(0xefe7de),"A little company.");
        ht_arc_status(&next,ht_rgb(0xc6aaef),"Harness");assert(decodes==old);
        verify(&next,first?NULL:&last);last=next;first=false;
        if(frame==11)preview(argv[1],small*8+mood);
    }
    // Touch gaze, letter attachment and clipping through the same pixel oracle.
    for(int gaze=-2;gaze<=2;gaze++){
        f.pose.pressed=true;f.pose.look=gaze;ht_scene_clear(&next,ht_rgb(0x181818));
        ht_tim_illustrated_draw(&next,&f,0,0,HT_CHARACTER_FULL,-45);verify(&next,&last);last=next;
    }
    // Registry switch must erase all sprite pixels when the ASCII Tux takes over.
    ht_character_select(&c,HT_CHARACTER_TUX);ht_scene_clear(&next,ht_rgb(0x181818));
    ht_character_face(&next,&c,&f,ht_rgb(0xc6aaef),"Ready to help.");verify(&next,&last);last=next;
    ht_character_select(&c,HT_CHARACTER_TIM);f.pose.pressed=false;f.mood=HT_CHARACTER_IDLE;
    ht_scene_clear(&next,ht_rgb(0x181818));ht_character_face(&next,&c,&f,ht_rgb(0xc6aaef),"Ready to help.");
    verify(&next,&last);preview(argv[1],16);
    assert(next.runs[0].sprite.width==108);
    // Animation boundaries, pause/resume, finite completion and clock wrap.
    ht_character_motion_t m={0};
    ht_tim_illustrated_tick(&m,0xffffff80u,HT_CHARACTER_IDLE,false,true,false,233,0,0);assert(m.frame==0);
    ht_tim_illustrated_tick(&m,22,HT_CHARACTER_IDLE,false,true,false,233,0,0);assert(m.frame==1);
    ht_tim_illustrated_tick(&m,50,HT_CHARACTER_IDLE,true,true,false,233,0,0);assert(m.frame==0);
    ht_tim_illustrated_tick(&m,10000,HT_CHARACTER_DONE,false,true,false,233,0,1);assert(m.frame==0);
    ht_tim_illustrated_tick(&m,12000,HT_CHARACTER_DONE,false,true,false,233,0,1);assert(m.frame==23);
    ht_tim_illustrated_tick(&m,20000,HT_CHARACTER_DONE,false,true,false,233,0,1);assert(m.frame==23);
    ht_tim_illustrated_tick(&m,21000,HT_CHARACTER_LISTENING,false,true,false,233,4,2);assert(m.frame==16);
    ht_tim_illustrated_tick(&m,21100,HT_CHARACTER_LISTENING,false,true,false,233,4,2);assert(m.frame==17);
    assert(allocations==2);printf("Illustrated Tim PASS: %u pixel/damage scenes, 2 fixed allocations, %u decodes\n",checked,decodes);
}
'''

with tempfile.TemporaryDirectory(prefix='harness-tim-art-') as tmp:
    out=Path(tmp)
    (out/'test.c').write_text(CODE)
    (out/'esp_heap_caps.h').write_text('#pragma once\n#include <stddef.h>\n#define MALLOC_CAP_SPIRAM 1\n#define MALLOC_CAP_8BIT 2\nvoid *test_allocate(size_t);\nstatic inline void *heap_caps_malloc(size_t n,unsigned f){(void)f;return test_allocate(n);}\n')
    (out/'esp_log.h').write_text('#pragma once\n#define ESP_LOGI(...) ((void)0)\n')
    (out/'miniz.h').write_text('#pragma once\n#include <stddef.h>\n#define TINFL_FLAG_PARSE_ZLIB_HEADER 1\nsize_t test_inflate(void*,size_t,const void*,size_t);\nstatic inline size_t tinfl_decompress_mem_to_mem(void*d,size_t c,const void*s,size_t n,int f){(void)f;return test_inflate(d,c,s,n);}\n')
    (out/'art.S').write_text('#ifdef __APPLE__\n.section __DATA,__const\n#else\n.section .rodata\n#endif\n.balign 8\n.globl _binary_tim_art_pack_start\n_binary_tim_art_pack_start:\n.incbin "'+str(GENERATED/'tim_art.pack')+'"\n.globl _binary_tim_art_pack_end\n_binary_tim_art_pack_end:\n')
    names=('tim_illustrated','character','character_motion','character_layout','tux','octopus','octopus_font','ascii_clip','terminal','fonts')
    subprocess.run(['cc','-std=gnu11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',
                    '-DDEVICE_TIM_ILLUSTRATED=1','-I',str(out),'-I',str(NATIVE),'-I',str(GENERATED),
                    str(out/'test.c'),str(out/'art.S'),*[str(NATIVE/(n+'.c')) for n in names],'-lz','-o',str(out/'test')],check=True)
    previews=GENERATED/'previews';previews.mkdir(exist_ok=True)
    subprocess.run([str(out/'test'),str(previews)],check=True,env={**os.environ,'ASAN_OPTIONS':'detect_leaks=0:abort_on_error=1'})
    from PIL import Image,ImageDraw
    sheet=Image.new('RGB',(4*466,4*466),'#000000')
    for index in range(17):
        p=previews/f'{index:02}.ppm';im=Image.open(p);im.save(p.with_suffix('.png'));p.unlink()
        if index<16:sheet.paste(im,(index%4*466,index//4*466))
    sheet.save(previews/'contact-sheet.png')
