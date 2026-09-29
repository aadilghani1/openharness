#pragma once
#include <stdbool.h>
#include <stdint.h>

#ifdef DEVICE_PRO_COMPANION
// The caller first opens an empty audio_speech session, then asks the visible
// companion to accept it. Rejection must abort that session before sending PCM.
// These methods take the model lock briefly; no codec I/O or playback wait occurs.
bool ui_companion_speech_begin(uint32_t id, const char *agent_id,
                               const char *caption, const char *emotion);
// Explicit cancellation only. A normal PCM end drains before surface_tick clears
// the presentation; clearing on stream end would hide words still being spoken.
// Zero clears any presentation. A late nonmatching ID cannot clear a newer one.
void ui_companion_speech_clear(uint32_t id);
#else
static inline bool ui_companion_speech_begin(uint32_t id, const char *agent_id,
                                            const char *caption, const char *emotion)
{ (void)id; (void)agent_id; (void)caption; (void)emotion; return false; }
static inline void ui_companion_speech_clear(uint32_t id) { (void)id; }
#endif
