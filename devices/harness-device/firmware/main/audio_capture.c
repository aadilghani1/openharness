#include "audio_capture.h"
#include "audio_speech.h"
#include "config_store.h"
#include "audio_probe.h"
#include "board_pins.h"
#include "board/board_i2c.h"
#include "driver/i2s_std.h"
#include "esp_codec_dev.h"
#include "esp_codec_dev_defaults.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_timer.h"
#include "esp_log.h"
#ifdef DEVICE_PRO_COMPANION
#include "esp_heap_caps.h"
#ifdef CONFIG_IDF_TARGET_ESP32P4
#include "soc/gpio_struct.h"
#endif
#endif
#include <string.h>
#include <stdatomic.h>

static const char *TAG = "audio_cap";

static i2s_chan_handle_t s_rx, s_tx;
static const audio_codec_data_if_t *s_data_if;
static const audio_codec_ctrl_if_t *s_ctrl_if;
static const audio_codec_if_t *s_es7210;
static esp_codec_dev_handle_t s_mic;
static bool s_open;
static SemaphoreHandle_t s_codec_lock;
static atomic_bool s_capture_requested;
static atomic_uint s_rx_overruns;
uint32_t audio_capture_overruns(void){return atomic_load(&s_rx_overruns);}
static bool rx_overrun(i2s_chan_handle_t channel,i2s_event_data_t *event,void *ctx)
{
    (void)channel;(void)event;(void)ctx;
    atomic_fetch_add_explicit(&s_rx_overruns,1,memory_order_relaxed);
    return false;
}

// ES8311 speaker (OUT) path for the notification beep — shares the I2S + I2C with the mic.
static const audio_codec_ctrl_if_t *s_spk_ctrl;
static const audio_codec_gpio_if_t *s_gpio_if;
static const audio_codec_if_t *s_es8311;
static esp_codec_dev_handle_t s_spk;
static TaskHandle_t s_beep_task;
static atomic_bool s_muted = true;
#ifdef DEVICE_PRO_COMPANION
static atomic_bool s_speech_requested;
#endif

bool audio_notify_is_muted(void)
{
    return atomic_load_explicit(&s_muted, memory_order_relaxed);
}

bool audio_notify_set_muted(bool muted)
{
    atomic_store_explicit(&s_muted, muted, memory_order_relaxed);
    return config_save_muted(muted);
}

// BEEP_COUNT 80ms ~2kHz tones with 60ms gaps. Generate only the next 20ms,
// retaining the identical waveform without reserving 11 KiB for an idle sound.
#define BEEP_SAMPLES (AUDIO_SAMPLE_RATE * 80 / 1000)
#define GAP_SAMPLES  (AUDIO_SAMPLE_RATE * 60 / 1000)
#define BEEP_COUNT   3
#define TONE_SAMPLES (BEEP_SAMPLES * BEEP_COUNT + GAP_SAMPLES * (BEEP_COUNT - 1))
#define TONE_BLOCK_SAMPLES (AUDIO_SAMPLE_RATE / 50)
static int16_t s_tone[TONE_BLOCK_SAMPLES];

static void render_tone(size_t offset, size_t count)
{
    const int half = AUDIO_SAMPLE_RATE / 2000 / 2;   // half-period of a ~2kHz square wave
    const int16_t amp = 6000;
    for (size_t i = 0; i < count; i++) {
        size_t phase = (offset + i) % (BEEP_SAMPLES + GAP_SAMPLES);
        s_tone[i] = phase < BEEP_SAMPLES
            ? (((phase / (half > 0 ? half : 1)) & 1) ? amp : -amp) : 0;
    }
}

static void play_beep(void)
{
#ifdef DEVICE_PRO_COMPANION
    if (atomic_load(&s_speech_requested)) return;
#endif
    if (!s_spk || audio_notify_is_muted() || atomic_load(&s_capture_requested)) return;
    if (xSemaphoreTake(s_codec_lock, 0) != pdTRUE) return;
    if (audio_notify_is_muted() || atomic_load(&s_capture_requested)) {
        xSemaphoreGive(s_codec_lock);
        return;
    }
#ifdef DEVICE_PRO_COMPANION
    if (atomic_load(&s_speech_requested)) { xSemaphoreGive(s_codec_lock); return; }
#endif
    esp_codec_dev_sample_info_t fs = { .sample_rate = AUDIO_SAMPLE_RATE, .channel = 1, .bits_per_sample = 16 };
    if (esp_codec_dev_open(s_spk, &fs) != ESP_OK) { xSemaphoreGive(s_codec_lock); ESP_LOGW(TAG, "spk open failed"); return; }
    if (!audio_notify_is_muted()) {
        esp_codec_dev_set_out_vol(s_spk, 100);
        // Let mute or a microphone start interrupt a tone within one 20ms write.
        for (size_t offset=0; offset<TONE_SAMPLES;) {
            if (audio_notify_is_muted() || atomic_load(&s_capture_requested)) break;
#ifdef DEVICE_PRO_COMPANION
            if (atomic_load(&s_speech_requested)) break;
#endif
            size_t count=TONE_SAMPLES-offset;
            if (count>TONE_BLOCK_SAMPLES) count=TONE_BLOCK_SAMPLES;
            render_tone(offset,count);
            if (esp_codec_dev_write(s_spk, s_tone, (int)(count*sizeof s_tone[0])) != ESP_CODEC_DEV_OK) break;
            offset+=count;
        }
    }
    esp_codec_dev_close(s_spk);
    xSemaphoreGive(s_codec_lock);
    ESP_LOGI(TAG, "beep");
}

static void beep_task(void *arg)
{
    (void)arg;
    while (1) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        play_beep();
    }
}

static void notify_init_failed(const char *why)
{
    // The microphone owns the shared I2S interface. Release only the speaker
    // objects acquired by this attempt, so a later retry cannot leak them.
    if (s_spk) { esp_codec_dev_delete(s_spk); s_spk = NULL; }
    if (s_es8311) { audio_codec_delete_codec_if(s_es8311); s_es8311 = NULL; }
    if (s_gpio_if) { audio_codec_delete_gpio_if(s_gpio_if); s_gpio_if = NULL; }
    if (s_spk_ctrl) { audio_codec_delete_ctrl_if(s_spk_ctrl); s_spk_ctrl = NULL; }
    ESP_LOGW(TAG, "speaker unavailable: %s", why);
}

void audio_notify_init(void)
{
#ifdef DEVICE_CREATURE_GALLERY
    atomic_store_explicit(&s_muted, true, memory_order_relaxed);
    ESP_LOGI(TAG, "notifications muted (local ASCII gallery)");
    return; // No speaker initialization or beep task in the visual-only study.
#endif
    if (s_beep_task) return;
    atomic_store_explicit(&s_muted, config_load_muted(), memory_order_relaxed);
    if (audio_notify_is_muted()) config_save_muted(true);
    ESP_LOGI(TAG, "notifications %s", audio_notify_is_muted() ? "muted" : "audible");
    if (!s_mic && !audio_capture_init()) { ESP_LOGW(TAG, "notify init: I2S unavailable"); return; }

    audio_codec_i2c_cfg_t i2c_cfg = {
        .port = I2C_NUM_0,
        .addr = ES8311_CODEC_DEFAULT_ADDR,
        .bus_handle = board_i2c_get(),
    };
    s_spk_ctrl = audio_codec_new_i2c_ctrl(&i2c_cfg);
    s_gpio_if = audio_codec_new_gpio();
    if (!s_spk_ctrl || !s_gpio_if) { notify_init_failed("control/GPIO allocation"); return; }

    es8311_codec_cfg_t es_cfg = {
        .ctrl_if = s_spk_ctrl,
        .gpio_if = s_gpio_if,
        .codec_mode = ESP_CODEC_DEV_WORK_MODE_DAC,
        .pa_pin = BSP_PA_IO,            // speaker power-amp enable — codec toggles it on open/close
        .use_mclk = true,
    };
    s_es8311 = es8311_codec_new(&es_cfg);
    if (!s_es8311) { notify_init_failed("codec allocation"); return; }

    esp_codec_dev_cfg_t dev_cfg = {
        .dev_type = ESP_CODEC_DEV_TYPE_OUT,
        .codec_if = s_es8311,
        .data_if = s_data_if,
    };
    s_spk = esp_codec_dev_new(&dev_cfg);
    if (!s_spk) { notify_init_failed("device allocation"); return; }

    // The full codec-open path retained only 688 B on a 3 KiB stack during
    // event stress. Four KiB restores the 25% and 1 KiB safety margins.
    if (xTaskCreate(beep_task, "beep", 4096, NULL, 5, &s_beep_task) != pdPASS) {
        s_beep_task = NULL;
        notify_init_failed("task allocation");
        return;
    }
    ESP_LOGI(TAG, "speaker (ES8311) ready");
#ifdef DEVICE_PRO_COMPANION
    // Provision the bounded stream at boot; hello/USB handlers only inspect
    // readiness, and never allocate or initialize a codec.
    (void)audio_speech_init();
#endif
}

void audio_notify_done(void)
{
    static atomic_uint last_ms;
    if (!s_beep_task || audio_notify_is_muted()) return;
    uint32_t previous = atomic_load(&last_ms);
    uint32_t now = (uint32_t)(esp_timer_get_time() / 1000);
    if (now - previous < 1000) return;
    // A concurrent completion owns the notification if it won this exchange.
    if (!atomic_compare_exchange_strong(&last_ms, &previous, now)) return;
    xTaskNotifyGive(s_beep_task);
}

static bool capture_init_failed(const char *why)
{
    if (s_mic) { esp_codec_dev_delete(s_mic); s_mic = NULL; }
    if (s_es7210) { audio_codec_delete_codec_if(s_es7210); s_es7210 = NULL; }
    if (s_ctrl_if) { audio_codec_delete_ctrl_if(s_ctrl_if); s_ctrl_if = NULL; }
    if (s_data_if) { audio_codec_delete_data_if(s_data_if); s_data_if = NULL; }
    if (s_rx) { i2s_channel_disable(s_rx); i2s_del_channel(s_rx); s_rx = NULL; }
    if (s_tx) { i2s_channel_disable(s_tx); i2s_del_channel(s_tx); s_tx = NULL; }
    if (s_codec_lock) { vSemaphoreDelete(s_codec_lock); s_codec_lock = NULL; }
    ESP_LOGE(TAG, "microphone unavailable: %s", why);
    return false;
}

bool audio_capture_init(void)
{
    if (s_mic) return true;
    if (!s_codec_lock) s_codec_lock=xSemaphoreCreateMutex();
    if (!s_codec_lock) return false;

    // Full-duplex I2S (BSP-exact): ES7210(ADC)+ES8311(codec) share BCLK/WS, so create both
    // tx+rx and enable them — RX-only setups leave the shared clocks misconfigured → silence.
    i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
#ifdef DEVICE_PRO_COMPANION
    // A streamed reply can pause between packets. Do not repeat stale PCM from
    // TX DMA while waiting for the next packet or handing the clocks to capture.
    chan_cfg.auto_clear = true;
#endif
#ifdef DEVICE_HABITAT
    chan_cfg.dma_frame_num = 160; // 10ms of mono PCM at 16kHz.
    chan_cfg.dma_desc_num = 12;   // 120ms of DMA headroom, independent of the USB sender.
#endif
    if (i2s_new_channel(&chan_cfg, &s_tx, &s_rx) != ESP_OK) return capture_init_failed("I2S allocation");

    i2s_std_config_t std = {
        .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(AUDIO_SAMPLE_RATE),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {
            .mclk = BSP_I2S_MCLK,
            .bclk = BSP_I2S_BCLK,
            .ws = BSP_I2S_WS,
            .dout = BSP_I2S_DOUT,
            .din = BSP_I2S_DIN,
            .invert_flags = { .mclk_inv = false, .bclk_inv = false, .ws_inv = false },
        },
    };
    if (i2s_channel_init_std_mode(s_tx, &std) != ESP_OK) return capture_init_failed("I2S TX init");
    if (i2s_channel_init_std_mode(s_rx, &std) != ESP_OK) return capture_init_failed("I2S RX init");
    i2s_event_callbacks_t callbacks={.on_recv_q_ovf=rx_overrun};
    if (i2s_channel_register_event_callback(s_rx,&callbacks,NULL) != ESP_OK)
        return capture_init_failed("I2S callback");
    if (i2s_channel_enable(s_tx) != ESP_OK) return capture_init_failed("I2S TX enable");
    if (i2s_channel_enable(s_rx) != ESP_OK) return capture_init_failed("I2S RX enable");

    // esp_codec_dev: I2S data interface + ES7210 over the shared I2C control bus.
    audio_codec_i2s_cfg_t i2s_cfg = { .port = I2S_NUM_0, .rx_handle = s_rx, .tx_handle = s_tx };
    s_data_if = audio_codec_new_i2s_data(&i2s_cfg);
    if (!s_data_if) return capture_init_failed("I2S interface allocation");

    audio_codec_i2c_cfg_t i2c_cfg = {
        .port = I2C_NUM_0,
        .addr = ES7210_CODEC_DEFAULT_ADDR,
        .bus_handle = board_i2c_get(),
    };
    s_ctrl_if = audio_codec_new_i2c_ctrl(&i2c_cfg);
    if (!s_ctrl_if) return capture_init_failed("control interface allocation");

    es7210_codec_cfg_t es_cfg = {
        .ctrl_if = s_ctrl_if,
        // Match the vendor BSP: leave mic_selected at the driver default (the board's mics
        // aren't necessarily MIC1/MIC2; an explicit wrong selection captures silence).
    };
    s_es7210 = es7210_codec_new(&es_cfg);
    if (!s_es7210) return capture_init_failed("codec allocation");

    esp_codec_dev_cfg_t dev_cfg = {
        .dev_type = ESP_CODEC_DEV_TYPE_IN,
        .codec_if = s_es7210,
        .data_if = s_data_if,
    };
    s_mic = esp_codec_dev_new(&dev_cfg);
    if (!s_mic) return capture_init_failed("device allocation");
    ESP_LOGI(TAG, "mic (ES7210) ready");
    return true;
}

bool audio_capture_start(void)
{
#ifdef DEVICE_PRO_COMPANION
    // Preempt before initialization/codec-lock acquisition. The USB callback
    // never closes a codec; the speech worker observes this atomic request.
    atomic_store(&s_capture_requested, true);
    audio_speech_abort(0);
#endif
    if (!s_mic && !audio_capture_init()) { atomic_store(&s_capture_requested,false); return false; }
    if (s_open) return true;
    atomic_store(&s_capture_requested,true);
    xSemaphoreTake(s_codec_lock,portMAX_DELAY);
    esp_codec_dev_sample_info_t fs = {
        .sample_rate = AUDIO_SAMPLE_RATE,
        .channel = 1,
        .bits_per_sample = 16,
    };
    if (esp_codec_dev_open(s_mic, &fs) != ESP_OK) { atomic_store(&s_capture_requested,false);xSemaphoreGive(s_codec_lock);ESP_LOGE(TAG, "codec open"); return false; }
    // Make sure the I2S RX clock is running (esp_codec_dev_open may leave it disabled).
    esp_err_t en = i2s_channel_enable(s_rx);
    if (en != ESP_OK && en != ESP_ERR_INVALID_STATE) ESP_LOGW(TAG, "i2s enable: %s", esp_err_to_name(en));
    esp_codec_dev_set_in_gain(s_mic, 37.5);  // higher analog mic gain
    atomic_store(&s_rx_overruns,0);
    s_open = true;
    ESP_LOGI(TAG, "mic stream open (%d Hz mono)", AUDIO_SAMPLE_RATE);
    return true;
}

int audio_capture_read(uint8_t *buf, int len)
{
    if (!s_open) return -1;
    int64_t started = esp_timer_get_time();
    int r = esp_codec_dev_read(s_mic, buf, len);
    audio_probe_read((uint32_t)(esp_timer_get_time()-started),r==ESP_CODEC_DEV_OK?len:0);
    return (r == ESP_CODEC_DEV_OK) ? len : -1;
}

void audio_capture_stop(void)
{
    if (s_open) { esp_codec_dev_close(s_mic); s_open = false;atomic_store(&s_capture_requested,false);xSemaphoreGive(s_codec_lock); }
}

#ifdef DEVICE_PRO_COMPANION
// The protocol publishes PCM only. One worker owns every speaker operation;
// capture/notification/speech serialize against the existing codec mutex.
#define SPEECH_BLOCK_BYTES (AUDIO_SPEECH_RATE * 2u / 50u)
#define SPEECH_WRITE_TIMEOUT_MS 20u
#define SPEECH_DATA_TIMEOUT_US INT64_C(5000000)
// Habitat's shared TX/RX configuration has twelve 10ms DMA descriptors. Bytes
// accepted by I2S may still be queued there; let the last samples play before
// closing, while remaining immediately interruptible by a new capture.
#define SPEECH_DMA_TAIL_US INT64_C(130000)
static portMUX_TYPE s_speech_mux = portMUX_INITIALIZER_UNLOCKED;
static TaskHandle_t s_speech_task;
static uint8_t *s_speech_pcm;
static audio_speech_state_t s_speech;
static uint32_t s_speech_generation;
static uint8_t s_speech_volume;
static bool s_speech_producer, s_speech_worker;
static int64_t s_speech_last_data;

bool audio_speech_available(void)
{
    return s_speech_task != NULL;
}

static void speech_cancel_locked(audio_speech_error_t error)
{
    s_speech.active = false;
    s_speech.pending = false;
    s_speech.level = 0;
    s_speech.error = error;
    if (!s_speech_worker && !s_speech_producer) atomic_store(&s_speech_requested, false);
}
void audio_speech_snapshot(audio_speech_state_t *out)
{
    if (!out) return;
    portENTER_CRITICAL(&s_speech_mux);
    *out = s_speech;
    out->queued = out->active ? out->received - out->consumed : 0;
    if (!s_speech_task) out->error = AUDIO_SPEECH_ERROR_UNAVAILABLE;
    portEXIT_CRITICAL(&s_speech_mux);
}
bool audio_speech_begin(uint32_t id, uint32_t rate, uint8_t volume)
{
    if (!s_speech_task || !id || rate != AUDIO_SPEECH_RATE || volume > 100 ||
        atomic_load(&s_capture_requested)) return false;
    int64_t now = esp_timer_get_time();
    portENTER_CRITICAL(&s_speech_mux);
    bool accept = !s_speech.active && !s_speech_worker && !s_speech_producer &&
                  id != s_speech.id && !atomic_load(&s_capture_requested);
    if (accept) {
        s_speech = (audio_speech_state_t){.id=id,.active=true,.pending=true};
        s_speech_generation++;
        s_speech_volume = volume;
        s_speech_last_data = now;
        atomic_store(&s_speech_requested, true);
    }
    portEXIT_CRITICAL(&s_speech_mux);
    if (accept) xTaskNotifyGive(s_speech_task);
    return accept;
}
static bool speech_rejected(const char *stage, uint32_t id, uint32_t offset, size_t length)
{
    // Preserve the reason before the transport aborts a rejected stream. Never
    // log PCM or captions, and never hold the speech lock while writing a log.
    audio_speech_state_t state;
    bool producer, worker;
    portENTER_CRITICAL(&s_speech_mux);
    state = s_speech;
    producer = s_speech_producer;
    worker = s_speech_worker;
    portEXIT_CRITICAL(&s_speech_mux);
    ESP_LOGW(TAG, "speech reject %s id=%lu offset=%lu bytes=%u current=%lu received=%lu consumed=%lu active=%d ended=%d producer=%d worker=%d capture=%d error=%u",
             stage, (unsigned long)id, (unsigned long)offset, (unsigned)length,
             (unsigned long)state.id, (unsigned long)state.received,
             (unsigned long)state.consumed, state.active, state.ended, producer, worker,
             atomic_load(&s_capture_requested), (unsigned)state.error);
    return false;
}
bool audio_speech_push(uint32_t id, uint32_t offset, const void *pcm, size_t length)
{
    if (!s_speech_task || !pcm || !length || (length & 1) || (offset & 1) ||
        length > AUDIO_SPEECH_CAPACITY || offset > AUDIO_SPEECH_MAX_BYTES ||
        length > AUDIO_SPEECH_MAX_BYTES-offset || atomic_load(&s_capture_requested))
        return speech_rejected("input", id, offset, length);
    portENTER_CRITICAL(&s_speech_mux);
    bool accept = s_speech.active && !s_speech.ended && !s_speech_producer &&
        id == s_speech.id && offset == s_speech.received &&
        length <= AUDIO_SPEECH_CAPACITY-(s_speech.received-s_speech.consumed);
    uint32_t generation = s_speech_generation;
    if (accept) s_speech_producer = true;
    portEXIT_CRITICAL(&s_speech_mux);
    if (!accept) return speech_rejected("state", id, offset, length);

    // The worker can only read published bytes. Reserve a single producer so
    // abort/new begin cannot reuse this region until this copy finishes. Never
    // disable interrupts across a PSRAM copy (up to the advertised window).
    size_t at = offset % AUDIO_SPEECH_CAPACITY;
    size_t first = AUDIO_SPEECH_CAPACITY-at;
    if (first > length) first = length;
    memcpy(s_speech_pcm+at, pcm, first);
    if (first < length) memcpy(s_speech_pcm, (const uint8_t *)pcm+first, length-first);
    int64_t now = esp_timer_get_time();
    portENTER_CRITICAL(&s_speech_mux);
    accept = s_speech.active && s_speech_generation == generation &&
             !atomic_load(&s_capture_requested);
    if (accept) {
        s_speech.received += (uint32_t)length;
        s_speech_last_data = now;
    }
    s_speech_producer = false;
    if (!s_speech.active && !s_speech_worker) atomic_store(&s_speech_requested, false);
    portEXIT_CRITICAL(&s_speech_mux);
    xTaskNotifyGive(s_speech_task);
    return accept ? true : speech_rejected("publish", id, offset, length);
}
bool audio_speech_end(uint32_t id, uint32_t total_bytes)
{
    if (!s_speech_task || (total_bytes & 1) || total_bytes > AUDIO_SPEECH_MAX_BYTES) return false;
    portENTER_CRITICAL(&s_speech_mux);
    bool accept = s_speech.active && !s_speech.ended && !s_speech_producer &&
                  id == s_speech.id && total_bytes == s_speech.received;
    if (accept) s_speech.ended = true;
    portEXIT_CRITICAL(&s_speech_mux);
    if (accept) xTaskNotifyGive(s_speech_task);
    return accept;
}
void audio_speech_abort(uint32_t id)
{
    if (!s_speech_task) return;
    portENTER_CRITICAL(&s_speech_mux);
    bool matches = !id || id == s_speech.id;
    if (matches && (s_speech.active || s_speech_worker))
        speech_cancel_locked(atomic_load(&s_capture_requested) ? AUDIO_SPEECH_ERROR_CAPTURE : AUDIO_SPEECH_ERROR_ABORTED);
    portEXIT_CRITICAL(&s_speech_mux);
    if (matches) xTaskNotifyGive(s_speech_task);
}
static bool speech_continue(uint32_t generation)
{
    portENTER_CRITICAL(&s_speech_mux);
    if (s_speech.active && atomic_load(&s_capture_requested))
        speech_cancel_locked(AUDIO_SPEECH_ERROR_CAPTURE);
    bool live = s_speech.active && s_speech_generation == generation;
    portEXIT_CRITICAL(&s_speech_mux);
    return live;
}
static uint8_t speech_level(const int16_t *pcm, size_t bytes)
{
    uint32_t sum = 0;
    size_t samples = bytes / 2;
    for (size_t i=0;i<samples;i++) {
        int32_t sample = pcm[i];
        sum += (uint32_t)(sample < 0 ? -sample : sample);
    }
    uint32_t mean = samples ? sum / samples : 0;
    return mean < 160 ? 0 : mean < 700 ? 1 : mean < 2200 ? 2 : mean < 7000 ? 3 : 4;
}
static void speech_open_diagnostics(uint8_t volume)
{
#ifdef CONFIG_IDF_TARGET_ESP32P4
    // GPIO54 is output-only. gpio_get_level() would return zero without input
    // enable; read the output latch and enable register without changing I/O.
    unsigned pa_out = (GPIO.out1.val >> (BSP_PA_IO - 32)) & 1;
    unsigned pa_enable = (GPIO.enable1.val >> (BSP_PA_IO - 32)) & 1;
    static const uint8_t regs[] = {0x09, 0x0d, 0x12, 0x31, 0x32, 0x44};
    uint8_t values[sizeof regs];
    unsigned failed = 0;
    for (unsigned i = 0; i < sizeof regs; i++) {
        values[i] = 0xff;
        if (!s_spk_ctrl || !s_spk_ctrl->read_reg ||
            s_spk_ctrl->read_reg(s_spk_ctrl, regs[i], 1, &values[i], 1) != ESP_CODEC_DEV_OK)
            failed |= 1u << i;
    }
    // Numeric once per explicit utterance, after volume/unmute but before PCM.
    // Register values are evidence of configuration, not acoustic playback.
    ESP_LOGI(TAG, "speech output vol=%u pa_pin=%u pa_out=%u pa_enable=%u read_fail=0x%x r09=%02x r0d=%02x r12=%02x r31=%02x r32=%02x r44=%02x",
             (unsigned)volume, (unsigned)BSP_PA_IO, pa_out, pa_enable, failed,
             values[0], values[1], values[2], values[3], values[4], values[5]);
#else
    (void)volume;
#endif
}
static void play_speech(void)
{
    uint32_t generation;
    uint8_t volume;
    int64_t now = esp_timer_get_time();
    portENTER_CRITICAL(&s_speech_mux);
    if (s_speech.active && atomic_load(&s_capture_requested)) speech_cancel_locked(AUDIO_SPEECH_ERROR_CAPTURE);
    if (s_speech.active && !s_speech.ended && now-s_speech_last_data >= SPEECH_DATA_TIMEOUT_US)
        speech_cancel_locked(AUDIO_SPEECH_ERROR_TIMEOUT);
    if (!s_speech.active || s_speech_worker || s_speech.received == s_speech.consumed) {
        if (s_speech.active && s_speech.ended) speech_cancel_locked(AUDIO_SPEECH_ERROR_NONE);
        portEXIT_CRITICAL(&s_speech_mux);
        return;
    }
    s_speech_worker = true;
    generation = s_speech_generation;
    volume = s_speech_volume;
    portEXIT_CRITICAL(&s_speech_mux);

    bool owns_codec = false, opened = false;
    audio_speech_error_t error = AUDIO_SPEECH_ERROR_NONE;
    while (speech_continue(generation)) {
        if (xSemaphoreTake(s_codec_lock, pdMS_TO_TICKS(SPEECH_WRITE_TIMEOUT_MS)) == pdTRUE) {
            owns_codec = true;
            break;
        }
    }
    if (!owns_codec || !speech_continue(generation)) goto finished;
    esp_codec_dev_sample_info_t fs = {.sample_rate=AUDIO_SPEECH_RATE,.channel=1,.bits_per_sample=16};
    // Open can partially configure the device before reporting failure. Always
    // close that attempt while still owning the shared codec mutex.
    opened = true;
    if (esp_codec_dev_open(s_spk, &fs) != ESP_CODEC_DEV_OK ||
        esp_codec_dev_set_out_vol(s_spk, volume) != ESP_CODEC_DEV_OK) {
        error = AUDIO_SPEECH_ERROR_CODEC;
        goto finished;
    }
    speech_open_diagnostics(volume);
    portENTER_CRITICAL(&s_speech_mux);
    s_speech.playing = true;
    s_speech.pending = false;
    portEXIT_CRITICAL(&s_speech_mux);

    int16_t block[SPEECH_BLOCK_BYTES/2];
    int64_t drain_until = 0;
    unsigned stalled = 0;
    while (speech_continue(generation)) {
        portENTER_CRITICAL(&s_speech_mux);
        uint32_t offset = s_speech.consumed;
        size_t bytes = s_speech.received-offset;
        bool ended = s_speech.ended;
        int64_t last_data = s_speech_last_data;
        portEXIT_CRITICAL(&s_speech_mux);
        if (bytes > sizeof block) bytes = sizeof block;
        if (bytes) {
            size_t at = offset % AUDIO_SPEECH_CAPACITY;
            size_t first = AUDIO_SPEECH_CAPACITY-at;
            if (first > bytes) first = bytes;
            memcpy(block, s_speech_pcm+at, first);
            if (first < bytes) memcpy((uint8_t *)block+first, s_speech_pcm, bytes-first);
            if (!speech_continue(generation)) break;
            size_t written = 0;
            // esp_codec_dev_write's fixed 1000ms timeout defeats capture
            // preemption. ES8311 has hardware volume, so use the shared TX
            // channel directly after codec open/volume with an explicit bound.
            esp_err_t rc = i2s_channel_write(s_tx, block, bytes, &written, SPEECH_WRITE_TIMEOUT_MS);
            if ((rc != ESP_OK && rc != ESP_ERR_TIMEOUT) || written > bytes || (written & 1)) {
                error = AUDIO_SPEECH_ERROR_CODEC;
                break;
            }
            if (!written) {
                if (++stalled >= 5) { error = AUDIO_SPEECH_ERROR_CODEC; break; }
                continue;
            }
            stalled = 0;
            uint8_t level = speech_level(block, written);
            drain_until = esp_timer_get_time()+SPEECH_DMA_TAIL_US;
            portENTER_CRITICAL(&s_speech_mux);
            if (s_speech.active && s_speech_generation == generation) {
                s_speech.consumed += (uint32_t)written;
                s_speech.level = level;
            }
            portEXIT_CRITICAL(&s_speech_mux);
            continue;
        }
        now = esp_timer_get_time();
        if (ended && now >= drain_until) break;
        if (!ended && now-last_data >= SPEECH_DATA_TIMEOUT_US) {
            error = AUDIO_SPEECH_ERROR_TIMEOUT;
            break;
        }
        if (now >= drain_until) {
            portENTER_CRITICAL(&s_speech_mux);
            s_speech.level = 0;
            portEXIT_CRITICAL(&s_speech_mux);
        }
        // Push/end/abort wake this immediately. Capture sets its atomic flag
        // then calls abort, so it does not wait for a starvation/tail timer.
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(SPEECH_WRITE_TIMEOUT_MS));
    }
finished:
    if (opened) esp_codec_dev_close(s_spk);
    if (owns_codec) xSemaphoreGive(s_codec_lock);
    portENTER_CRITICAL(&s_speech_mux);
    if (s_speech_generation == generation) {
        if (s_speech.active) speech_cancel_locked(error);
        s_speech.playing = false;
        s_speech.pending = false;
        s_speech.level = 0;
    }
    s_speech_worker = false;
    if (!s_speech.active && !s_speech_producer) atomic_store(&s_speech_requested, false);
    portEXIT_CRITICAL(&s_speech_mux);
}
static void speech_task(void *arg)
{
    (void)arg;
    for (;;) {
        // An unanswered begin has a finite timeout. Completely idle playback
        // has no periodic CPU work and does not keep the codec open.
        ulTaskNotifyTake(pdTRUE, atomic_load(&s_speech_requested) ? pdMS_TO_TICKS(1000) : portMAX_DELAY);
        play_speech();
    }
}
bool audio_speech_init(void)
{
    if (s_speech_task) return true;
    if (!s_spk || !s_codec_lock) return false;
    s_speech_pcm = heap_caps_malloc(AUDIO_SPEECH_CAPACITY, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!s_speech_pcm) return false;
    if (xTaskCreate(speech_task, "speech", 4096, NULL, 5, &s_speech_task) != pdPASS) {
        s_speech_task = NULL;
        heap_caps_free(s_speech_pcm);
        s_speech_pcm = NULL;
        return false;
    }
    ESP_LOGI(TAG, "speech ready: PCM16 mono 16kHz, 64KiB window, 30s limit");
    return true;
}
#endif
