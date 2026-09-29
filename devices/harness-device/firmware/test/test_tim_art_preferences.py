"""Validate the real one-time illustrated Tim preference migration."""
from pathlib import Path
import re, subprocess, tempfile
fw=Path(__file__).resolve().parent.parent
source=(fw/'main/config_store.c').read_text()
function=re.search(r'bool config_select_illustrated_tim_once\(void\)\n\{.*?^\}',source,re.M|re.S).group()
code='\n#include <assert.h>\n#include <stdbool.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\ntypedef int nvs_handle_t; typedef int esp_err_t;\nenum {ESP_OK=0, ESP_ERR_NVS_NOT_FOUND=1,NVS_READWRITE=2};\nstatic const char *NS="pair";\nstatic uint8_t character=1,mark;\nstatic unsigned writes,closes,opens;\nstatic int failure;\nstatic int nvs_open(const char *ns,int mode,int *h){assert(!strcmp(ns,NS)&&mode==NVS_READWRITE);if(failure==1)return -1;opens++;*h=1;return 0;}\nstatic int nvs_get_u8(int h,const char *key,uint8_t *v){assert(h==1&&!strcmp(key,"tim_art"));if(failure==2)return -1;if(!mark)return ESP_ERR_NVS_NOT_FOUND;*v=mark;return 0;}\nstatic int nvs_set_u8(int h,const char *key,uint8_t v){assert(h==1);writes++;if(failure==3)return -1;if(!strcmp(key,"habitat_char")){assert(v==0);character=v;}else{assert(!strcmp(key,"tim_art")&&v==1&&character==0);mark=v;}return 0;}\nstatic int nvs_commit(int h){assert(h==1);return failure==4?-1:0;}\nstatic void nvs_close(int h){assert(h==1);closes++;}\n'+function+'int main(void){\n for(failure=1;failure<=3;failure++){assert(!config_select_illustrated_tim_once());assert(character==1&&mark==0);}\n failure=0;assert(config_select_illustrated_tim_once()&&character==0&&mark==1);\n unsigned count=writes;character=1;\n assert(config_select_illustrated_tim_once()&&character==1&&writes==count);\n assert(opens==closes);puts("Illustrated Tim migration: one-time selection, later Tux choice preserved, failed reads/writes PASS");\n}\n'
with tempfile.TemporaryDirectory(prefix='tim-art-preferences-') as folder:
    p=Path(folder)
    (p/'test.c').write_text(code)
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',str(p/'test.c'),'-o',str(p/'test')],check=True)
    subprocess.run([str(p/'test')],check=True)
