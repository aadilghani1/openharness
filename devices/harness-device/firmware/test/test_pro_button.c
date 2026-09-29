#include "../main/board/pro_button_filter.h"
#include <assert.h>
#include <stdio.h>

int main(void)
{
    pro_button_filter_t s = {0};
    assert(!pro_button_sample(&s, false, 0));
    assert(!pro_button_sample(&s, true, 20));
    assert(!pro_button_sample(&s, false, 40));
    assert(!pro_button_sample(&s, true, 60));
    assert(!pro_button_sample(&s, true, 120));
    assert(pro_button_sample(&s, true, 140));
    assert(pro_button_sample(&s, true, 6000));
    assert(pro_button_sample(&s, false, 6020));
    assert(!pro_button_sample(&s, false, 6100));
    for (unsigned i = 0; i < 100; i++)
        assert(!pro_button_sample(&s, !(i & 1), 7000 + i * 20));
    assert(s.noisy);
    assert(!pro_button_sample(&s, false, 8980 + 1000));
    assert(!s.noisy);
    assert(!pro_button_sample(&s, true, 10000));
    assert(pro_button_sample(&s, true, 10080));
    s = (pro_button_filter_t){0};
    assert(!pro_button_sample(&s, true, UINT32_MAX - 40));
    assert(pro_button_sample(&s, true, 40));
    puts("Pro button: bounce, valid hold/release, noise quarantine/recovery, clock wrap PASS");
}
