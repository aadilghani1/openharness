#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "cJSON.h"
#ifdef DEVICE_PRO_COMPANION
bool cable_speech_message(const char *type, const cJSON *payload);
void cable_speech_pcm(const uint8_t *payload, size_t length);
void cable_speech_tick(void);
void cable_speech_disconnect(void);
#else
static inline bool cable_speech_message(const char *t, const cJSON *p) { (void)t; (void)p; return false; }
static inline void cable_speech_pcm(const uint8_t *p, size_t n) { (void)p; (void)n; }
static inline void cable_speech_tick(void) {}
static inline void cable_speech_disconnect(void) {}
#endif
