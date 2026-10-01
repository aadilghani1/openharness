#include "pro_voice_samples.h"
#include "audio_speech.h"
#include <stdatomic.h>
#include <string.h>

extern const uint8_t pro_voice_pack_start[] __asm__("_binary_pro_voice_pack_start");
extern const uint8_t pro_voice_pack_end[] __asm__("_binary_pro_voice_pack_end");
#include "pro_voice_samples.inc"

static const int steps[89] = {
    7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,
    73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,
    449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,
    2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,
    7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,
    22385,24623,27086,29794,32767
};
static const int indices[8] = {-1,-1,-1,-1,2,4,6,8};

size_t pro_voice_decode(pro_voice_decoder_t *s, const uint8_t *data, uint32_t samples,
                        int16_t *out, size_t capacity)
{
    if (!s || !data || !out || s->index < 0 || s->index > 88 || s->position > samples) return 0;
    size_t n = samples - s->position;
    if (n > capacity) n = capacity;
    for (size_t i = 0; i < n; ++i) {
        unsigned code = data[s->position / 2];
        code = (s->position++ & 1) ? code & 15 : code >> 4;
        int step = steps[s->index], delta = step >> 3;
        if (code & 1) delta += step >> 2;
        if (code & 2) delta += step >> 1;
        if (code & 4) delta += step;
        s->predictor += code & 8 ? -delta : delta;
        if (s->predictor > 32767) s->predictor = 32767;
        if (s->predictor < -32768) s->predictor = -32768;
        s->index += indices[code & 7];
        if (s->index < 0) s->index = 0;
        if (s->index > 88) s->index = 88;
        out[i] = (int16_t)s->predictor;
    }
    return n;
}

unsigned pro_voice_sample_count(void) { return sizeof voice_samples / sizeof voice_samples[0]; }
const pro_voice_sample_t *pro_voice_sample(unsigned index)
{ return index < pro_voice_sample_count() ? &voice_samples[index] : NULL; }

// Only the renderer calls the player. The audio worker owns the actual codec.
// A 2 KiB scratch block feeds the existing bounded 64 KiB ring; no new task,
// file system, network, full-clip allocation, or work on the touch-down path.
static struct {
    pro_voice_progress_t progress;
    pro_voice_decoder_t decoder;
    const pro_voice_sample_t *sample;
    uint32_t id, deadline;
    uint8_t volume;
    bool begun, ended;
    int16_t pcm[1024];
} player;
static atomic_uint owned_id;
static uint32_t serial = 0x564f0000u;

bool pro_voice_sample_owns_audio(void) { return atomic_load(&owned_id) != 0; }
pro_voice_progress_t pro_voice_sample_progress(void) { return player.progress; }
void pro_voice_sample_volume(uint8_t volume)
{
    if (volume > 100) return;
    player.volume = volume;
    if (atomic_load(&owned_id) && player.begun) audio_speech_set_volume(player.id, volume);
}
void pro_voice_sample_stop(void)
{
    uint32_t id = atomic_exchange(&owned_id, 0);
    if (id) audio_speech_abort(id);
    if (player.progress.phase == PRO_VOICE_STARTING || player.progress.phase == PRO_VOICE_PLAYING)
        player.progress.phase = PRO_VOICE_STOPPED;
    player.progress.level = 0;
}
static void failed(const char *error)
{
    pro_voice_sample_stop();
    player.progress.phase = PRO_VOICE_ERROR;
    player.progress.error = error;
}
bool pro_voice_sample_play(unsigned index, uint8_t volume, uint32_t now)
{
    const pro_voice_sample_t *sample = pro_voice_sample(index);
    if (!sample || volume > 100) return false;
    pro_voice_sample_stop();
    memset(&player, 0, sizeof player);
    player.progress.sample = index;
    if (!audio_speech_available()) { failed("Speaker unavailable"); return false; }
    size_t bytes = (sample->samples + 1u) / 2u;
    size_t size = (size_t)(pro_voice_pack_end - pro_voice_pack_start);
    if (!sample->samples || sample->samples > AUDIO_SPEECH_MAX_BYTES / 2u ||
        sample->offset > size || bytes > size - sample->offset) {
        failed("Sample unavailable"); return false;
    }
    player.sample = sample;
    player.volume = volume;
    if (!++serial) ++serial;
    player.id = serial;
    player.deadline = now + 1500;
    player.progress.phase = PRO_VOICE_STARTING;
    player.progress.total = sample->samples * 2u;
    atomic_store(&owned_id, player.id);
    return true;
}
static int16_t gain(int16_t sample)
{
    // Table/interpolation of the existing 4x / 0.63-ceiling soft gain. No per-
    // sample floating-point tanh on the renderer. Every audition uses this same
    // gain; quieter emotions remain quieter rather than being RMS-normalised.
    unsigned magnitude = sample < 0 ? -(int)sample : sample;
    unsigned at = magnitude >> 7, fraction = magnitude & 127u;
    int value = voice_gain[at];
    if (fraction) value += ((voice_gain[at + 1] - value) * fraction + 64) / 128;
    return (int16_t)(sample < 0 ? -value : value);
}
void pro_voice_sample_tick(uint32_t now)
{
    if (!atomic_load(&owned_id)) return;
    audio_speech_state_t audio;
    audio_speech_snapshot(&audio);
    if (!player.begun) {
        if (audio_speech_begin(player.id, AUDIO_SPEECH_RATE, player.volume)) player.begun = true;
        else if ((int32_t)(now - player.deadline) >= 0) failed("Speaker busy. Tap Play again.");
        if (!player.begun) return;
        audio_speech_snapshot(&audio);
    }
    if (audio.id != player.id) { failed("Playback interrupted"); return; }
    player.progress.consumed = audio.consumed;
    player.progress.level = audio.level;
    if (!audio.active && !audio.playing) {
        if (audio.error == AUDIO_SPEECH_ERROR_NONE && audio.consumed == player.progress.total) {
            atomic_store(&owned_id, 0);
            player.progress.phase = PRO_VOICE_DONE;
            player.progress.level = 0;
        } else failed(audio.error == AUDIO_SPEECH_ERROR_CAPTURE ? "Microphone is in use" : "Playback interrupted");
        return;
    }
    if (audio.playing) player.progress.phase = PRO_VOICE_PLAYING;
    if (player.ended) return;
    // At most 128 ms of audio per 20 ms poll. Wait for room instead of logging
    // backpressure as an error; preserve the decoder if a concurrent abort wins.
    unsigned budget = 2;
    while (budget-- && audio.queued <= AUDIO_SPEECH_CAPACITY - sizeof player.pcm) {
        pro_voice_decoder_t decoder = player.decoder;
        size_t n = pro_voice_decode(&decoder, pro_voice_pack_start + player.sample->offset,
                                   player.sample->samples, player.pcm, 1024);
        if (!n) break;
        for (size_t i = 0; i < n; i++) player.pcm[i] = gain(player.pcm[i]);
        if (!audio_speech_push(player.id, player.decoder.position * 2u, player.pcm, n * 2u)) {
            failed("Playback interrupted"); return;
        }
        player.decoder = decoder;
        audio.queued += n * 2u;
    }
    if (player.decoder.position == player.sample->samples) {
        player.ended = audio_speech_end(player.id, player.progress.total);
        if (!player.ended) failed("Playback interrupted");
    }
}
