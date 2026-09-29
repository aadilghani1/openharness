set(FW "${CMAKE_CURRENT_LIST_DIR}/../../../firmware/main")
idf_component_register(
    SRCS "gallery.c" "${FW}/ui/pro_panel_bus.c" "${FW}/ui/touch_gt911.c" "${FW}/board/board_i2c.c"
    INCLUDE_DIRS "." "${FW}/ui" "${FW}/board"
    REQUIRES esp_lcd esp_driver_gpio esp_driver_ledc esp_driver_i2c esp_timer esp_psram app_update
    EMBED_FILES "gallery.pack")
