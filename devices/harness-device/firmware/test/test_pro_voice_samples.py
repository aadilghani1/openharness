"""Real offline player: codec oracle, all clips, bounded buffers, stop and live volume."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from native_voice import voice_assets

HERE=Path(__file__).resolve().parent
MAIN=HERE/'../main'
ASSETS=HERE/'../../prototype/pro-companion/voice-samples'
code=r'''
#include "pro_voice_samples.h"
#include "audio_speech.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
extern const unsigned char data[] __asm__("_binary_pro_voice_pack_start");
static audio_speech_state_t audio;
static unsigned begins, volume, max_queued, changes;
static bool available=true, busy;
bool audio_speech_available(void) { return available; }
bool audio_speech_begin(uint32_t id,uint32_t rate,uint8_t vol) {
    assert(rate==16000&&vol<=100);
    if(busy||audio.active||audio.playing)return false;
    begins++;volume=vol;audio=(audio_speech_state_t){.id=id,.active=true,.pending=true};return true;
}
bool audio_speech_set_volume(uint32_t id,uint8_t vol) {
    assert(vol<=100);if(audio.id!=id||!audio.active)return false;volume=vol;changes++;return true;
}
bool audio_speech_push(uint32_t id,uint32_t at,const void *pcm,size_t n) {
    assert(pcm&&n&&n<=2048&&!(n&1));
    assert(audio.active&&audio.id==id&&audio.received==at&&!audio.ended);
    assert(audio.queued+n<=65536);
    audio.received+=n;audio.queued+=n;
    if(audio.queued>max_queued)max_queued=audio.queued;
    audio.playing=true;audio.pending=false;return true;
}
bool audio_speech_end(uint32_t id,uint32_t n) { assert(audio.id==id&&audio.received==n);audio.ended=true;return true; }
void audio_speech_abort(uint32_t id) { if(!id||id==audio.id){audio.active=audio.playing=audio.pending=false;audio.queued=0;audio.error=AUDIO_SPEECH_ERROR_ABORTED;} }
void audio_speech_snapshot(audio_speech_state_t *out) { *out=audio; }
static void consume(void) {
    if(!audio.active)return;
    unsigned n=audio.queued<640?audio.queued:640;
    audio.queued-=n;audio.consumed+=n;
    if(audio.ended&&!audio.queued){audio.active=audio.playing=false;audio.error=0;}
}
int main(int argc,char **argv) {
    assert(argc==2);FILE *decoded=fopen(argv[1],"wb");assert(decoded);
    assert(pro_voice_sample_count()==16&&!pro_voice_sample(16));
    for(unsigned i=0;i<pro_voice_sample_count();i++) {
        const pro_voice_sample_t *clip=pro_voice_sample(i);
        pro_voice_decoder_t decoder={0};int16_t block[1024];
        while(decoder.position<clip->samples) {
            size_t capacity=decoder.position%7==0?1:1024;
            size_t n=pro_voice_decode(&decoder,data+clip->offset,clip->samples,block,capacity);
            assert(n&&n<=capacity);assert(fwrite(block,2,n,decoded)==n);
        }
        assert(!pro_voice_decode(&decoder,data+clip->offset,clip->samples,block,1024));
        memset(&audio,0,sizeof audio);unsigned start=begins;
        assert(pro_voice_sample_play(i,80,0));assert(pro_voice_sample_owns_audio());
        pro_voice_sample_tick(0);assert(audio.received&&begins==start+1&&volume==80);
        uint32_t id=audio.id;
        for(unsigned now=20;now<=14000&&pro_voice_sample_owns_audio();now+=20) {
            if(now==200){pro_voice_sample_volume(0);assert(volume==0&&audio.id==id);}
            if(now==400){pro_voice_sample_volume(80);assert(volume==80&&audio.id==id);}
            consume();pro_voice_sample_tick(now);
        }
        pro_voice_progress_t p=pro_voice_sample_progress();
        assert(p.phase==PRO_VOICE_DONE&&p.consumed==clip->samples*2u&&p.sample==i);
        assert(begins==start+1&&max_queued<=65536);
    }
    fclose(decoded);assert(changes==32);
    assert(pro_voice_sample_play(0,80,100));pro_voice_sample_tick(100);
    uint32_t old=audio.id;pro_voice_sample_stop();assert(!audio.active&&!pro_voice_sample_owns_audio());
    pro_voice_sample_tick(120);assert(audio.id==old&&!audio.active);
    assert(pro_voice_sample_play(1,40,200));pro_voice_sample_tick(200);assert(audio.id!=old&&volume==40);
    pro_voice_sample_stop();busy=true;assert(pro_voice_sample_play(1,80,0));
    pro_voice_sample_tick(1400);assert(pro_voice_sample_progress().phase==PRO_VOICE_STARTING);
    busy=false;pro_voice_sample_tick(1420);assert(audio.active);pro_voice_sample_stop();
    busy=true;assert(pro_voice_sample_play(1,80,0));pro_voice_sample_tick(1500);
    assert(pro_voice_sample_progress().phase==PRO_VOICE_ERROR&&!pro_voice_sample_owns_audio());
    busy=false;available=false;assert(!pro_voice_sample_play(1,80,0));assert(!pro_voice_sample_owns_audio());
    assert(pro_voice_sample_progress().phase==PRO_VOICE_ERROR&&pro_voice_sample_progress().sample==1);
    assert(!pro_voice_sample_play(999,80,0)&&!pro_voice_sample_play(0,101,0));
    puts("Offline voice: 16 complete clips, streaming decoder, bounded queue, instant start, live volume without restart, stop, retry and unavailable speaker PASS");
}
'''
with tempfile.TemporaryDirectory(prefix='pro-voice-samples-') as d:
    out=Path(d);(out/'test.c').write_text(code)
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-O1','-g','-fsanitize=address,undefined','-DDEVICE_PRO_COMPANION=1','-I',str(MAIN),str(out/'test.c'),*voice_assets(out),'-o',str(out/'test')],check=True)
    subprocess.run([str(out/'test'),str(out/'decoded.pcm')],check=True,timeout=20)
    pack=(ASSETS/'samples.pack').read_bytes()
    rows=json.loads((ASSETS/'samples.json').read_text())
    decoded=(out/'decoded.pcm').read_bytes()
    offset=0
    for row in rows:
        encoded=pack[row['adpcm_offset']:row['adpcm_offset']+row['adpcm_bytes']]
        assert hashlib.sha256(encoded).hexdigest()==row['adpcm_sha256']
        n=row['samples']*2
        # Golden PCM hashes were made by Python's independent audioop decoder.
        assert hashlib.sha256(decoded[offset:offset+n]).hexdigest()==row['decoded_sha256']
        offset+=n
    assert offset==len(decoded)
    print('All decoded samples match the independent IMA ADPCM oracle byte-for-byte')
