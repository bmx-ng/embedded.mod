#ifndef BLITZMAX_EMBEDDED_EVENTS_H
#define BLITZMAX_EMBEDDED_EVENTS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t bmx_embedded_event_post(uint32_t token, uint32_t event_data,
    uint32_t detail);
int32_t bmx_embedded_event_post_ex(uint32_t token, uint32_t event_data,
    uint32_t event_mods, uint32_t event_x, uint32_t event_y);
int32_t bmx_embedded_event_post_from_isr(uint32_t token,
    uint32_t event_data, uint32_t detail);
int32_t bmx_embedded_event_post_from_isr_ex(uint32_t token,
    uint32_t event_data, uint32_t event_mods, uint32_t event_x,
    uint32_t event_y);
int32_t bmx_embedded_event_take(uint32_t *token, uint32_t *event_data,
    uint32_t *event_mods, uint32_t *event_x, uint32_t *event_y);
uint32_t bmx_embedded_event_pending(void);
uint32_t bmx_embedded_event_dropped(void);

#ifdef __cplusplus
}
#endif

#endif
