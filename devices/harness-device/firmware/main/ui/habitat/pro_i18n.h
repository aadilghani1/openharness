#pragma once
#include <string.h>
#include <stddef.h>

// Call only for built-in interface copy. Never translate user content, names,
// model IDs, protocol fields, or the words in an English voice audition.
static inline const char *pro_translate(const char *language, const char *text)
{
    if (!text || strcmp(language, "vi")) return text;
    static const struct { const char *english, *vietnamese; } strings[] = {
#include "pro_strings.inc"
    };
    size_t lo = 0, hi = sizeof strings / sizeof strings[0];
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        int cmp = strcmp(text, strings[mid].english);
        if (cmp < 0) hi = mid;
        else if (cmp > 0) lo = mid + 1;
        else return strings[mid].vietnamese;
    }
    return text;
}
