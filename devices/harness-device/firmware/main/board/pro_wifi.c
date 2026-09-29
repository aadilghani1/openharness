#include "pro_wifi.h"
#include "cable_link.h"
#include "cJSON.h"
#include "driver/usb_serial_jtag.h"
#include "esp_event.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "nvs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char ssid[33], password[65]; } credentials_t;
static QueueHandle_t requests;
static atomic_bool reconnect;
static atomic_bool unavailable;
static const char *TAG = "pro-wifi";
static void status(const char *state, const char *ip, int reason)
{
    cJSON *m=cJSON_CreateObject();
    if(!m)return;
    cJSON_AddStringToObject(m,"t","wifi.state");
    cJSON_AddStringToObject(m,"state",state);
    cJSON_AddNumberToObject(m,"reason",reason);
    if(ip)cJSON_AddStringToObject(m,"ip",ip);
    char *wire=cJSON_PrintUnformatted(m);
    if(wire){cable_link_send(CABLE_TYPE_JSON,(const uint8_t*)wire,strlen(wire));free(wire);}
    cJSON_Delete(m);
}
static void event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void)arg;
    if(base==WIFI_EVENT && id==WIFI_EVENT_STA_START)atomic_store(&reconnect,true);
    if(base==WIFI_EVENT && id==WIFI_EVENT_STA_DISCONNECTED){
        const wifi_event_sta_disconnected_t *e=data;
        ESP_LOGI(TAG,"station disconnected reason=%d",e->reason);
        status("disconnected",NULL,e->reason);atomic_store(&reconnect,true);
    }
    if(base==IP_EVENT && id==IP_EVENT_STA_GOT_IP){
        const ip_event_got_ip_t *e=data;char ip[16];
        snprintf(ip,sizeof ip,IPSTR,IP2STR(&e->ip_info.ip));
        ESP_LOGI(TAG,"station connected ip=%s",ip);
        status("connected",ip,0);atomic_store(&reconnect,false);
    }
}
static bool load(credentials_t *c)
{
    nvs_handle_t nvs;if(nvs_open("pro_wifi",NVS_READONLY,&nvs)!=ESP_OK)return false;
    size_t size=sizeof *c;esp_err_t e=nvs_get_blob(nvs,"station",c,&size);nvs_close(nvs);
    return e==ESP_OK && size==sizeof *c && c->ssid[0] && !c->ssid[32] && !c->password[64];
}
static bool save(const credentials_t *c)
{
    nvs_handle_t nvs;if(nvs_open("pro_wifi",NVS_READWRITE,&nvs)!=ESP_OK)return false;
    esp_err_t e=nvs_set_blob(nvs,"station",c,sizeof *c);
    if(e==ESP_OK)e=nvs_commit(nvs);
    nvs_close(nvs);
    return e==ESP_OK;
}
static bool initialize(void)
{
    esp_err_t e=esp_netif_init();if(e!=ESP_OK)return false;
    e=esp_event_loop_create_default();if(e!=ESP_OK && e!=ESP_ERR_INVALID_STATE)return false;
    if(!esp_netif_create_default_wifi_sta())return false;
    if(esp_event_handler_register(WIFI_EVENT,ESP_EVENT_ANY_ID,event,NULL)!=ESP_OK)return false;
    if(esp_event_handler_register(IP_EVENT,IP_EVENT_STA_GOT_IP,event,NULL)!=ESP_OK)return false;
    wifi_init_config_t cfg=WIFI_INIT_CONFIG_DEFAULT();
    e=esp_wifi_init(&cfg);
    if(e!=ESP_OK){ESP_LOGE(TAG,"radio init failed (%s)",esp_err_to_name(e));return false;}
    return esp_wifi_set_storage(WIFI_STORAGE_RAM)==ESP_OK && esp_wifi_set_mode(WIFI_MODE_STA)==ESP_OK;
}
static void probe_network(const char *ssid)
{
    wifi_band_mode_t band=0;
    esp_err_t e=esp_wifi_get_band_mode(&band);
    ESP_LOGI(TAG,"radio band=%d result=%s",(int)band,esp_err_to_name(e));
    wifi_scan_config_t scan={0};
    scan.ssid=(uint8_t*)ssid;
    scan.show_hidden=true;
    e=esp_wifi_scan_start(&scan,true);
    uint16_t count=1;wifi_ap_record_t ap={0};
    if(e==ESP_OK)e=esp_wifi_scan_get_ap_records(&count,&ap);
    // No surrounding SSIDs or credentials are exposed by this diagnostic.
    ESP_LOGI(TAG,"configured network scan result=%s matches=%u channel=%u rssi=%d auth=%d",
        esp_err_to_name(e),(unsigned)(e==ESP_OK?count:0),
        (unsigned)ap.primary,(int)ap.rssi,(int)ap.authmode);
    status(e==ESP_OK && count?"network-found":"network-not-found",NULL,e);
}
static void task(void *arg)
{
    (void)arg;credentials_t credentials={0};
    // Let app_main return and the idle task reclaim its internal stack. UI and
    // USB are already live; this only defers cold radio initialization.
    vTaskDelay(pdMS_TO_TICKS(100));
    bool pending=load(&credentials), ready=false, started=false;
    for(;;){
        if(!pending)pending=xQueueReceive(requests,&credentials,pdMS_TO_TICKS(3000))==pdTRUE;
        if(pending){
            if(!ready)ready=initialize();
            if(!ready){
                atomic_store(&unavailable,true);
                status("radio-unavailable",NULL,1);
                memset(&credentials,0,sizeof credentials);
                break;
            }
            if(started){atomic_store(&reconnect,false);esp_wifi_disconnect();}
            wifi_config_t config={0};
            memcpy(config.sta.ssid,credentials.ssid,strlen(credentials.ssid));
            memcpy(config.sta.password,credentials.password,strlen(credentials.password));
            config.sta.threshold.authmode=WIFI_AUTH_WPA2_PSK;
            config.sta.threshold.rssi=-127;
            config.sta.scan_method=WIFI_ALL_CHANNEL_SCAN;
            config.sta.pmf_cfg.capable=true;
            esp_err_t e=esp_wifi_set_config(WIFI_IF_STA,&config);
            memset(&config,0,sizeof config);
            bool stored=e==ESP_OK && save(&credentials);
            pending=false;
            if(!stored){memset(&credentials,0,sizeof credentials);status("configuration-failed",NULL,2);continue;}
            if(!started){
                e=esp_wifi_start();started=e==ESP_OK;
                if(started){
                    esp_err_t band_error=esp_wifi_set_band_mode(WIFI_BAND_MODE_AUTO);
                    ESP_LOGI(TAG,"automatic 2.4/5 GHz band selection (%s)",esp_err_to_name(band_error));
                    probe_network(credentials.ssid);
                }
            }else e=esp_wifi_connect();
            memset(&credentials,0,sizeof credentials);
            ESP_LOGI(TAG,"station configured (%s)",esp_err_to_name(e));
            status(e==ESP_OK?"connecting":"start-failed",NULL,e);
        }else if(ready && started && atomic_exchange(&reconnect,false)){
            esp_err_t e=esp_wifi_connect();
            if(e!=ESP_OK){atomic_store(&reconnect,true);ESP_LOGW(TAG,"retry (%s)",esp_err_to_name(e));}
        }
    }
    vTaskDeleteWithCaps(NULL);
}
void pro_wifi_start(void)
{
    if(requests)return;
    requests=xQueueCreate(1,sizeof(credentials_t));if(!requests)return;
    if(xTaskCreateWithCaps(task,"pro_wifi",6144,NULL,3,NULL,MALLOC_CAP_SPIRAM|MALLOC_CAP_8BIT)!=pdPASS){
        vQueueDelete(requests);requests=NULL;ESP_LOGE(TAG,"no station task");
    }
}
bool pro_wifi_configure(const char *ssid,const char *password)
{
    if(!requests || atomic_load(&unavailable) || !usb_serial_jtag_is_connected() || !ssid || !password)return false;
    size_t n=strlen(ssid),p=strlen(password);
    if(!n || n>32 || p<8 || p>63)return false;
    credentials_t c={0};memcpy(c.ssid,ssid,n);memcpy(c.password,password,p);
    bool ok=xQueueOverwrite(requests,&c)==pdTRUE;memset(&c,0,sizeof c);return ok;
}
