/* Pro supply policy. The companion is a dock-only USB device.
 * Keep the legacy battery driver for other Pro firmware builds. */
#include "power.h"
#include "board_pins.h"
#include "driver/gpio.h"
#include "esp_check.h"
#include "esp_log.h"

static const char *TAG = "power";
static bool s_ready;

void power_hold_init(void)
{
    // Q9/Q6 gate the battery boost supply; USB powers VCC5V independently.
    // Preload before enabling output so the dock-only build never asserts it.
#ifdef DEVICE_PRO_COMPANION
    ESP_ERROR_CHECK(gpio_set_level(BSP_PWR_HOLD, 0));
#else
    ESP_ERROR_CHECK(gpio_set_level(BSP_PWR_HOLD, 1));
#endif
    // GPIO1 is also an LP/RTC pad. Take digital ownership explicitly rather
    // than only changing the HP direction and inheriting its boot mux state.
    const gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << BSP_PWR_HOLD,
        .mode = GPIO_MODE_INPUT_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&cfg));
}

#ifdef DEVICE_PRO_COMPANION
bool power_init(void)
{
    if (!s_ready) {
        ESP_LOGI(TAG, "dock-only power; battery latch GPIO%d=%d",
                 BSP_PWR_HOLD, gpio_get_level(BSP_PWR_HOLD));
        s_ready = true;
    }
    return true;
}

// No cell, charger polling or battery ADC allocation in the dock-only build.
int power_battery_pct(void) { return -1; }
bool power_is_charging(void) { return false; }
bool power_is_on_external(void) { return true; }
#else
#include "board_i2c.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"

#define IP5306_REG_READ0 0x70   /* bit 3: 1 = charging */
#define IP5306_REG_READ1 0x71   /* bit 3: 1 = full */
static i2c_master_dev_handle_t s_ip5306;
static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_calibration;
static int battery_mv(void);

static bool ip5306_read(uint8_t reg, uint8_t *out)
{
    if (!s_ip5306) return false;
    return i2c_master_transmit_receive(s_ip5306, &reg, 1, out, 1, 50) == ESP_OK;
}

bool power_init(void)
{
    if (s_ready) return true;
    i2c_master_bus_handle_t bus = board_i2c_get();
    if (!bus) return false;

    const i2c_device_config_t dev = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = BSP_IP5306_I2C_ADDR,
        .scl_speed_hz = BSP_I2C_FREQ_HZ,
    };
    if (!s_ip5306 && i2c_master_bus_add_device(bus, &dev, &s_ip5306) != ESP_OK) {
        ESP_LOGE(TAG, "IP5306 would not open at 0x%02X", BSP_IP5306_I2C_ADDR);
        return false;
    }

    const adc_oneshot_unit_init_cfg_t unit = { .unit_id = ADC_UNIT_1 };
    if (!s_adc && adc_oneshot_new_unit(&unit, &s_adc) != ESP_OK) {
        ESP_LOGE(TAG, "battery ADC unit refused");
        return false;
    }
    /* 12 dB of attenuation because the divider puts a full battery at ~1.4 V and the lower ranges clip
     * there — a clipped reading looks exactly like a flat battery. */
    const adc_oneshot_chan_cfg_t chan = { .atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT };
    if (adc_oneshot_config_channel(s_adc, ADC_CHANNEL_4, &chan) != ESP_OK) {
        ESP_LOGE(TAG, "battery ADC channel refused");
        return false;
    }

    const adc_cali_curve_fitting_config_t calibration = {
        .unit_id = ADC_UNIT_1, .chan = ADC_CHANNEL_4,
        .atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    if (adc_cali_create_scheme_curve_fitting(&calibration, &s_calibration) != ESP_OK) {
        ESP_LOGW(TAG, "battery ADC calibration unavailable; voltage is approximate");
    }

    s_ready = true;
    ESP_LOGI(TAG, "IP5306 at 0x%02X · battery on ADC1_CH4 (GPIO%d, /%d divider)",
             BSP_IP5306_I2C_ADDR, BSP_VBAT_ADC_GPIO, BSP_VBAT_DIVIDER);
    uint8_t charge = 0, full = 0;
    bool charge_ok = ip5306_read(IP5306_REG_READ0, &charge);
    bool full_ok = ip5306_read(IP5306_REG_READ1, &full);
    ESP_LOGI(TAG, "battery latch GPIO%d=%d vbat_mv=%d calibrated=%d charger_read=%d charging=%d full=%d",
             BSP_PWR_HOLD, gpio_get_level(BSP_PWR_HOLD), battery_mv(), s_calibration != NULL,
             charge_ok && full_ok, charge_ok && (charge & 8), full_ok && (full & 8));
    return true;
}

/* Millivolts at the battery, averaged: one sample of an ADC carries enough noise to make the percentage
 * jitter by a few points between two ticks of the status bar. */
static int battery_mv(void)
{
    if (!s_ready) return 0;
    int sum = 0, taken = 0;
    for (int i = 0; i < 8; i++) {
        int raw = 0;
        if (adc_oneshot_read(s_adc, ADC_CHANNEL_4, &raw) != ESP_OK) continue;
        sum += raw;
        taken++;
    }
    if (!taken) return 0;
    /* 12 dB attenuation spans roughly 0–3100 mV across the 12-bit range; the divider is the rest. */
    int at_pin_mv = 0;
    if (s_calibration) {
        if (adc_cali_raw_to_voltage(s_calibration, sum / taken, &at_pin_mv) != ESP_OK) return 0;
    } else {
        at_pin_mv = (sum / taken) * 3100 / 4095;
    }
    return at_pin_mv * BSP_VBAT_DIVIDER;
}

/*
 * A single Li-ion cell's voltage/charge curve, piecewise-linear, from HARDWARE.md §7.
 *
 * It is a curve and not a straight line because the cell's is: most of the useful charge sits between
 * 3.7 V and 4.1 V, and a linear map of 3.0–4.2 V onto 0–100% reads 50% on a battery that is nearly flat.
 */
static const struct { int mv; int pct; } CURVE[] = {
    { 4200, 100 }, { 4100, 95 }, { 4000, 87 }, { 3900, 76 }, { 3800, 65 }, { 3700, 50 },
    { 3600,  25 }, { 3500, 12 }, { 3400,  6 }, { 3300,  2 }, { 3000,  0 },
};

int power_battery_pct(void)
{
    const int mv = battery_mv();
    if (mv <= 0) return -1;                       /* no reading — the UI shows no battery rather than 0% */
    if (mv >= CURVE[0].mv) return 100;
    for (size_t i = 1; i < sizeof(CURVE) / sizeof(CURVE[0]); i++) {
        if (mv >= CURVE[i].mv) {
            const int span_mv = CURVE[i - 1].mv - CURVE[i].mv;
            const int span_pct = CURVE[i - 1].pct - CURVE[i].pct;
            return CURVE[i].pct + (mv - CURVE[i].mv) * span_pct / span_mv;
        }
    }
    return 0;
}

bool power_is_charging(void)
{
    uint8_t v = 0;
    return ip5306_read(IP5306_REG_READ0, &v) && (v & 0x08);
}

/* External power present. On this board that is the same fact as "charging" — there is no separate VBUS
 * sense — which is why a full battery on a plugged-in device reports charging false and external true. */
bool power_is_on_external(void)
{
    uint8_t v = 0;
    if (ip5306_read(IP5306_REG_READ0, &v) && (v & 0x08)) return true;
    return ip5306_read(IP5306_REG_READ1, &v) && (v & 0x08);   /* full, still on the charger */
}

#endif

// The Pro button is a GPIO handled directly by ptt_pro.c.
bool power_take_pwrkey_tap(void) { return false; }
