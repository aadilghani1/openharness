#pragma once

// One charcoal surface, two neutral inks, one companion/action accent.
// Canvas matches the desktop terminal pane and Cmd N / Cmd P surfaces.
// All colors are RGB565-representable at full brightness. Conversion and the
// existing saved brightness setting remain at the UI boundary; no theme heap.
#define HT_THEME_CANVAS    0x181818u
#define HT_THEME_TEXT      0xefe7deu
#define HT_THEME_SECONDARY 0xada6adu
#define HT_THEME_ACCENT    0xc6aaefu
#define HT_THEME_SELECTION 0x392c4au
#define HT_THEME_ERROR     0xe7a6adu
