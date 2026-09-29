"""Exercise production brightness loading, controls, and persistence conversions."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

here = Path(__file__).resolve().parent
source = Path(os.environ.get('UI_SOURCE', here / '../main/ui/habitat/ui_habitat.c')).read_text()

def function(name, text=source):
    match = re.search(r'^[^\n]*\b' + name + r'\([^;]*?\)\n\{.*?^\}', text, re.M | re.S)
    assert match, name
    return match.group(0)

def brightness_case(name):
    match = re.search(r'    case A_BRIGHT:.*?\bbreak;', function(name), re.S)
    assert match, name
    return match.group(0)

load = re.search(r'    s\.brightness = [^;]*config_load_brightness\(\)[^;]*;', function('ui_init')).group(0)
code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "theme.h"
static struct { int brightness; } s;
typedef struct { int kind, value; } action_t;
enum { A_BRIGHT };
static action_t pending;
static uint8_t saved;
static bool has_saved=true, can_open=true;
static int closes;
typedef int nvs_handle_t;
#define ESP_OK 0
#define NVS_READONLY 1
static const char *NS="pair";
static int nvs_open(const char *name,int mode,nvs_handle_t *handle) {
    assert(!strcmp(name,NS) && mode==NVS_READONLY); *handle=1; return can_open ? ESP_OK : -1;
}
static int nvs_get_u8(nvs_handle_t handle,const char *key,uint8_t *value) {
    assert(handle==1 && !strcmp(key,"bright"));
    if(!has_saved)return -1;
    *value=saved; return ESP_OK;
}
static void nvs_close(nvs_handle_t handle) { assert(handle==1);closes++; }
static void config_save_brightness(uint8_t value) { saved=value; }
static void display_lock(void) {}
static void display_unlock(void) {}
static void change(void) {}
static bool queue(action_t a) { pending=a; return true; }
#ifdef DEVICE_PRO_COMPANION
static uint8_t backlight;
static void pro_backlight_set(uint8_t value) { backlight=value; }
#endif
'''
code += function('config_load_brightness', (here / '../main/config_store.c').read_text()) + '\n'
code += function('display_set_brightness', (here / '../main/ui/habitat/display_habitat.c').read_text()) + '\n'
code += function('ui_set_brightness') + '\n'
code += function('ht_rgb', (here / '../main/ui/habitat/terminal.c').read_text()) + '\n'
code += function('color') + '\n'
code += 'static void load_saved(void) {\n' + load + '\n}\n'
code += 'static void tap_brightness(void) { action_t a={.kind=A_BRIGHT}; switch(a.kind) {\n' + brightness_case('dispatch') + '\n} }\n'
code += 'static void persist(void) { action_t a=pending; switch(a.kind) {\n' + brightness_case('worker') + '\n} }\n'
code += r'''
int main(void) {
    has_saved=false;
#ifdef DEVICE_PRO_COMPANION
    const uint8_t default_level=220;
#else
    const uint8_t default_level=0x99;
#endif
    assert(config_load_brightness()==default_level && closes==1);
    can_open=false;
    assert(config_load_brightness()==default_level && closes==1);
    can_open=has_saved=true;
    // The factory byte 0x99 is 60%. Two presses used to produce 85%, then
    // 110%, whose persisted byte wrapped back to a nearly dark display.
    saved=0x99; load_saved(); assert(s.brightness==60);
    tap_brightness(); tap_brightness();
    if (s.brightness>100) {
        fprintf(stderr,"Brightness escaped its range: %d%%\n",s.brightness);
        return 1;
    }
    int previous=-1;
    for(int level=0;level<=255;level++) {
        saved=(uint8_t)level; load_saved();
        assert(config_load_brightness()==level); // Every explicit setting overrides the default.
        int loaded=s.brightness;
        ui_set_brightness((uint8_t)level);
        assert(s.brightness==loaded && loaded>=previous && loaded<=100);
#ifdef DEVICE_PRO_COMPANION
        assert(backlight==(level<20 ? 20 : level));
#endif
        previous=loaded;
        for(int step=0;step<8;step++) {
            int before=s.brightness;
            tap_brightness();
            int chosen=s.brightness;
            assert(chosen>=25 && chosen<=100 && chosen%25==0);
            assert(before==100 ? chosen==25 : chosen>before);
            assert(pending.value==chosen);
#ifdef DEVICE_PRO_COMPANION
            assert(backlight==(chosen*255+50)/100);
#endif
            persist(); load_saved();
            assert(s.brightness==chosen); // Reboot cannot change the selected step.
            ui_set_brightness(saved); assert(s.brightness==chosen);
        }
    }
    for(int percent=0;percent<=100;percent++) {
        s.brightness=percent;
        uint16_t canvas=color(HT_THEME_CANVAS);
#ifdef DEVICE_PRO_COMPANION
        // Physical backlight adjustment must not also dim text or shift the palette.
        assert(canvas==ht_rgb(HT_THEME_CANVAS));
        assert(color(HT_THEME_TEXT)==ht_rgb(HT_THEME_TEXT));
        assert(color(HT_THEME_ACCENT)==ht_rgb(HT_THEME_ACCENT));
#else
        unsigned r=canvas>>11, g=(canvas>>5)&63, b=canvas&31;
        r=(r<<3)|(r>>2); g=(g<<2)|(g>>4); b=(b<<3)|(b>>2);
        assert(r==g && g==b && r<=24);
        if(percent==25)assert(r==8);
        if(percent==60)assert(r==16);
        if(percent==100)assert(r==24 && color(HT_THEME_TEXT)==ht_rgb(HT_THEME_TEXT));
#endif
    }
    puts("Brightness: missing/default and 256 explicit saved levels, 2048 control/save/reload cycles, palette at all 101 percentages PASS");
}
'''
with tempfile.TemporaryDirectory(prefix='harness-brightness-') as directory:
    out=Path(directory)
    (out/'test.c').write_text(code)
    for mode, flags in [('round',[]),('pro',['-DDEVICE_PRO_COMPANION=1'])]:
        binary=out/mode
        subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-O1','-g',*flags,
            '-fsanitize='+os.environ.get('SANITIZERS','undefined,bounds'),
            '-I',str(here / '../main/ui/habitat'),str(out/'test.c'),'-o',str(binary)],check=True)
        subprocess.run([str(binary)],check=True)
