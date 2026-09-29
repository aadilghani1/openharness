"""Enable the desktop companion in the existing production touch/scene harness.

No board, NVS or serial I/O. Keep the full legacy voice/inbox tests and add the
actual companion request handler, real cJSON, and owner/receipt checks.
"""
import re


def instrument(code, source):
    start = code.index('typedef struct cJSON {')
    end = code.index('static action_t pressed_action;', start)
    code = code[:start] + '#include "cJSON.h"\nenum { JSTRING=cJSON_String,JTRUE=cJSON_True };\n' + code[end:]
    code = '#include "companion.h"\nstatic ht_companion_t desktop_companion;\n' + code
    code = code.replace('static bool queue(action_t a) {', '''
static action_t companion_queued;
static int companion_requests;
static bool queue(action_t a) {
    if (!congestion && a.kind==A_DESKTOP_COMPANION) {companion_requests++;companion_queued=a;}
''')
    for name in ['companion_request', 'companion_dispatch']:
        handler = re.search(r'^static void ' + name + r'\([^\n]*\)\n\{.*?^\}', source, re.M | re.S)
        assert handler
        code = code.replace('static void render_companion(', handler.group(0) + '\nstatic void render_companion(', 1)
    code = code.replace('static void reset(void) {', 'static void reset(void) {\nht_companion_reset(&desktop_companion);companion_requests=0;')
    code = code.replace('else if (a.kind == A_PET) boops++;', '''else if (a.kind == A_DESKTOP_COMPANION) companion_dispatch(a);
    else if (a.kind == A_PET) boops++;''')
    checks = r'''
static void companion_state(const char *phase,const char *stage,uint64_t serial,unsigned epoch) {
    char json[1024];
    snprintf(json,sizeof json,"{\"t\":\"companion.state\",\"v\":1,\"serial\":%llu,\"window\":\"desktop-fixture\",\"epoch\":%u,\"revision\":%llu,\"enabled\":true,\"motion\":true,\"phase\":\"%s\",\"art\":\"fixture\",\"feeling\":{\"emotion\":\"content\",\"reason\":\"settled\"},%s\"egg\":{\"uid\":\"egg-owned\",\"kind\":\"first\",\"stage\":\"%s\"}}",
        (unsigned long long)serial,epoch,(unsigned long long)serial,phase,
        !strcmp(phase,"creature")?"\"creature\":{\"uid\":\"tim-owned\",\"id\":\"tim\",\"name\":\"Tim\",\"version\":\"0.1\",\"seed\":42},":"",stage);
    cJSON *p=cJSON_Parse(json);assert(p);assert(ht_companion_receive(&desktop_companion,p,ms()));cJSON_Delete(p);scene_take();
}
static bool companion_receipt(const char *id,bool ok) {
    cJSON *p=cJSON_CreateObject();cJSON_AddStringToObject(p,"t","companion.action.result");
    cJSON_AddStringToObject(p,"requestId",id);cJSON_AddBoolToObject(p,"ok",ok);
    bool accepted=ht_companion_receive(&desktop_companion,p,ms());cJSON_Delete(p);return accepted;
}
static void companion_checks(void) {
    // The same voice contact works before, during and after hatching.
    const char *stages[]={"p0","p1","p2","p3","p4","rock","burst","tumble","open","hatchling"};
    for(unsigned i=0;i<sizeof stages/sizeof stages[0];i++) {
        reset();companion_state(i<5?"egg":i<9?"hatching":"creature",stages[i],1,7);
        tap(1000,233,220);assert(starts==1&&recording&&!strcmp(target,"a")&&!companion_requests);
        tap(2000,233,220);assert(stops==1&&!recording&&!companion_requests);
    }
    reset();s.count=0;s.active=-1;companion_state("egg","p0",1,7);
    assert(!action_enabled(A_DESKTOP_COMPANION));
    tap(1000,233,220);assert(!companion_requests&&!starts); // Voice needs a recipient, not a grown Tim.
    companion_state("egg","p4",2,7);
    assert(action_enabled(A_DESKTOP_COMPANION)&&!action_enabled(A_INBOX));
    bool hatch_label=false;
    for(int r=0;r<scene.count;r++)if(!strcmp(scene.runs[r].text,"[hatch]")) {
        hatch_label=true;
        assert(scene.runs[r].y>=HT_COMPANION_HATCH_TOP);
        assert(scene.runs[r].y+scene.runs[r].font->height<=HT_COMPANION_HATCH_BOTTOM);
    }
    assert(hatch_label);

    // Hatch works with no panes or inbox, and holds/drags never become speech or hatch.
    habitat_touch(true,233,375,1200);habitat_touch(true,233,220,1300);habitat_touch(false,233,220,1400);
    assert(!companion_requests&&!starts&&!moves);scene_take();
    habitat_touch(true,233,375,1500);surface_tick(2150);habitat_touch(false,233,375,2200);
    assert(s.view==HOME&&!companion_requests&&!starts);scene_take();
    tap(2500,233,375);assert(companion_requests==1&&!starts&&desktop_companion.pending);
    assert(companion_queued.value==1&&!strcmp(companion_queued.id,"egg-owned"));
    assert(companion_queued.revision==7&&!strcmp(companion_queued.text,"desktop-fixture"));
    assert(!strcmp(desktop_companion.phase,"egg")); // Sending is never a local hatch.
    tap(3000,233,375);assert(companion_requests==1&&!starts);
    s.count=2;s.active=0;scene_take();
    tap(4000,233,220);assert(starts==1&&recording&&companion_requests==1); // A pending hatch never gates voice.
    tap(5000,233,220);assert(stops==1&&!recording);
    dispatch((action_t){.kind=A_VOICE_ABORT});
    assert(!companion_receipt("stale-request",true)&&desktop_companion.pending);
    assert(companion_receipt(companion_queued.text+81,true)&&!desktop_companion.pending);
    assert(!strcmp(desktop_companion.phase,"egg")); // Receipt still waits for authoritative state.
    companion_state("creature","hatchling",3,7);
    assert(!action_enabled(A_DESKTOP_COMPANION));
    strcpy(s.agents[0].preview,"Latest result lives in the inbox");s.agents[0].recap_ready=true;scene_take();
    for(int r=0;r<scene.count;r++)assert(!strstr(scene.runs[r].text,"Latest result"));
    ht_companion_disconnect(&desktop_companion);s.connected=false;scene_take();
    assert(!desktop_companion.motion&&!s.hit_count&&title_is("Harness offline"));
    s.connected=true;companion_state("creature","hatchling",1,7);
    tap(6000,233,220);assert(starts==2&&recording&&!strcmp(target,"a"));
    tap(7000,233,220);assert(stops==2&&!recording);
    dispatch((action_t){.kind=A_VOICE_ABORT}); // End the fake upload/result lifetime.
    view(COMPANION);scene_take();assert(action_enabled(A_DESKTOP_COMPANION));
    dispatch(make_action((hit_t){.action=A_DESKTOP_COMPANION,.value=0}));
    assert(companion_requests==2&&companion_queued.value==0&&!strcmp(companion_queued.id,"tim-owned"));
    assert(companion_receipt(companion_queued.text+81,false));assert(desktop_companion.action_error[0]);
    companion_request(2);assert(companion_queued.value==2&&desktop_companion.pending);
    ht_companion_tick(&desktop_companion,desktop_companion.action_deadline,false,true);
    assert(!desktop_companion.pending&&desktop_companion.action_error[0]);
    companion_request(3);assert(companion_queued.value==3&&desktop_companion.pending);
    char old[49];strcpy(old,desktop_companion.action_id);
    companion_state("creature","hatchling",4,8);assert(!desktop_companion.pending&&!desktop_companion.action_error[0]);
    assert(!companion_receipt(old,true));
    congestion=true;companion_request(0);assert(!desktop_companion.pending);
    congestion=false;desktop_companion.enabled=false;companion_request(0);assert(!desktop_companion.pending);

    // Hold keeps the new tab picker, with no companion menu or accidental tab selection.
    for(int egg=0;egg<2;egg++) {
        workspace_setup();companion_state(egg?"egg":"creature",egg?"p4":"hatchling",1,7);
        habitat_touch(true,233,220,1000);surface_tick(1650);scene_take();
        assert(s.view==TABS&&!action_enabled(A_SETTINGS)&&!starts&&!companion_requests);
        habitat_touch(false,233,320,1800);assert(!tab_switches&&!starts&&!companion_requests);
    }
    // Hatch, bell and voice never overlap, even if a notification disappears under a finger.
    reset();companion_state("egg","p4",1,7);
    ui_notify_task_done("b","Pane B","M2","A result");scene_take();
    assert(action_enabled(A_INBOX)&&action_enabled(A_DESKTOP_COMPANION));
    for(int i=0;i<s.hit_count;i++)for(int j=i+1;j<s.hit_count;j++) {
        ht_rect_t a=s.hits[i].rect,b=s.hits[j].rect;
        assert(a.x+a.w<=b.x||b.x+b.w<=a.x||a.y+a.h<=b.y||b.y+b.h<=a.y);
    }
    habitat_touch(true,233,430,1000);ui_notif_seen("b");scene_take();habitat_touch(false,233,430,1075);
    assert(!starts&&!companion_requests);
    view(HOME);scene_take();tap(2000,233,375);assert(companion_requests==1&&!starts);

    // A changed account or replaced ready egg cannot inherit an old finger's hatch.
    for(int replacement=0;replacement<2;replacement++) {
        reset();companion_state("egg","p4",1,7);
        habitat_touch(true,233,375,1000);
        if(replacement)strcpy(desktop_companion.egg_uid,"replacement-egg");
        else companion_state("egg","p4",2,8);
        habitat_touch(false,233,375,1075);assert(!companion_requests&&!starts);
    }
    reset();puts("Desktop companion touch: voice at every life stage, separate hatch/bell, hold-to-tabs, owner, receipts, pending voice, timeout and queue refusal PASS");
}
'''
    marker = 'int main(int argc, char **argv) {'
    assert code.count(marker) == 1
    return code.replace(marker, checks + marker + '\ncompanion_checks();\n')
