#ifndef BLITZMAX_EMBEDDED_RANDOM_H
#define BLITZMAX_EMBEDDED_RANDOM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t bmx_embedded_random_uint32(void);
uint64_t bmx_embedded_random_uint64(void);
int32_t bmx_embedded_random_fill(void *buffer, int32_t length);

#ifdef __cplusplus
}
#endif

#endif
