"""Pro speech JSON/binary contract and bounded credit; no serial port or codec.

Uses the production protocol and real cJSON. Audio/UI mocks are explicit local
boundaries; real ring/codec/preemption behavior is tested by test_audio_speech.
"""
from pathlib import Path
import os
import subprocess
import tempfile
from native_shapes import defines

MAIN = Path(__file__).resolve().parent / "../main"
SOURCE = (MAIN / "cable_speech.c").read_text()
JSON = Path(os.environ["IDF_PATH"]) / "components/json/cJSON"
code = r'''
#include "cJSON.h"
#include "audio_speech.h"
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#define ID_MAX 48
#define CABLE_TYPE_JSON 1
static audio_speech_state_t audio;
static bool connected=true, ui_accept=true, audio_accept=true, wire_accept=true;
static uint32_t ui_id, begin_id, begin_rate, pushed_id, pushed_offset, end_id, end_bytes;
static uint8_t begin_volume, first_pcm;
static size_t pushed_bytes;
static unsigned begins,pushes,ends,aborts,ui_begins,ui_clears,sends;
static int64_t now;
static char wire[2048], caption_seen[1025], agent_seen[ID_MAX];
static size_t alloc_count,free_count,live,fail_at;
static void *allocate(size_t size) {
    if (++alloc_count==fail_at) return NULL;
    void *p=malloc(size); if(p) live++; return p;
}
static void release(void *p) { if(p) { assert(live); live--; free_count++; free(p); } }
static int64_t esp_timer_get_time(void) { return now; }
static bool cable_client_is_connected(void) { return connected; }
static bool cable_link_send(uint8_t type,const uint8_t *data,size_t bytes) {
    assert(type==CABLE_TYPE_JSON && bytes<sizeof wire); sends++;
    memcpy(wire,data,bytes); wire[bytes]=0; return wire_accept;
}
void audio_speech_snapshot(audio_speech_state_t *out) { *out=audio; }
bool audio_speech_begin(uint32_t id,uint32_t rate,uint8_t volume) {
    begins++; begin_id=id; begin_rate=rate; begin_volume=volume;
    if (!audio_accept) return false;
    audio=(audio_speech_state_t){.id=id,.active=true,.pending=true}; return true;
}
bool audio_speech_push(uint32_t id,uint32_t offset,const void *pcm,size_t bytes) {
    pushes++; pushed_id=id; pushed_offset=offset; pushed_bytes=bytes;
    if (!audio_accept || !audio.active || id!=audio.id || offset!=audio.received ||
        (bytes&1) || bytes>AUDIO_SPEECH_CAPACITY-audio.queued) return false;
    first_pcm=((const uint8_t *)pcm)[0]; audio.received+=(uint32_t)bytes;
    audio.queued=audio.received-audio.consumed; return true;
}
bool audio_speech_end(uint32_t id,uint32_t bytes) {
    ends++; end_id=id; end_bytes=bytes;
    if (!audio_accept || id!=audio.id || bytes!=audio.received || (bytes&1)) return false;
    audio.ended=true; return true;
}
void audio_speech_abort(uint32_t id) {
    aborts++;
    if (!id || id==audio.id) {
        audio.active=audio.pending=false; audio.queued=0; audio.error=AUDIO_SPEECH_ERROR_ABORTED;
    }
}
static bool ui_companion_speech_begin(uint32_t id,const char *agent,const char *caption,const char *emotion) {
    (void)emotion; ui_begins++; snprintf(agent_seen,sizeof agent_seen,"%s",agent);
    snprintf(caption_seen,sizeof caption_seen,"%s",caption); if(ui_accept)ui_id=id; return ui_accept;
}
static void ui_companion_speech_clear(uint32_t id) { ui_clears++; if(!id || id==ui_id)ui_id=0; }
'''
code = code.replace("#define ID_MAX 48", defines("ID_MAX").strip())
code += SOURCE[SOURCE.index("#define WIRE_WINDOW"):].rsplit("#endif", 1)[0]
code += r'''
static void reset(void) {
    audio=(audio_speech_state_t){0}; reported=(audio_speech_state_t){0}; reported_at=0; remote_id=0; now=1000000;
    connected=ui_accept=audio_accept=wire_accept=true; ui_id=0;
    begins=pushes=ends=aborts=ui_begins=ui_clears=sends=0;
    wire[0]=caption_seen[0]=agent_seen[0]=0; fail_at=0;
}
static cJSON *begin_request(void) {
    cJSON *p=cJSON_Parse("{\"id\":100,\"sr\":16000,\"volume\":60,\"agentId\":\"pane-a\",\"caption\":\"A little progress.\",\"emotion\":\"pleased\"}");
    assert(p); return p;
}
static double number(const char *key) {
    cJSON *p=cJSON_Parse(wire); assert(p); cJSON *v=cJSON_GetObjectItemCaseSensitive(p,key);
    assert(cJSON_IsNumber(v)); double value=v->valuedouble; cJSON_Delete(p); return value;
}
static void uint_validation(void) {
    const double values[]={-1,-0.5,0.5,4294967296.0,INFINITY,-INFINITY,NAN};
    for (unsigned i=0;i<sizeof values/sizeof values[0];i++) {
        reset(); cJSON *p=begin_request();
        // Test uint_of against hostile numeric nodes without asking cJSON's
        // unrelated valueint conversion to cast NaN to int (it is undefined).
        cJSON_GetObjectItemCaseSensitive(p,"id")->valuedouble=values[i];
        assert(cable_speech_message("speech.begin",p)); assert(!begins && sends==1 && number("error")==100);
        cJSON_Delete(p);
    }
    reset(); cJSON *p=begin_request(); cJSON_ReplaceItemInObjectCaseSensitive(p,"id",cJSON_CreateString("100"));
    assert(cable_speech_message("speech.begin",p) && !begins); cJSON_Delete(p);
    reset(); p=begin_request(); cJSON_SetNumberValue(cJSON_GetObjectItemCaseSensitive(p,"id"),4294967295.0);
    assert(cable_speech_message("speech.begin",p) && begins==1 && begin_id==UINT32_MAX);
    assert(number("id")==4294967295.0 && number("credit")==8192); cJSON_Delete(p);
}
static void begin_bounds(void) {
    for (int fault=0;fault<9;fault++) {
        reset(); cJSON *p=begin_request();
        char wide[1026]; memset(wide,'x',sizeof wide-1); wide[sizeof wide-1]=0;
        if(fault==0) cJSON_DeleteItemFromObjectCaseSensitive(p,"sr");
        if(fault==1) cJSON_SetNumberValue(cJSON_GetObjectItemCaseSensitive(p,"volume"),101);
        if(fault==2) cJSON_SetNumberValue(cJSON_GetObjectItemCaseSensitive(p,"volume"),-1);
        if(fault==3) cJSON_SetValuestring(cJSON_GetObjectItemCaseSensitive(p,"caption"),"");
        if(fault==4) cJSON_SetValuestring(cJSON_GetObjectItemCaseSensitive(p,"caption"),wide);
        if(fault==5) cJSON_SetValuestring(cJSON_GetObjectItemCaseSensitive(p,"agentId"),"");
        if(fault==6) { wide[ID_MAX]=0; cJSON_SetValuestring(cJSON_GetObjectItemCaseSensitive(p,"agentId"),wide); }
        if(fault==7) cJSON_SetNumberValue(cJSON_GetObjectItemCaseSensitive(p,"id"),0);
        if(fault==8) connected=false;
        assert(cable_speech_message("speech.begin",p) && !begins && !ui_begins);
        cJSON_Delete(p);
    }
    reset(); cJSON *p=begin_request();
    char exact[1025]; memset(exact,'W',1024); exact[1024]=0;
    cJSON_SetValuestring(cJSON_GetObjectItemCaseSensitive(p,"caption"),exact);
    assert(cable_speech_message("speech.begin",p) && begins==1 && ui_begins==1);
    assert(begin_rate==16000 && begin_volume==60 && strlen(caption_seen)==1024 && !strcmp(agent_seen,"pane-a"));
    assert(number("credit")==8192); cJSON_Delete(p);
    reset(); p=begin_request(); audio_accept=false;
    assert(cable_speech_message("speech.begin",p) && begins==1 && !ui_begins && number("error")==102);
    cJSON_Delete(p);
    reset(); p=begin_request(); ui_accept=false;
    assert(cable_speech_message("speech.begin",p) && aborts==1 && !audio.active && number("error")==101);
    cJSON_Delete(p);
}
static void put32(uint8_t *out,uint32_t n) { for(unsigned i=0;i<4;i++)out[i]=(uint8_t)(n>>(8*i)); }
static void pcm_and_sessions(void) {
    reset(); uint8_t p[20]={0}; put32(p,100); p[8]=0x9a;
    audio=(audio_speech_state_t){.id=100,.active=true,.pending=true}; ui_id=100; remote_id=100;
    for(size_t size=0;size<10;size++)cable_speech_pcm(p,size);
    assert(!pushes && !sends);
    cable_speech_pcm(p,10); assert(pushes==1 && pushed_id==100 && pushed_offset==0 && pushed_bytes==2 && first_pcm==0x9a);
    assert(audio.received==2);
    put32(p+4,2); cable_speech_pcm(p,11);
    assert(pushes==2 && aborts==1 && !audio.active && !ui_id && number("error")==100);
    reset(); audio=(audio_speech_state_t){.id=200,.active=true,.received=100,.queued=100}; ui_id=200; remote_id=200;
    put32(p,100); put32(p+4,0); cable_speech_pcm(p,10);
    assert(aborts==0 && audio.active && audio.id==200 && ui_id==200 && number("id")==100);
    reset(); connected=false; cable_speech_pcm(p,20); assert(!pushes && !aborts);
    reset(); audio=(audio_speech_state_t){.id=0x87654321,.active=true}; remote_id=0x87654321;
    put32(p,0x87654321); put32(p+4,0x12345678); cable_speech_pcm(p,10);
    assert(pushed_id==0x87654321 && pushed_offset==0x12345678);
    assert(!audio.active && number("error")==100);
}
static void terminal_lifecycle(void) {
    reset(); audio=(audio_speech_state_t){.id=100,.active=true,.received=640,.queued=640}; ui_id=100; remote_id=100;
    cJSON *p=cJSON_Parse("{\"id\":100,\"bytes\":640}"); assert(p);
    assert(cable_speech_message("speech.end",p) && ends==1 && end_id==100 && end_bytes==640);
    assert(audio.active && audio.ended && ui_id==100 && !aborts); // captions survive the DMA drain.
    cJSON_SetNumberValue(cJSON_GetObjectItemCaseSensitive(p,"id"),99);
    assert(cable_speech_message("speech.end",p) && audio.active && ui_id==100);
    cJSON_SetNumberValue(cJSON_GetObjectItemCaseSensitive(p,"id"),100);
    assert(cable_speech_message("speech.abort",p) && !audio.active && !ui_id);
    cJSON_Delete(p);
    reset(); audio=(audio_speech_state_t){.id=200,.active=true}; ui_id=200; remote_id=200;
    p=cJSON_CreateObject(); assert(!cable_speech_message("agent.focus",p) && !aborts);
    assert(!cable_speech_message("fw.offer",p) && aborts==1 && !audio.active && !ui_id);
    cJSON_Delete(p);
    reset(); audio=(audio_speech_state_t){.id=300,.active=true}; ui_id=300; remote_id=300;
    cable_speech_disconnect(); assert(aborts==1 && !audio.active && !ui_id && !reported.id);
}
static void credit_and_report_retry(void) {
    reset();
    const uint32_t queue[]={0,2,4096,57344,60000,65534,65536};
    for(unsigned i=0;i<sizeof queue/sizeof queue[0];i++) {
        audio=(audio_speech_state_t){.id=100+i,.active=true,.received=queue[i]+1234,.consumed=1234,.queued=queue[i]};
        assert(report(&audio,0));
        uint32_t credit=(uint32_t)number("credit");
        uint32_t room=AUDIO_SPEECH_CAPACITY-queue[i]; if(room>8192)room=8192;
        assert(credit==audio.received+room && credit<=audio.consumed+AUDIO_SPEECH_CAPACITY);
        audio.ended=true; assert(report(&audio,0) && number("credit")==audio.received);
        audio.ended=false; audio.active=false; assert(report(&audio,0) && number("credit")==audio.received);
    }
    const uint32_t near_limit[]={AUDIO_SPEECH_MAX_BYTES-8194,AUDIO_SPEECH_MAX_BYTES-8192,
        AUDIO_SPEECH_MAX_BYTES-2,AUDIO_SPEECH_MAX_BYTES};
    for(unsigned i=0;i<sizeof near_limit/sizeof near_limit[0];i++) {
        audio=(audio_speech_state_t){.id=200+i,.active=true,.received=near_limit[i],
            .consumed=near_limit[i]-1000,.queued=1000};
        assert(report(&audio,0)); uint32_t credit=(uint32_t)number("credit");
        assert(credit<=AUDIO_SPEECH_MAX_BYTES && credit>=audio.received);
        assert(credit==audio.received+(AUDIO_SPEECH_MAX_BYTES-audio.received<8192 ? AUDIO_SPEECH_MAX_BYTES-audio.received : 8192));
    }
    reset(); audio=(audio_speech_state_t){.id=100,.active=true,.pending=true}; wire_accept=false; remote_id=100;
    cable_speech_tick(); assert(sends==1 && !reported.id);
    wire_accept=true; cable_speech_tick(); assert(sends==2 && reported.id==100);
    // Receipt ACKs unblock the very next frame, including a burst within 40 ms.
    for(unsigned i=1;i<=4;i++) {
        audio.received=i*2048; audio.queued=audio.received; now+=100;
        cable_speech_tick(); assert(sends==2+i && reported.received==audio.received);
        assert(number("received")==i*2048);
    }
    audio.playing=true; audio.pending=false; now++; cable_speech_tick(); assert(sends==7);
    // Progress alone is still bounded to 25 Hz; it must not delay an ACK.
    audio.consumed=640; audio.queued-=640; now+=39999; cable_speech_tick(); assert(sends==7);
    now++; cable_speech_tick(); assert(sends==8 && reported.consumed==640);
    now+=40000; cable_speech_tick(); assert(sends==8);
    audio.active=false; audio.error=AUDIO_SPEECH_ERROR_CAPTURE; cable_speech_tick();
    assert(sends==9 && number("error")==AUDIO_SPEECH_ERROR_CAPTURE);
}
static void allocation_failure_is_atomic(void) {
    reset(); audio=(audio_speech_state_t){.id=100,.active=true,.received=640,.consumed=320,.queued=320};
    size_t before=alloc_count; assert(report(&audio,0)); size_t count=alloc_count-before;
    assert(!live);
    for(size_t i=1;i<=count;i++) {
        sends=0; fail_at=alloc_count+i; assert(!report(&audio,0));
        assert(!sends && !live); fail_at=0;
    }
    wire_accept=false; assert(!report(&audio,0) && !live);
}
static void local_audition_is_independent(void) {
    reset(); audio=(audio_speech_state_t){.id=0x564f0001,.active=true,.playing=true};
    cable_speech_tick(); assert(!sends);
    cable_speech_disconnect(); assert(!aborts && audio.active && !ui_clears);
    cJSON *p=cJSON_Parse("{\"id\":1448017921}");assert(p);
    assert(cable_speech_message("speech.abort",p));assert(!aborts && audio.active);
    cJSON_Delete(p);
    remote_id=100;ui_id=100;
    cable_speech_disconnect();assert(aborts==1&&audio.active&&ui_id==0);
}
int main(void) {
    const cJSON_Hooks hooks={allocate,release}; cJSON_InitHooks((cJSON_Hooks *)&hooks);
    local_audition_is_independent(); uint_validation(); begin_bounds(); pcm_and_sessions(); terminal_lifecycle();
    credit_and_report_retry(); allocation_failure_is_atomic(); assert(!live);
    puts("Pro speech protocol: uint32/JSON bounds, caption limits, LE packet routing, stale-session isolation, end/drain lifecycle, bounded credit, throttling/retry and every report allocation failure PASS (offline)");
}
'''
with tempfile.TemporaryDirectory(prefix="harness-cable-speech-") as folder:
    out = Path(folder)
    (out / "speech.c").write_text(code)
    flags = [os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror", "-O1", "-g",
             "-DDEVICE_PRO_COMPANION=1", "-fno-sanitize-recover=all",
             "-fsanitize=" + os.environ.get("SANITIZERS", "undefined,bounds")]
    subprocess.run(flags + ["-Wno-deprecated-declarations", "-c", str(JSON / "cJSON.c"), "-o", str(out / "cJSON.o")], check=True)
    subprocess.run(flags + ["-I", str(MAIN), "-I", str(JSON), str(out / "speech.c"), str(out / "cJSON.o"),
                            "-lm", "-o", str(out / "speech")], check=True)
    subprocess.run([str(out / "speech")], check=True, timeout=30)
