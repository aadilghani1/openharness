#pragma once
#include "terminal.h"

/*
 * The Claude Code pet (claude_pet.c, scripts/gen_claude_pet.py): four loops of 24 steps, each step a
 * de-duplicated frame and a vertical offset in px, advanced every ht_claude_pet_step_ms[state].
 */
typedef enum { HT_PET_IDLE, HT_PET_WORKING, HT_PET_DONE, HT_PET_ASKING, HT_PET_STATES } ht_pet_state_t;
typedef struct { uint8_t frame; int8_t dy; } ht_pet_step_t;
enum { HT_PET_W = 60, HT_PET_H = 45, HT_PET_STEPS = 24 };

extern const unsigned ht_claude_pet_frame_count;
extern const ht_icon_t ht_claude_pet_frames[];
extern const ht_pet_step_t ht_claude_pet_loops[HT_PET_STATES][HT_PET_STEPS];
extern const uint16_t ht_claude_pet_step_ms[HT_PET_STATES];
