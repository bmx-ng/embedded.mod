#ifndef BLITZMAX_EMBEDDED_PWM_H
#define BLITZMAX_EMBEDDED_PWM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BMX_EMBEDDED_PWM_DUTY_MAXIMUM 65535u

int32_t bmx_embedded_pwm_is_valid_pin(uint32_t gpio);
uint32_t bmx_embedded_pwm_init_pin(uint32_t gpio, uint32_t frequency,
    uint32_t duty, int32_t inverted);
int32_t bmx_embedded_pwm_deinit_pin(uint32_t gpio);
uint32_t bmx_embedded_pwm_set_pin_frequency(uint32_t gpio, uint32_t frequency);
uint32_t bmx_embedded_pwm_get_pin_frequency(uint32_t gpio);
int32_t bmx_embedded_pwm_set_pin_duty(uint32_t gpio, uint32_t duty);
uint32_t bmx_embedded_pwm_get_pin_duty(uint32_t gpio);
int32_t bmx_embedded_pwm_set_pin_polarity(uint32_t gpio, int32_t inverted);
int32_t bmx_embedded_pwm_get_pin_polarity(uint32_t gpio);
int32_t bmx_embedded_pwm_set_pin_enabled(uint32_t gpio, int32_t enabled);
int32_t bmx_embedded_pwm_get_pin_enabled(uint32_t gpio);

#ifdef __cplusplus
}
#endif

#endif
