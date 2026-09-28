#pragma once
#include "terminal.h"
typedef enum {
    HT_TIM_CONTENT, HT_TIM_WORKING, HT_TIM_ATTENTION, HT_TIM_DONE,
    HT_TIM_OFFLINE, HT_TIM_ASLEEP, HT_TIM_BOOPED, HT_TIM_LISTENING
} ht_tim_mood_t;
typedef struct { int8_t look; uint8_t hands, level; bool blink, pressed; } ht_tim_pose_t;
typedef struct {
    ht_tim_pose_t pose;
    ht_tim_mood_t mood;
    uint32_t next_blink, blink_until, reaction_at, reaction_until, release_until;
    uint32_t activity, sequence, next_ms, level_at;
    bool initialized, was_down;
} ht_tim_motion_t;
// Sparse blink deadlines and finite event reactions. No heap, animation thread or hidden-screen work.
bool ht_tim_motion_tick(ht_tim_motion_t *m, uint32_t now, ht_tim_mood_t mood,
                        bool quiet, bool visible, bool down, int x, unsigned level, uint32_t activity);
void ht_tim_portrait(ht_scene_t *scene, int y, ht_tim_mood_t mood, uint16_t ink);
typedef struct {
    const char *recipient, *status, *hint, *detail;
    ht_tim_mood_t mood;
    ht_tim_pose_t pose;
    bool focus, carrying, footer_action, straight_title, unread, primary_title, roomy_reading;
    uint16_t ink, foreground, dim;
} ht_tim_face_t;
void ht_tim_face(ht_scene_t *scene, const ht_tim_face_t *face);
