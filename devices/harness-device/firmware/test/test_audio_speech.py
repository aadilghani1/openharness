"""Bounded Pro PCM playback, credit, preemption and shared-codec races; no hardware.

Compiles the production streaming implementation and capture start/stop. A
deterministic I2S sink verifies exact bytes/offsets, while one pthread test
preempts a real in-flight worker write with the production capture entry point.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

MAIN = Path(__file__).resolve().parent / "../main"
SOURCE = (MAIN / "audio_capture.c").read_text()


def function(name):
    match = re.search(r"^[^\n]*\b" + name + r"\([^;]*?\)\n\{.*?^\}", SOURCE, re.M | re.S)
    assert match, name
    return match.group(0) + "\n"


code = r'''
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "audio_capture.h"
#include "audio_speech.h"
#define ESP_OK 0
#define ESP_CODEC_DEV_OK 0
#define ESP_ERR_TIMEOUT 1
#define ESP_ERR_INVALID_STATE 2
#define ESP_FAIL 3
#define pdTRUE 1
#define pdPASS 1
#define pdMS_TO_TICKS(x) (x)
#define portMAX_DELAY UINT32_MAX
#define MALLOC_CAP_SPIRAM 1
#define MALLOC_CAP_8BIT 2
#define ESP_LOGI(...) test_log(__VA_ARGS__)
#define ESP_LOGW(...) test_log(__VA_ARGS__)
#define ESP_LOGE(...) ((void)0)
typedef int esp_err_t;
typedef void *TaskHandle_t;
typedef pthread_mutex_t portMUX_TYPE;
#define portMUX_INITIALIZER_UNLOCKED PTHREAD_MUTEX_INITIALIZER
static _Thread_local unsigned critical_depth;
static const char *TAG="audio_test";
static void test_log(const char *tag,const char *format,...) {
    (void)tag; assert(!critical_depth);
    char line[512]; va_list ap; va_start(ap,format); vsnprintf(line,sizeof line,format,ap); va_end(ap);
}
#define portENTER_CRITICAL(m) do { assert(!critical_depth); pthread_mutex_lock(m); critical_depth++; } while(0)
#define portEXIT_CRITICAL(m) do { assert(critical_depth==1); critical_depth--; pthread_mutex_unlock(m); } while(0)
typedef struct { int sample_rate,channel,bits_per_sample; } esp_codec_dev_sample_info_t;
static pthread_mutex_t codec = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t *s_codec_lock = &codec;
#define BSP_PA_IO 54
static struct { struct { uint32_t val; } out1,enable1; } GPIO = {{1u<<22},{1u<<22}};
typedef struct test_ctrl test_ctrl_t;
struct test_ctrl { int (*read_reg)(const test_ctrl_t *,int,int,void *,int); };
static unsigned register_reads;
static bool register_read_fail;
static int test_read_reg(const test_ctrl_t *ctrl,int reg,int reg_size,void *out,int out_size);
static const test_ctrl_t ctrl = {.read_reg=test_read_reg};
static const test_ctrl_t *s_spk_ctrl=&ctrl;
static int s_spk=1,s_mic=2,s_tx=3,s_rx=4;
static void *s_beep_task=(void *)2;
static bool s_open;
static atomic_bool s_capture_requested, s_speech_requested;
static atomic_uint s_rx_overruns, notifications, codec_held, in_write;
static atomic_bool open_entered, allow_open;
static atomic_llong clock_us;
static unsigned opens,closes,writes,mic_opens,mic_closes,beep_writes,volume_set;
static bool change_volume;
static unsigned allocations, frees, task_creates, notify_inits;
static bool muted, alloc_fail, task_fail, speaker_fail, open_fail, volume_fail, write_fail;
static bool short_write, no_progress, abort_copy, feed_wrap, feed_limit, end_on_write, replace_on_write, hold_open;
static unsigned abort_after, capture_after, real_write_delay;
static uint8_t sink[AUDIO_SPEECH_MAX_BYTES], input[AUDIO_SPEECH_MAX_BYTES];
static size_t sink_length;
static void pause_ms(unsigned ms) {
    struct timespec delay={.tv_sec=ms/1000,.tv_nsec=(long)(ms%1000)*1000000};
    nanosleep(&delay,NULL);
}
static int test_read_reg(const test_ctrl_t *control,int reg,int reg_size,void *out,int out_size) {
    assert(control==&ctrl && reg_size==1 && out_size==1 && !critical_depth && atomic_load(&codec_held)==1);
    assert(reg==0x09 || reg==0x0d || reg==0x12 || reg==0x31 || reg==0x32 || reg==0x44);
    register_reads++; *(uint8_t *)out=(uint8_t)reg;
    return register_read_fail ? ESP_FAIL : ESP_CODEC_DEV_OK;
}
static int64_t esp_timer_get_time(void) { return atomic_load(&clock_us); }
static const char *esp_err_to_name(int error) { (void)error; return "test"; }
bool audio_notify_is_muted(void) { return muted; }
void audio_notify_init(void) { notify_inits++; if (!speaker_fail) s_spk=1; }
bool audio_capture_init(void) { return true; }
static void *heap_caps_malloc(size_t bytes, unsigned caps) {
    assert(bytes==AUDIO_SPEECH_CAPACITY && caps==3 && !critical_depth);
    if (alloc_fail) return NULL;
    allocations++; return malloc(bytes);
}
static void heap_caps_free(void *p) { assert(p); frees++; free(p); }
static int xTaskCreate(void (*fn)(void *),const char *name,int stack,void *arg,int priority,void **out) {
    (void)fn; (void)arg; assert(!strcmp(name,"speech") && stack==4096 && priority==5 && !critical_depth);
    task_creates++; if (task_fail) return 0; *out=(void *)1; return pdPASS;
}
static void xTaskNotifyGive(void *task) { assert(task && !critical_depth); atomic_fetch_add(&notifications,1); }
static uint32_t ulTaskNotifyTake(bool clear,uint32_t ticks) {
    assert(clear && !critical_depth && ticks!=portMAX_DELAY);
    unsigned n=atomic_exchange(&notifications,0);
    if (!n) atomic_fetch_add(&clock_us,(int64_t)ticks*1000);
    return n;
}
static bool xSemaphoreTake(pthread_mutex_t *lock,uint32_t ticks) {
    assert(lock==&codec && !critical_depth);
    int rc=ticks==portMAX_DELAY ? pthread_mutex_lock(lock) : pthread_mutex_trylock(lock);
    if (rc) { atomic_fetch_add(&clock_us,(int64_t)ticks*1000); return false; }
    assert(atomic_fetch_add(&codec_held,1)==0); return true;
}
static void xSemaphoreGive(pthread_mutex_t *lock) {
    assert(lock==&codec && !critical_depth && atomic_fetch_sub(&codec_held,1)==1);
    pthread_mutex_unlock(lock);
}
static int esp_codec_dev_open(int device,const esp_codec_dev_sample_info_t *fs) {
    assert(atomic_load(&codec_held)==1 && !critical_depth);
    assert(fs->sample_rate==16000 && fs->channel==1 && fs->bits_per_sample==16);
    if (device==s_mic) { mic_opens++; assert(closes==opens); return 0; }
    assert(device==s_spk); opens++;
    if (hold_open) {
        atomic_store(&open_entered,true);
        while (!atomic_load(&allow_open)) pause_ms(1);
    }
    return open_fail ? ESP_FAIL : 0;
}
static int esp_codec_dev_set_out_vol(int device,int volume) {
    assert(device==s_spk && atomic_load(&codec_held)==1 && volume>=0 && volume<=100 && !critical_depth);
    volume_set=(unsigned)volume; return volume_fail ? ESP_FAIL : 0;
}
static int esp_codec_dev_close(int device) {
    assert(atomic_load(&codec_held)==1 && !critical_depth);
    if (device==s_mic) mic_closes++; else { assert(device==s_spk); closes++; }
    return 0;
}
static int i2s_channel_enable(int device) { assert(device==s_rx); return 0; }
static void esp_codec_dev_set_in_gain(int device,double gain) { assert(device==s_mic && gain==37.5); }
static int esp_codec_dev_write(int device,void *pcm,int bytes) {
    (void)pcm; assert(device==s_spk && bytes>0 && atomic_load(&codec_held)==1); beep_writes++; return 0;
}
static esp_err_t i2s_channel_write(int device,const void *pcm,size_t bytes,size_t *written,uint32_t timeout) {
    assert(device==s_tx && atomic_load(&codec_held)==1 && !critical_depth);
    assert(bytes>0 && bytes<=640 && !(bytes&1) && timeout==20);
    writes++; atomic_store(&in_write,1);
    if(change_volume && writes==2) { assert(audio_speech_set_volume(100,80));assert(!audio_speech_set_volume(101,20));assert(!audio_speech_set_volume(100,101)); }
    if (real_write_delay) pause_ms(real_write_delay);
    *written=0;
    if (write_fail) return ESP_FAIL;
    if (no_progress) { atomic_fetch_add(&clock_us,20000); return ESP_ERR_TIMEOUT; }
    if (short_write && bytes>2) bytes=bytes>126 ? 126 : bytes-2;
    assert(sink_length+bytes<=sizeof sink);
    memcpy(sink+sink_length,pcm,bytes); sink_length+=bytes; *written=bytes;
    atomic_fetch_add(&clock_us,(int64_t)bytes*1000000/32000);
    if (feed_wrap && writes==10) {
        assert(audio_speech_push(100,65536,input+65536,4096));
        assert(audio_speech_end(100,69632)); feed_wrap=false;
    }
    if (feed_limit && writes%8==0) {
        audio_speech_state_t s; audio_speech_snapshot(&s);
        uint32_t n=AUDIO_SPEECH_CAPACITY-s.queued;
        if(n>AUDIO_SPEECH_MAX_BYTES-s.received)n=AUDIO_SPEECH_MAX_BYTES-s.received;
        assert(n && audio_speech_push(100,s.received,input+s.received,n));
        if(s.received+n==AUDIO_SPEECH_MAX_BYTES) {
            assert(!audio_speech_push(100,AUDIO_SPEECH_MAX_BYTES,input,2));
            assert(audio_speech_end(100,AUDIO_SPEECH_MAX_BYTES)); feed_limit=false;
        }
    }
    if (end_on_write) { end_on_write=false; assert(audio_speech_end(100,1280)); }
    if (abort_after && writes==abort_after) audio_speech_abort(100);
    if (capture_after && writes==capture_after) {
        atomic_store(&s_capture_requested,true); audio_speech_abort(0);
    }
    if (replace_on_write) {
        replace_on_write=false; audio_speech_abort(100);
        assert(!audio_speech_begin(101,16000,60));
    }
    return short_write ? ESP_ERR_TIMEOUT : ESP_OK;
}
static void *test_memcpy(void *dst,const void *src,size_t count);
#undef memcpy
#define memcpy test_memcpy
'''
code += "#define SPEECH_BLOCK_BYTES" + SOURCE.split("#define SPEECH_BLOCK_BYTES", 1)[1].rsplit("#endif", 1)[0]
# Keep the entire production block intact, including its constants and worker.
assert "#define SPEECH_BLOCK_BYTES" in code
code += "\n#undef memcpy\n"
code += function("audio_capture_start") + function("audio_capture_stop")
for line in SOURCE.splitlines():
    if re.match(r"#define (BEEP_|GAP_|TONE_)", line) or line.startswith("static int16_t s_tone["):
        code += line + "\n"
code += function("render_tone") + function("play_beep")
code += r'''
static void *test_memcpy(void *dst,const void *src,size_t count) {
    assert(!critical_depth);
    void *result=memcpy(dst,src,count);
    uintptr_t d=(uintptr_t)dst, first=(uintptr_t)s_speech_pcm;
    if (abort_copy && d>=first && d<first+AUDIO_SPEECH_CAPACITY) {
        abort_copy=false; audio_speech_abort(100);
        assert(!audio_speech_begin(101,16000,60));
    }
    return result;
}
static audio_speech_state_t state(void) { audio_speech_state_t s; audio_speech_snapshot(&s); return s; }
static void reset(void) {
    assert(!atomic_load(&codec_held) && !s_speech_worker && !s_speech_producer);
    s_speech=(audio_speech_state_t){0}; s_speech_generation++;
    atomic_store(&s_capture_requested,false); atomic_store(&s_speech_requested,false);
    atomic_store(&clock_us,0); atomic_store(&notifications,0); atomic_store(&in_write,0);
    atomic_store(&open_entered,false); atomic_store(&allow_open,false); hold_open=false;
    change_volume=false; s_open=false; muted=open_fail=volume_fail=write_fail=short_write=no_progress=false;
    abort_copy=feed_wrap=feed_limit=end_on_write=replace_on_write=false;
    abort_after=capture_after=real_write_delay=0;
    opens=closes=writes=mic_opens=mic_closes=beep_writes=volume_set=0; sink_length=0;
    register_reads=0; register_read_fail=false;
}
static void begin_bytes(size_t bytes,bool end) {
    assert(audio_speech_begin(100,16000,60));
    assert(audio_speech_push(100,0,input,bytes));
    if (end) assert(audio_speech_end(100,(uint32_t)bytes));
}
static void complete(size_t bytes) {
    audio_speech_state_t s=state();
    assert(s.id==100 && !s.active && !s.playing && !s.pending && !s.queued && !s.level);
    assert(s.error==AUDIO_SPEECH_ERROR_NONE && s.received==bytes && s.consumed==bytes);
    assert(sink_length==bytes && !memcmp(sink,input,bytes));
    assert(opens==1 && closes==1 && !atomic_load(&codec_held) && !atomic_load(&s_speech_requested));
    assert(register_reads==6 && GPIO.out1.val==(1u<<22) && GPIO.enable1.val==(1u<<22));
}
static void init_failures(void) {
    s_spk=0; speaker_fail=true; assert(!audio_speech_init() && !allocations && !audio_speech_available());
    speaker_fail=false; s_spk=1; alloc_fail=true; assert(!audio_speech_init() && !allocations && !audio_speech_available());
    alloc_fail=false; task_fail=true; assert(!audio_speech_init());
    assert(allocations==1 && frees==1 && !s_speech_pcm && !audio_speech_available());
    task_fail=false; assert(audio_speech_init() && audio_speech_available());
    unsigned before=allocations; assert(audio_speech_init() && allocations==before);
}
static void rejects_and_credit(void) {
    reset(); assert(!audio_speech_begin(0,16000,60)); assert(!audio_speech_begin(100,24000,60));
    assert(!audio_speech_begin(100,16000,101)); assert(audio_speech_begin(100,16000,60));
    assert(!audio_speech_begin(101,16000,60));
    assert(!audio_speech_push(99,0,input,640)); assert(!audio_speech_push(100,2,input,640));
    assert(!audio_speech_push(100,0,NULL,640)); assert(!audio_speech_push(100,0,input,1));
    assert(!audio_speech_push(100,0,input,0)); assert(!audio_speech_push(100,0,input,65538));
    assert(!audio_speech_push(100,UINT32_MAX-1,input,640));
    assert(!audio_speech_push(100,AUDIO_SPEECH_MAX_BYTES,input,2));
    assert(audio_speech_push(100,0,input,65536));
    audio_speech_state_t s=state(); assert(s.received==65536 && s.queued==65536 && !s.consumed);
    assert(!audio_speech_push(100,65536,input,2)); assert(!audio_speech_end(99,65536));
    assert(!audio_speech_end(100,65534)); assert(!audio_speech_end(100,65537));
    assert(audio_speech_end(100,65536)); assert(!audio_speech_end(100,65536));
    assert(!audio_speech_push(100,65536,input,2));
    assert(!opens && !writes); play_speech(); complete(65536);
    assert(!audio_speech_begin(100,16000,60)); assert(audio_speech_begin(101,16000,60));
    assert(!audio_speech_push(100,0,input,640)); audio_speech_abort(100); assert(state().active);
    audio_speech_abort(101); assert(!state().active && state().error==AUDIO_SPEECH_ERROR_ABORTED);
}
static void stream_wrap_and_short_writes(void) {
    reset(); begin_bytes(65536,false); feed_wrap=true; play_speech(); complete(69632);
    reset(); begin_bytes(65536,false); feed_limit=true; play_speech(); complete(AUDIO_SPEECH_MAX_BYTES);
    reset(); begin_bytes(4096,true); short_write=true; play_speech(); complete(4096);
    assert(writes>7);
    reset(); begin_bytes(1280,false); end_on_write=true; play_speech(); complete(1280);
    reset(); begin_bytes(640,true); register_read_fail=true; play_speech(); complete(640);
}
static void mute_volume_and_tail(void) {
    reset();begin_bytes(6400,true);change_volume=true;play_speech();complete(6400);assert(volume_set==80&&opens==1&&writes==10);
    reset(); muted=true; begin_bytes(640,true); play_beep(); assert(!opens && !beep_writes);
    play_speech(); complete(640); assert(volume_set==60);
    assert(esp_timer_get_time()>=150000); // 20ms audio plus the interruptible DMA drain.
    reset(); assert(audio_speech_begin(100,16000,0)); assert(audio_speech_end(100,0));
    play_speech(); assert(!state().active && !opens && !state().error);
}
static void cancellation_and_errors(void) {
    reset(); begin_bytes(4096,true); abort_after=1; play_speech();
    assert(writes==1 && closes==1 && !state().active && !state().queued && state().error==AUDIO_SPEECH_ERROR_ABORTED);
    reset(); begin_bytes(4096,true); capture_after=1; play_speech();
    assert(writes==1 && closes==1 && state().error==AUDIO_SPEECH_ERROR_CAPTURE);
    assert(!audio_speech_begin(101,16000,60)); assert(audio_capture_start() && s_open && mic_opens==1);
    audio_capture_stop(); assert(!s_open && !atomic_load(&codec_held));
    reset(); assert(audio_speech_begin(100,16000,60)); abort_copy=true;
    assert(!audio_speech_push(100,0,input,640)); assert(!state().received && !state().active);
    assert(audio_speech_begin(101,16000,60)); audio_speech_abort(0);
    reset(); begin_bytes(640,true); replace_on_write=true; play_speech();
    assert(audio_speech_begin(101,16000,60)); audio_speech_abort(0);
    reset(); begin_bytes(640,true); open_fail=true; play_speech();
    assert(opens==1 && closes==1 && !writes && state().error==AUDIO_SPEECH_ERROR_CODEC);
    reset(); begin_bytes(640,true); volume_fail=true; play_speech();
    assert(closes==1 && !writes && state().error==AUDIO_SPEECH_ERROR_CODEC);
    reset(); begin_bytes(640,true); write_fail=true; play_speech();
    assert(writes==1 && closes==1 && !state().consumed && state().error==AUDIO_SPEECH_ERROR_CODEC);
    reset(); begin_bytes(640,true); no_progress=true; play_speech();
    assert(writes==5 && closes==1 && state().error==AUDIO_SPEECH_ERROR_CODEC);
    reset(); assert(audio_speech_begin(100,16000,60)); atomic_store(&clock_us,5000000); play_speech();
    assert(!opens && !state().active && state().error==AUDIO_SPEECH_ERROR_TIMEOUT);
    reset(); begin_bytes(640,false); play_speech();
    assert(closes==1 && state().error==AUDIO_SPEECH_ERROR_TIMEOUT && !state().active);
}
static void *run_worker(void *arg) { (void)arg; play_speech(); return NULL; }
static void concurrent_burst_during_codec_open(void) {
    reset(); begin_bytes(2048,false); hold_open=true;
    pthread_t worker; assert(!pthread_create(&worker,NULL,run_worker,NULL));
    for (unsigned i=0;!atomic_load(&open_entered);i++) { assert(i<1000); pause_ms(1); }
    // Real USB startup: codec configuration is in flight while the other core
    // receives the rest of the initial 8 KiB credit window without pacing.
    for (uint32_t at=2048;at<8192;at+=2048)
        assert(audio_speech_push(100,at,input+at,2048));
    audio_speech_state_t s=state();
    assert(s.active && s.pending && !s.playing && s.received==8192 && !s.consumed && !s.error);
    assert(audio_speech_end(100,8192));
    atomic_store(&allow_open,true); assert(!pthread_join(worker,NULL)); complete(8192);
}
static void concurrent_capture_preempts(void) {
    reset(); begin_bytes(64000,true); real_write_delay=20;
    pthread_t worker; assert(!pthread_create(&worker,NULL,run_worker,NULL));
    for (unsigned i=0;!atomic_load(&in_write);i++) { assert(i<1000); pause_ms(1); }
    // Actual capture entry sets the request before blocking on the shared codec.
    assert(audio_capture_start()); assert(!pthread_join(worker,NULL));
    assert(writes==1 && closes==1 && mic_opens==1 && s_open);
    assert(state().error==AUDIO_SPEECH_ERROR_CAPTURE && !state().playing && !state().active);
    audio_capture_stop(); assert(mic_closes==1 && !atomic_load(&codec_held));
}
int main(void) {
    for (size_t i=0;i<sizeof input;i++) input[i]=(uint8_t)((i*31+i/251)&255);
    init_failures(); rejects_and_credit(); stream_wrap_and_short_writes();
    mute_volume_and_tail(); cancellation_and_errors(); concurrent_burst_during_codec_open(); concurrent_capture_preempts();
    audio_speech_abort(0); heap_caps_free(s_speech_pcm); s_speech_pcm=NULL; s_speech_task=NULL;
    assert(allocations==frees);
    puts("Pro speech: exact PCM/ring wrap, credit, stale/order/size rejection, partial writes, DMA tail, separate mute, init/error cleanup, abort-copy race, concurrent startup burst and capture preemption PASS (offline)");
}
'''

with tempfile.TemporaryDirectory(prefix="harness-pro-speech-") as folder:
    out = Path(folder)
    (out / "speech.c").write_text(code)
    subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-function", "-Wno-unused-variable", "-O1", "-g", "-pthread",
                    "-DDEVICE_PRO_COMPANION=1", "-DCONFIG_IDF_TARGET_ESP32P4=1", "-fno-sanitize-recover=all",
                    "-fsanitize=" + os.environ.get("SANITIZERS", "undefined,bounds"),
                    "-I", str(MAIN), str(out / "speech.c"), "-o", str(out / "speech")], check=True)
    subprocess.run([str(out / "speech")], check=True, timeout=30)
