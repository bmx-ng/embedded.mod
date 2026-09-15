#ifndef BLITZMAX_EMBEDDED_DEVICE_H
#define BLITZMAX_EMBEDDED_DEVICE_H

#include <stdint.h>

#include "blitzmax/embedded_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

#define BMX_EMBEDDED_RESET_REASON_UNKNOWN 0
#define BMX_EMBEDDED_RESET_REASON_POWER_ON 1
#define BMX_EMBEDDED_RESET_REASON_EXTERNAL 2
#define BMX_EMBEDDED_RESET_REASON_SOFTWARE 3
#define BMX_EMBEDDED_RESET_REASON_WATCHDOG 4
#define BMX_EMBEDDED_RESET_REASON_PANIC 5
#define BMX_EMBEDDED_RESET_REASON_DEEP_SLEEP 6
#define BMX_EMBEDDED_RESET_REASON_BROWNOUT 7
#define BMX_EMBEDDED_RESET_REASON_POWER_GLITCH 8
#define BMX_EMBEDDED_RESET_REASON_CPU_LOCKUP 9

const BMXEmbeddedString *bmx_embedded_unique_device_id(void);
BMXEmbeddedArray *bmx_embedded_unique_device_id_bytes(void);
int32_t bmx_embedded_device_reset_reason(void);
int32_t bmx_embedded_device_reboot(uint32_t delay_ms);

#ifdef __cplusplus
}
#endif

#endif
