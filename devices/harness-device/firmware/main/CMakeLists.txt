# Single "main" component holding all app sources. Board drivers live under board/
# and the LVGL UI under ui/.
#
# TWO BOARDS, ONE COMPONENT. What each one builds is chosen by IDF_TARGET, because the difference is the
# SoC and nothing about an ESP32-S3 image can run on an ESP32-P4. See ../CMakeLists.txt for the pair.
#
# The Pro's list is deliberately short while the board is being brought up. The portable half of this
# firmware — the cable protocol, the config store, OTA, the screens — is not board-dependent and joins
# the list a file at a time as each is proved on the new hardware, rather than all at once against a
# panel that has never lit up. board/pro_bringup.c carries its own app_main for exactly that window,
# and goes away when the shared one takes over.

if(IDF_TARGET STREQUAL "esp32p4")

    set(BOARD_SRCS
        # the portable half, shared verbatim with the dial
        "app_main.c"
        "ram_telemetry.c"
        "config_store.c"
        "device_mac.c"
        "cable_frame.c"
        "cable_link.c"
        "last_words.c"
        "cable_client.c"
        "cable_machines.c"
        "fw_update.c"
        "audio_client.c"
        "audio_capture.c"
        # this board's own
        "board/board_i2c.c"
        "board/board_pro.c"
        "board/ptt_pro.c"
        "board/power_pro.c"
        "ui/display.c"
        "ui/panel_pro.c"
        "ui/touch.c"
        "ui/touch_gt911.c"
        # the screens, and the faces they are drawn in — identical files on both boards
        "ui/ui_screens.c"
        "ui/carousel_ring.c"
        "ui/geist_reg_16.c"
        "ui/geist_reg_20.c"
        "ui/geist_reg_24.c"
        "ui/geist_reg_25.c"
        "ui/geist_med_28.c"
        "ui/geist_med_32.c"
        "ui/geist_reg_32.c"
        "ui/geist_reg_34.c"
        "ui/geist_reg_38.c"
        "ui/geist_med_38.c"
        "ui/geist_med_48.c"
        "ui/geist_med_64.c"
        "ui/geist_sem_24.c"
        "ui/icons_settings.c"
        "ui/icons_engine.c"
        "ui/icons_voice.c"
        "ui/spinner_spokes.c"
    )
    set(BOARD_REQUIRES
        esp_driver_i2c
        esp_driver_gpio
        esp_driver_ledc
        esp_lcd
        esp_lcd_touch
        esp_timer
        driver
        lvgl
        esp_psram
        json
        nvs_flash
        app_update
        esp_partition
        mbedtls
        esp_adc
        esp_codec_dev
        esp_driver_i2s
    )

else()   # esp32s3 — the round dial

    set(BOARD_SRCS
        "app_main.c"
        "ram_telemetry.c"
        "config_store.c"
        "device_mac.c"
        "cable_frame.c"
        "cable_link.c"
        "last_words.c"
        "cable_client.c"
        "cable_machines.c"
        "fw_update.c"
        "audio_capture.c"
        "audio_client.c"
        "ptt.c"
        "board/board_i2c.c"
        "board/board.c"
        "board/board_table.c"
        "board/power.c"
        "ui/display.c"
        "ui/panel_dial.c"
        "ui/touch.c"
        "ui/touch_cst.c"
        "ui/ui_screens.c"
        "ui/carousel_ring.c"
        "ui/geist_reg_20.c"
        "ui/geist_reg_25.c"
        "ui/geist_med_28.c"
        "ui/geist_med_32.c"
        "ui/geist_reg_34.c"
        "ui/geist_reg_38.c"
        "ui/geist_reg_16.c"
        "ui/geist_reg_24.c"
        "ui/geist_reg_32.c"
        "ui/geist_med_48.c"
        "ui/geist_med_64.c"
        "ui/geist_sem_24.c"
        "ui/geist_med_38.c"
        "ui/icons_settings.c"
        "ui/spinner_spokes.c"
        "ui/icons_engine.c"
        "ui/icons_voice.c"
    )
    set(BOARD_REQUIRES
        nvs_flash
        esp_wifi
        esp_netif
        esp_event
        esp_http_server
        esp_http_client
        esp_https_ota
        app_update
        esp_partition
        mbedtls
        libsodium
        esp_websocket_client
        esp-tls
        esp_lcd
        esp_lcd_touch
        esp_codec_dev
        esp_timer
        driver
        json
        lvgl
    )

endif()

idf_component_register(
    SRCS ${BOARD_SRCS}
    INCLUDE_DIRS
        "."
        "ui"
        "board"
    REQUIRES ${BOARD_REQUIRES}
)

# snprintf() is bounded (it truncates, never overflows), but -O2 enables a noisy
# format-truncation analysis that errors on safe same-size copies. Keep it as a warning, not error.
target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-format-truncation)

# PROD build override: `idf.py -DDEVICE_FORCE_PROD=1 build` (into a separate build dir) forces the
# production backend and ignores any local provisioned_config.h — no need to move the header, so the LOCAL
# and PROD build dirs both stay warm (no CMake-reconfigure churn). See app_main.c's DEVICE_FORCE_PROD.
if(DEVICE_FORCE_PROD)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE DEVICE_FORCE_PROD=1)
endif()

# LOCAL BACKEND override: `idf.py -DDEVICE_BACKEND_URL="ws://<laptop-ip>:8085" build` points the device
# at a backend on your machine. The URL is otherwise hardcoded to production AND re-forced over whatever
# NVS holds on every boot (app_main.c), so it is not a setting the device can be talked into — a local
# build is the only way. Only the URL changes: the device keeps its provisioned WiFi and SDS credential,
# so there is no need to bake credentials in or re-run setup just to move the socket.
if(DEVICE_BACKEND_URL)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE DEVICE_PROD_BACKEND_URL="${DEVICE_BACKEND_URL}")
endif()

# BRING-UP PROBE: `idf.py -DBOARD_PROBE=1 build` (separate build dir recommended). app_main runs
# board/board_probe.c before the display comes up and prints what is on the I2C bus, which reset pins
# do what, and what each touch driver reads idle. Never set for a release image.
# PANEL BISECT: `idf.py -DPRO_PANEL_DIAG=1 build` on the Pro. No UI, no LVGL — the panel shows its own
# colour bars while the backlight sweeps its whole range, so "the screen is blank" splits into "no video"
# and "no light" without guessing. See board/pro_bringup.c.
if(PRO_PANEL_DIAG)
    target_compile_definitions(${COMPONENT_LIB} PRIVATE PRO_PANEL_DIAG=1)
endif()

# The dial's own probe. The Pro does not need a flag for this: board/pro_bringup.c IS the probe until
# the shared app_main takes the board over.
if(BOARD_PROBE AND NOT IDF_TARGET STREQUAL "esp32p4")
    target_compile_definitions(${COMPONENT_LIB} PRIVATE BOARD_PROBE=1)
    target_sources(${COMPONENT_LIB} PRIVATE "board/board_probe.c")
endif()
