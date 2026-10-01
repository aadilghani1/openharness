#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define AUDIO_SPEECH_RATE 16000u
#define AUDIO_SPEECH_CAPACITY 65536u
#define AUDIO_SPEECH_MAX_BYTES (AUDIO_SPEECH_RATE * 2u * 30u)

typedef enum {
    AUDIO_SPEECH_ERROR_NONE = 0,
    AUDIO_SPEECH_ERROR_UNAVAILABLE,
    AUDIO_SPEECH_ERROR_CODEC,
    AUDIO_SPEECH_ERROR_TIMEOUT,
    AUDIO_SPEECH_ERROR_ABORTED,
    AUDIO_SPEECH_ERROR_CAPTURE,
} audio_speech_error_t;

typedef struct {
    uint32_t id;
    bool active;   // Accepting/draining this session, including a temporary underrun.
    bool playing;  // Worker owns the open speaker, including its final DMA drain.
    bool pending;  // Active but the speaker has not opened yet.
    bool ended;    // An exact total was supplied; no further pushes accepted.
    uint32_t received;
    uint32_t consumed; // Bytes accepted by I2S; host credit, not an audible timestamp.
    uint32_t queued;   // received - consumed while active; zero after abort.
    uint8_t level;     // Bounded 0..4 amplitude for the companion.
    audio_speech_error_t error;
} audio_speech_state_t;

#ifdef DEVICE_PRO_COMPANION
// Boot-only, called by audio_notify_init after speaker creation: starts the worker
// and preallocates PSRAM. An explicit retry requires that speaker to be ready.
bool audio_speech_init(void);
bool audio_speech_available(void);
// Nonblocking callbacks. No allocation, codec access, NVS write, or wait for playback.
// Begin rejects zero/reused-last IDs, invalid rate/volume, capture, and an active or
// still-closing session. volume is explicitly requested 0..100, independent of
// notification mute. The caller should normally use 60.
bool audio_speech_begin(uint32_t id, uint32_t rate, uint8_t volume);
// Metadata only: the codec worker applies the new volume at its next short block.
bool audio_speech_set_volume(uint32_t id, uint8_t volume);
// Mono signed PCM16LE, even offset/length, strict received-byte offset, max 30 s.
// False includes backpressure/concurrent producer: no bytes were accepted. Retry
// at the same offset after credit; malformed/stale packets must not be retried.
bool audio_speech_push(uint32_t id, uint32_t offset, const void *pcm, size_t length);
bool audio_speech_end(uint32_t id, uint32_t total_bytes);
// id==0 aborts any current session. Codec shutdown happens on the worker.
void audio_speech_abort(uint32_t id);
void audio_speech_snapshot(audio_speech_state_t *out);
#else
static inline bool audio_speech_init(void) { return false; }
static inline bool audio_speech_available(void) { return false; }
static inline bool audio_speech_begin(uint32_t id, uint32_t rate, uint8_t volume)
{ (void)id; (void)rate; (void)volume; return false; }
static inline bool audio_speech_set_volume(uint32_t id, uint8_t volume)
{ (void)id; (void)volume; return false; }
static inline bool audio_speech_push(uint32_t id, uint32_t offset, const void *pcm, size_t length)
{ (void)id; (void)offset; (void)pcm; (void)length; return false; }
static inline bool audio_speech_end(uint32_t id, uint32_t total_bytes)
{ (void)id; (void)total_bytes; return false; }
static inline void audio_speech_abort(uint32_t id) { (void)id; }
static inline void audio_speech_snapshot(audio_speech_state_t *out)
{ if (out) *out = (audio_speech_state_t){.error=AUDIO_SPEECH_ERROR_UNAVAILABLE}; }
#endif
