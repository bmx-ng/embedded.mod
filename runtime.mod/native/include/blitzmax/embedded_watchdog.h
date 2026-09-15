#ifndef BLITZMAX_EMBEDDED_WATCHDOG_H
#define BLITZMAX_EMBEDDED_WATCHDOG_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t bmx_embedded_watchdog_maximum_delay_ms(void);
int32_t bmx_embedded_watchdog_enable(uint32_t delay_ms);
int32_t bmx_embedded_watchdog_disable(void);
int32_t bmx_embedded_watchdog_feed(void);
int32_t bmx_embedded_watchdog_is_enabled(void);
int32_t bmx_embedded_watchdog_caused_reboot(void);

#ifdef __cplusplus
}
#endif

#endif
