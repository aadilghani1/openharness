"""Persist both language choices; surface storage errors; keep translations format-safe."""
from pathlib import Path
import json
import os
import re
import subprocess
import tempfile
import unicodedata

MAIN = Path(__file__).resolve().parent / '../main'
source = (MAIN / 'config_store.c').read_text()

def function(name):
    match = re.search(r'^[^\n]*\b' + name + r'\([^;]*?\)\n\{.*?^\}', source, re.M | re.S)
    assert match, name
    return match.group(0) + '\n'

catalog = MAIN / 'ui/habitat/pro_strings.inc'
rows = [json.loads('[' + line.rstrip(',')[1:-1] + ']')
        for line in catalog.read_text().splitlines() if line.startswith('{')]
assert rows == sorted(rows) and len(dict(rows)) == len(rows)
formats = re.compile(r'%(?:[-+ #0]*\d*(?:\.\d+)?(?:hh|ll|[hljztL])?[diuoxXfFeEgGaAcspn%])')
extra = {0x102,0x103,0x110,0x111,0x128,0x129,0x168,0x169,0x1a0,0x1a1,0x1af,0x1b0}
for english, vietnamese in rows:
    assert formats.findall(english) == formats.findall(vietnamese), english
    assert unicodedata.normalize('NFC', vietnamese) == vietnamese
    assert all(ord(c) < 256 or 0x1ea0 <= ord(c) <= 0x1ef9 or ord(c) in extra for c in vietnamese), english

code = r'''
#include "config_store.h"
#include "ui/habitat/pro_i18n.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define ESP_LOGI(...) ((void)0)
typedef int nvs_handle_t;
enum {ESP_OK, NVS_READONLY, NVS_READWRITE};
static const char *NS="pair";
static char durable[8], pending[8];
static bool opened, writable, fail_open, fail_get, fail_set, fail_commit;
static unsigned writes, commits;
static int nvs_open(const char *ns,int mode,nvs_handle_t *h) {
    assert(!opened&&!strcmp(ns,NS));if(fail_open)return -1;
    opened=true;writable=mode==NVS_READWRITE;*h=1;strcpy(pending,durable);return ESP_OK;
}
static int nvs_get_str(nvs_handle_t h,const char *key,char *out,size_t *cap) {
    assert(opened&&h==1&&!strcmp(key,"vlang"));
    if(fail_get||!durable[0]||strlen(durable)>=*cap)return -1;
    strcpy(out,durable);*cap=strlen(durable)+1;return ESP_OK;
}
static int nvs_set_str(nvs_handle_t h,const char *key,const char *value) {
    assert(opened&&writable&&h==1&&!strcmp(key,"vlang"));writes++;
    if(fail_set)return -1;snprintf(pending,sizeof pending,"%s",value);return ESP_OK;
}
static int nvs_commit(nvs_handle_t h) {
    assert(opened&&writable&&h==1);commits++;
    if(fail_commit)return -1;strcpy(durable,pending);return ESP_OK;
}
static void nvs_close(nvs_handle_t h) {assert(opened&&h==1);opened=false;}
'''
code += function('read_str') + function('config_load_voicelang') + function('config_save_voicelang')
code += r'''
int main(void) {
    char lang[CFG_VLANG_MAX];
    config_load_voicelang(lang,sizeof lang);assert(!strcmp(lang,"en")&&!writes);
    for(int i=0;i<10;i++) {
        const char *want=i&1 ? "en" : "vi";
        assert(config_save_voicelang(want));
        memset(lang,0xa5,sizeof lang);config_load_voicelang(lang,sizeof lang);
        assert(!strcmp(lang,want)&&!opened);
    }
    assert(config_save_voicelang("vi"));
    unsigned before=commits;
    fail_open=true;assert(!config_save_voicelang("en"));assert(commits==before&&!opened);fail_open=false;
    fail_set=true;assert(!config_save_voicelang("en"));assert(commits==before&&!opened);fail_set=false;
    fail_commit=true;assert(!config_save_voicelang("en"));assert(!opened);fail_commit=false;
    config_load_voicelang(lang,sizeof lang);assert(!strcmp(lang,"vi"));
    fail_get=true;config_load_voicelang(lang,sizeof lang);assert(!strcmp(lang,"en")&&!opened);fail_get=false;
    assert(config_save_voicelang("en"));config_load_voicelang(lang,sizeof lang);assert(!strcmp(lang,"en"));
    assert(!strcmp(pro_translate("vi","Language"),"Ngôn ngữ"));
    assert(!strcmp(pro_translate("en","Language"),"Language"));
    assert(!strcmp(pro_translate("xx","Language"),"Language"));
    assert(!strcmp(pro_translate("vi","My custom message"),"My custom message"));
    assert(pro_translate("vi",NULL)==NULL);
    puts("Pro language: persisted en/vi, NVS failures/retry, catalog formats and glyph coverage PASS");
}
'''
with tempfile.TemporaryDirectory(prefix='pro-language-') as folder:
    out = Path(folder)
    (out/'test.c').write_text(code)
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-O1','-g',
                    '-fsanitize='+os.environ.get('SANITIZERS','undefined,bounds'),
                    '-I',str(MAIN),str(out/'test.c'),'-o',str(out/'test')],check=True)
    subprocess.run([str(out/'test')],check=True)
