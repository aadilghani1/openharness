// Local visual review appliance. Only horizontal swipes have behavior.
// No network, microphone capture, NVS writes or commands to the desktop.
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include "board_pins.h"
#include "pro_panel_bus.h"
#include "touch_ctrl.h"
#include "gallery_assets.h"
#include "driver/gpio.h"
#include "esp_heap_caps.h"
#include "esp_lcd_mipi_dsi.h"
#include "esp_lcd_panel_ops.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_timer.h"
#include "esp_attr.h"
#include "miniz.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

extern const uint8_t blob_start[] asm("_binary_gallery_pack_start");
extern const uint8_t blob_end[] asm("_binary_gallery_pack_end");
static const char *TAG="concepts";
static esp_lcd_panel_handle_t panel;
static SemaphoreHandle_t copied;
static uint16_t *pixels;
static uint32_t frames_drawn,render_max_us,touch_errors;

static bool IRAM_ATTR color_done(esp_lcd_panel_handle_t p,esp_lcd_dpi_panel_event_data_t *ev,void *arg) {
    (void)p;(void)ev;(void)arg;
    BaseType_t woken=pdFALSE;
    xSemaphoreGiveFromISR(copied,&woken);
    return woken==pdTRUE;
}

static void unpack(gallery_asset_t a,size_t count) {
    const size_t length=blob_end-blob_start;
    ESP_ERROR_CHECK(a.off<=length && a.len<=length-a.off ? ESP_OK:ESP_ERR_INVALID_SIZE);
    size_t n=tinfl_decompress_mem_to_mem(pixels,count*2,blob_start+a.off,a.len,TINFL_FLAG_PARSE_ZLIB_HEADER);
    ESP_ERROR_CHECK(n==count*2?ESP_OK:ESP_ERR_INVALID_SIZE);
}

static void draw(gallery_asset_t a,int x,int y,int w,int h) {
    ESP_ERROR_CHECK(w>0&&h>0&&x>=0&&y>=0&&x+w<=720&&y+h<=720?ESP_OK:ESP_ERR_INVALID_SIZE);
    int64_t began=esp_timer_get_time();
    unpack(a,(size_t)w*h);
    // The input buffer is reused only after the actual copy, not merely a scan-out tick.
    while(xSemaphoreTake(copied,0)==pdTRUE) {}
    ESP_ERROR_CHECK(esp_lcd_panel_draw_bitmap(panel,x,y,x+w,y+h,pixels));
    ESP_ERROR_CHECK(xSemaphoreTake(copied,pdMS_TO_TICKS(1000))==pdTRUE?ESP_OK:ESP_ERR_TIMEOUT);
    uint32_t elapsed=esp_timer_get_time()-began;
    if(elapsed>render_max_us)render_max_us=elapsed;
    ++frames_drawn;
}

static void show(unsigned n) {
    const gallery_scene_t *s=&scenes[n];
    draw(s->base,0,0,720,720);
    pro_backlight_set(s->brightness);
    ESP_LOGI(TAG,"page=%u/%u name=%s brightness=%u animation=%u region=%ux%u",n+1,GALLERY_SCENES,s->name,s->brightness,s->frames,s->w,s->h);
}

void app_main(void) {
    const gpio_config_t latch={.pin_bit_mask=1ULL<<BSP_PWR_HOLD,.mode=GPIO_MODE_OUTPUT};
    ESP_ERROR_CHECK(gpio_config(&latch));
    ESP_ERROR_CHECK(gpio_set_level(BSP_PWR_HOLD,1));
    ESP_LOGI(TAG,"Harness Pro concept review: 8 directions + 3 screen profiles");
    pixels=heap_caps_aligned_alloc(64,720*720*2,MALLOC_CAP_SPIRAM|MALLOC_CAP_8BIT);
    ESP_ERROR_CHECK(pixels?ESP_OK:ESP_ERR_NO_MEM);
    unsigned checked=0;
    for(unsigned i=0;i<GALLERY_SCENES;i++) {
        const gallery_scene_t *s=&scenes[i];
        unpack(s->base,720*720);++checked;
        for(unsigned j=0;j<s->frames;j++) {
            unpack(s->anim[j],(size_t)s->w*s->h);++checked;
            vTaskDelay(1);
        }
    }
    ESP_LOGI(TAG,"verified %u image blocks across %u scenes",checked,GALLERY_SCENES);
    copied=xSemaphoreCreateBinary();
    ESP_ERROR_CHECK(copied?ESP_OK:ESP_ERR_NO_MEM);
    pro_backlight_init();
    ESP_ERROR_CHECK(pro_panel_bus_open(&panel,NULL));
    const esp_lcd_dpi_panel_event_callbacks_t cb={.on_color_trans_done=color_done};
    ESP_ERROR_CHECK(esp_lcd_dpi_panel_register_event_callbacks(panel,&cb,NULL));
    esp_lcd_panel_io_handle_t touch_io;
    esp_lcd_touch_handle_t touch;
    ESP_ERROR_CHECK(touch_ctrl_open(&touch_io,&touch)?ESP_OK:ESP_ERR_NOT_FOUND);
    unsigned page=0,frame=0,empty_reads=0;
    uint32_t began=0,next_frame=0,last_report=0;
    bool contact=false;
    int start_x=0,start_y=0,last_x=0,last_y=0;
    show(page);
    esp_ota_mark_app_valid_cancel_rollback();
    ESP_LOGI(TAG,"READY: swipe left/right. taps and holds do nothing. hardware=harness-pro");
    while(true) {
        uint32_t now=(uint32_t)(esp_timer_get_time()/1000);
        esp_err_t err=esp_lcd_touch_read_data(touch);
        if(err==ESP_OK) {
            uint16_t x=0,y=0,strength=0;uint8_t points=0;
            bool down=esp_lcd_touch_get_coordinates(touch,&x,&y,&strength,&points,1)&&points;
            if(down) {
                if(!contact){contact=true;began=now;start_x=x;start_y=y;}
                last_x=x;last_y=y;empty_reads=0;
                if(now-began>5000){contact=false;}
            } else if(contact && ++empty_reads>=3) {
                int dx=last_x-start_x,dy=last_y-start_y;
                if(now-began<2500 && abs(dx)>=65 && abs(dx)>abs(dy)*3/2) {
                    page=(page+GALLERY_SCENES+(dx<0?1:-1))%GALLERY_SCENES;
                    show(page);frame=0;next_frame=now+120;
                }
                contact=false;empty_reads=0;
            }
        } else {++touch_errors;contact=false;}
        const gallery_scene_t *s=&scenes[page];
        if(s->frames && !contact && (int32_t)(now-next_frame)>=0) {
            frame=(frame+1)%s->frames;
            draw(s->anim[frame],s->x,s->y,s->w,s->h);
            next_frame=now+120;
        }
        if(now-last_report>=15000) {
            last_report=now;
            ESP_LOGI(TAG,"alive page=%u frames=%lu render_max_us=%lu touch_errors=%lu heap=%u psram=%u stack=%u",page+1,(unsigned long)frames_drawn,(unsigned long)render_max_us,(unsigned long)touch_errors,(unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),(unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM),(unsigned)uxTaskGetStackHighWaterMark(NULL));
        }
        vTaskDelay(pdMS_TO_TICKS(15));
    }
}
