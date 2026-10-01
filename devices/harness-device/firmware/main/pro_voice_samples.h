#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    const char *id, *voice, *title, *model, *tag, *caption, *note, *voice_id;
    uint32_t offset, samples;
    int32_t seed; // -1 means the provider default, not a reproducibility promise.
    uint8_t stability, similarity;
} pro_voice_sample_t;

typedef enum {
    PRO_VOICE_READY, PRO_VOICE_STARTING, PRO_VOICE_PLAYING,
    PRO_VOICE_DONE, PRO_VOICE_STOPPED, PRO_VOICE_ERROR
} pro_voice_phase_t;

typedef struct {
    pro_voice_phase_t phase;
    unsigned sample;
    uint32_t consumed, total;
    uint8_t level;
    const char *error;
} pro_voice_progress_t;

typedef struct { int predictor, index; uint32_t position; } pro_voice_decoder_t;
// IMA ADPCM, high nibble first, initial predictor/index zero. No heap or codec I/O.
size_t pro_voice_decode(pro_voice_decoder_t *state, const uint8_t *data, uint32_t samples,
                        int16_t *out, size_t capacity);
unsigned pro_voice_sample_count(void);
const pro_voice_sample_t *pro_voice_sample(unsigned index);
bool pro_voice_sample_play(unsigned index, uint8_t volume, uint32_t now);
void pro_voice_sample_stop(void);
void pro_voice_sample_volume(uint8_t volume);
void pro_voice_sample_tick(uint32_t now);
pro_voice_progress_t pro_voice_sample_progress(void);
// Lock-free ownership query used by the UI's separate conversational speech path.
bool pro_voice_sample_owns_audio(void);
