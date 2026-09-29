#pragma once
#include <stdbool.h>
// Pro-only station setup. Provisioned over the local USB session, never logged.
void pro_wifi_start(void);
bool pro_wifi_configure(const char *ssid, const char *password);
