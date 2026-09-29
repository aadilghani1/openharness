#include "gestures.h"
#include <stdlib.h>
#ifdef DEVICE_PRO_COMPANION
#define MOTION_PX 24
#define TAP_MAX_MS 649
#else
#define MOTION_PX 12
#define TAP_MAX_MS 350
#endif

void ht_gesture_cancel(ht_gesture_t *g)
{
    g->live = false;
    // Preserve the voice guard across its resulting screen transition.
}
void ht_gesture_guard(ht_gesture_t *g, uint32_t now)
{
    g->guard_valid = true;
    g->guard_until = now + 450;
}
void ht_gesture_begin(ht_gesture_t *g, int x, int y, uint32_t now, uint32_t context)
{
    (void)context; // No multi-contact gesture state; the UI cancels on target/view changes.
    if (g->live) ht_gesture_cancel(g);
    g->guarded = g->guard_valid && (int32_t)(now - g->guard_until) < 0;
    if (!g->guarded) g->guard_valid = false;
    g->x = x; g->y = y; g->began = now;
    g->live = true; g->moved = false; g->axis = 0;
}
void ht_gesture_move(ht_gesture_t *g, int x, int y)
{
    if (!g->live) return;
    int dx = x - g->x, dy = y - g->y;
#ifdef DEVICE_PRO_COMPANION
    if (abs(dx) >= MOTION_PX || abs(dy) >= MOTION_PX) {
        g->moved = true;
        if (!g->axis && abs(dx) * 4 > abs(dy) * 5) g->axis = 2;
        else if (!g->axis && abs(dy) * 4 > abs(dx) * 5) g->axis = 1;
    }
#else
    if (dx * dx + dy * dy >= MOTION_PX * MOTION_PX) {
        g->moved = true;
        if (!g->axis) g->axis = abs(dx) > abs(dy) ? 2 : 1;
    }
#endif
}
ht_touch_result_t ht_gesture_end(ht_gesture_t *g, int x, int y, uint32_t now)
{
    if (!g->live) return HT_TOUCH_NONE;
    ht_gesture_move(g, x, y);
    g->live = false;
    uint32_t duration = now - g->began;
    if (g->moved || g->guarded) {
        return HT_TOUCH_NONE;
    }
    if (duration < 25 || duration > TAP_MAX_MS) {
        return duration >= 650 && duration <= 1800 ? HT_TOUCH_HOLD : HT_TOUCH_NONE;
    }
    return HT_TOUCH_TAP;
}
