#ifndef BLITZMAX_EMBEDDED_TIME_H
#define BLITZMAX_EMBEDDED_TIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint64_t bmx_embedded_time_microseconds(void);
uint64_t bmx_embedded_time_milliseconds(void);
void bmx_embedded_sleep_milliseconds(uint32_t milliseconds);
void bmx_embedded_sleep_microseconds(uint64_t microseconds);

#ifdef __cplusplus
}
#endif

#endif
