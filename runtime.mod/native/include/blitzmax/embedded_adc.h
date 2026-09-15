#ifndef BLITZMAX_EMBEDDED_ADC_H
#define BLITZMAX_EMBEDDED_ADC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t bmx_embedded_adc_is_valid_pin(uint32_t gpio);
int32_t bmx_embedded_adc_init_pin(uint32_t gpio);
int32_t bmx_embedded_adc_deinit_pin(uint32_t gpio);
int32_t bmx_embedded_adc_read_raw(uint32_t gpio, uint32_t *value);
uint32_t bmx_embedded_adc_resolution_bits(uint32_t gpio);
uint32_t bmx_embedded_adc_maximum_value(uint32_t gpio);

#ifdef __cplusplus
}
#endif

#endif
