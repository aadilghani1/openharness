"""Check dock power and recovery after a long side-button hold using real drivers."""
from pathlib import Path
import re
import subprocess
import tempfile

fw = Path(__file__).resolve().parent.parent
boot = (fw / 'main/app_main.c').read_text().split('void app_main(void)', 1)[1]
assert boot.index('power_hold_init();') < boot.index('last_words_boot();')
def driver(name):
    return re.sub(r'^#include .*\n', '', (fw / 'main/board' / name).read_text(), flags=re.M)
code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <setjmp.h>
#include "pro_button_filter.h"
#define DEVICE_PRO_COMPANION 1
#define GPIO_PULLUP_DISABLE 0
#define GPIO_PULLUP_ENABLE 1
#define GPIO_PULLDOWN_DISABLE 0
#define GPIO_INTR_DISABLE 0
#define GPIO_MODE_INPUT 1
#define GPIO_MODE_INPUT_OUTPUT 3
#define BSP_PWR_HOLD 1
#define BSP_PWR_BTN 2
#define ESP_OK 0
#define ESP_ERROR_CHECK(e) assert((e)==0)
#define ESP_LOGI(tag, ...) do {(void)tag; printf(__VA_ARGS__); puts("");} while(0)
#define ESP_LOGW ESP_LOGI
#define pdMS_TO_TICKS(ms) (ms)
typedef struct {uint64_t pin_bit_mask;int mode,pull_up_en,pull_down_en,intr_type;} gpio_config_t;
static int latch=-1, latch_writes, configured, locks, back_presses, sleeps, wakes;
static int64_t now;
static bool asleep;
static jmp_buf finished;
static void (*button_task)(void *);
static int gpio_set_level(int pin,int value) {
    assert(pin==BSP_PWR_HOLD && value==0 && !configured);
    latch=value; latch_writes++; return 0;
}
static int gpio_config(const gpio_config_t *cfg) {
    if (cfg->pin_bit_mask==(1ULL<<BSP_PWR_HOLD)) {
        assert(latch==0 && cfg->mode==GPIO_MODE_INPUT_OUTPUT && !cfg->pull_up_en);
        configured++;
    } else {
        assert(cfg->pin_bit_mask==(1ULL<<BSP_PWR_BTN) && cfg->mode==GPIO_MODE_INPUT && cfg->pull_up_en);
    }
    return 0;
}
static int gpio_get_level(int pin) {
    if (pin==BSP_PWR_HOLD) return latch;
    assert(pin==BSP_PWR_BTN);
    return !((now>=100000 && now<6500000) || (now>=6900000 && now<7100000));
}
static int64_t esp_timer_get_time(void) {return now;}
static void display_lock(void) {assert(locks++==0);}
static void display_unlock(void) {assert(--locks==0);}
static bool display_is_asleep(void) {return asleep;}
static void display_sleep(void) {assert(locks==1);asleep=true;sleeps++;}
static void display_wake(void) {assert(locks==1);asleep=false;wakes++;}
static void ui_boot_pressed(void) {back_presses++;}
static void vTaskDelay(int ms) {
    assert(ms==20); now+=(int64_t)ms*1000;
    if(now>=7600000) longjmp(finished,1);
}
static void xTaskCreate(void (*fn)(void*),const char *name,int stack,void *arg,int priority,void *out) {
    (void)name; (void)stack; (void)arg; (void)priority; (void)out; button_task=fn;
}
#define TAG power_tag
'''
code += driver('power_pro.c')
code += '\n#undef TAG\n#define TAG ptt_tag\n' + driver('ptt_pro.c')
code += r'''
int main(void) {
    power_hold_init(); assert(latch==0 && configured==1 && latch_writes==1);
    assert(power_init() && power_init());
    assert(power_battery_pct()==-1 && !power_is_charging() && power_is_on_external());
    assert(!power_take_pwrkey_tap());
    ptt_start(); assert(button_task);
    if(!setjmp(finished)) button_task(NULL);
    // Six-second hold sleeps once; the next tap still wakes and reaches the UI.
    assert(!asleep && sleeps==1 && wakes==1 && back_presses==2 && !locks);
    assert(latch==0 && latch_writes==1);
    puts("Pro dock power: no battery dependency; long hold and subsequent wake PASS");
}
'''
with tempfile.TemporaryDirectory(prefix='harness-pro-power-') as tmp:
    path=Path(tmp)
    (path/'test.c').write_text(code)
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-O1','-g',
                    '-fsanitize=address,undefined','-I',str(fw/'main/board'),
                    str(path/'test.c'),'-o',str(path/'test')],check=True)
    subprocess.run([str(path/'test')],check=True)
