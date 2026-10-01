// Pro speech transport: the USB reader only validates/copies. Codec I/O belongs
// to the audio worker, and captions belong to the normal renderer.
#include "cable_speech.h"
#ifdef DEVICE_PRO_COMPANION
#include "audio_speech.h"
#include "cable_client.h"
#include "cable_link.h"
#include "ui/companion_speech.h"
#include "esp_timer.h"
#include <string.h>

#define WIRE_WINDOW 8192u
static audio_speech_state_t reported;
static int64_t reported_at;
static uint32_t remote_id; // Local Menu -> Voice auditions own a separate session.

static bool uint_of(const cJSON *p, const char *key, uint32_t *out)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(p, key);
    if (!cJSON_IsNumber(v) || !(v->valuedouble >= 0 && v->valuedouble <= UINT32_MAX)) return false;
    uint32_t n = (uint32_t)v->valuedouble;
    if (v->valuedouble != n) return false;
    *out = n; return true;
}
static const char *string_of(const cJSON *p, const char *key)
{
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(p, key);
    return cJSON_IsString(v) ? v->valuestring : "";
}
static bool report(const audio_speech_state_t *state, unsigned error)
{
    cJSON *p = cJSON_CreateObject();
    if (!p) return false;
    uint32_t free_bytes = state->queued < AUDIO_SPEECH_CAPACITY ? AUDIO_SPEECH_CAPACITY - state->queued : 0;
    if (free_bytes > WIRE_WINDOW) free_bytes = WIRE_WINDOW;
    uint32_t remaining = state->received < AUDIO_SPEECH_MAX_BYTES ? AUDIO_SPEECH_MAX_BYTES - state->received : 0;
    if (free_bytes > remaining) free_bytes = remaining;
    bool ok = cJSON_AddStringToObject(p, "t", "speech.state") &&
        cJSON_AddNumberToObject(p, "id", state->id) &&
        cJSON_AddBoolToObject(p, "active", state->active) &&
        cJSON_AddBoolToObject(p, "playing", state->playing) &&
        cJSON_AddBoolToObject(p, "pending", state->pending) &&
        cJSON_AddNumberToObject(p, "received", state->received) &&
        cJSON_AddNumberToObject(p, "consumed", state->consumed) &&
        cJSON_AddNumberToObject(p, "credit", state->active && !state->ended ? state->received + free_bytes : state->received) &&
        cJSON_AddNumberToObject(p, "error", error ? error : state->error);
    char *text = ok ? cJSON_PrintUnformatted(p) : NULL;
    cJSON_Delete(p);
    ok = text && cable_link_send(CABLE_TYPE_JSON, (const uint8_t *)text, strlen(text));
    cJSON_free(text);
    return ok;
}
static void reject(uint32_t id, unsigned error)
{
    const audio_speech_state_t no = {.id = id};
    report(&no, error);
}
void cable_speech_tick(void)
{
    if (!cable_client_is_connected()) return;
    audio_speech_state_t state; audio_speech_snapshot(&state);
    if (!remote_id || state.id != remote_id) return;
    int64_t now = esp_timer_get_time();
    // Receipts and codec readiness unblock host writes, so they cannot wait for
    // the 40 ms progress throttle. Consumption-only updates remain throttled.
    bool terminal = state.id != reported.id || state.active != reported.active || state.error != reported.error ||
        state.received != reported.received || state.playing != reported.playing;
    if (!terminal && now - reported_at < 40000) return;
    if (!terminal && state.received == reported.received && state.consumed == reported.consumed &&
        state.playing == reported.playing && state.pending == reported.pending) return;
    if (report(&state, 0)) { reported = state; reported_at = now; }
}
void cable_speech_disconnect(void)
{
    if (remote_id) {
        audio_speech_abort(remote_id);
        ui_companion_speech_clear(remote_id);
    }
    remote_id = 0;
    memset(&reported, 0, sizeof reported); reported_at = 0;
}
bool cable_speech_message(const char *type, const cJSON *p)
{
    if (!strcmp(type, "fw.offer")) { cable_speech_disconnect(); return false; }
    if (strncmp(type, "speech.", 7)) return false;
    uint32_t id = 0;
    if (!uint_of(p, "id", &id) || !id || !cable_client_is_connected()) { reject(id, 100); return true; }
    if (!strcmp(type, "speech.begin")) {
        uint32_t rate, volume;
        const char *agent = string_of(p, "agentId"), *caption = string_of(p, "caption");
        if (!uint_of(p, "sr", &rate) || !uint_of(p, "volume", &volume) || volume > 100 ||
            !agent[0] || strlen(agent) >= ID_MAX || !caption[0] || strlen(caption) > 1024) {
            reject(id, 100); return true;
        }
        if (!audio_speech_begin(id, rate, (uint8_t)volume)) { reject(id, 102); return true; }
        if (!ui_companion_speech_begin(id, agent, caption, string_of(p, "emotion"))) {
            audio_speech_abort(id); reject(id, 101); return true;
        }
        remote_id = id;
        cable_speech_tick(); return true;
    }
    if (id != remote_id) { reject(id, 100); return true; }
    if (!strcmp(type, "speech.end")) {
        uint32_t bytes;
        if (!uint_of(p, "bytes", &bytes) || !audio_speech_end(id, bytes)) {
            audio_speech_abort(id); ui_companion_speech_clear(id); reject(id, 100);
        } else cable_speech_tick();
        return true;
    }
    if (!strcmp(type, "speech.abort")) {
        audio_speech_abort(id); ui_companion_speech_clear(id); cable_speech_tick(); return true;
    }
    reject(id, 100); return true;
}
static uint32_t little32(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
void cable_speech_pcm(const uint8_t *p, size_t n)
{
    if (!cable_client_is_connected() || n < 10) return;
    uint32_t id = little32(p), offset = little32(p + 4);
    if (!remote_id || id != remote_id) { reject(id, 100); return; }
    if (!audio_speech_push(id, offset, p + 8, n - 8)) {
        // Credit already prevents ordinary backpressure. A gap, overflow or stale
        // packet cannot be repaired by playing whatever bytes happen to follow.
        audio_speech_abort(id); ui_companion_speech_clear(id); reject(id, 100); return;
    }
    cable_speech_tick();
}
#endif
