#ifndef BLITZMAX_EMBEDDED_GPIO_H
#define BLITZMAX_EMBEDDED_GPIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t bmx_embedded_gpio_is_valid(uint32_t gpio);
int32_t bmx_embedded_gpio_is_output_capable(uint32_t gpio);
int32_t bmx_embedded_gpio_is_pull_capable(uint32_t gpio);
int32_t bmx_embedded_gpio_init(uint32_t gpio);
int32_t bmx_embedded_gpio_set_direction(uint32_t gpio, int32_t direction);
int32_t bmx_embedded_gpio_get_direction(uint32_t gpio);
int32_t bmx_embedded_gpio_set_input(uint32_t gpio);
int32_t bmx_embedded_gpio_set_output(uint32_t gpio);
int32_t bmx_embedded_gpio_get(uint32_t gpio);
int32_t bmx_embedded_gpio_put(uint32_t gpio, int32_t value);
int32_t bmx_embedded_gpio_get_output(uint32_t gpio);
int32_t bmx_embedded_gpio_set_pulls(uint32_t gpio, int32_t pull_up, int32_t pull_down);
int32_t bmx_embedded_gpio_pull_up(uint32_t gpio);
int32_t bmx_embedded_gpio_pull_down(uint32_t gpio);
int32_t bmx_embedded_gpio_disable_pulls(uint32_t gpio);
int32_t bmx_embedded_gpio_is_pulled_up(uint32_t gpio);
int32_t bmx_embedded_gpio_is_pulled_down(uint32_t gpio);
int32_t bmx_embedded_gpio_set_drive_strength(uint32_t gpio, int32_t drive_strength);
int32_t bmx_embedded_gpio_get_drive_strength(uint32_t gpio);
int32_t bmx_embedded_gpio_set_irq_enabled(uint32_t gpio, uint32_t event_mask,
    int32_t enabled);
int32_t bmx_embedded_gpio_set_event_token(uint32_t gpio, uint32_t token);
uint32_t bmx_embedded_gpio_pending_irq_events(uint32_t gpio);
uint32_t bmx_embedded_gpio_take_irq_events(uint32_t gpio);

#ifdef __cplusplus
}
#endif

#endif
