#ifndef BLITZMAX_EMBEDDED_I2C_H
#define BLITZMAX_EMBEDDED_I2C_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t bmx_embedded_i2c_controller_count(void);
int32_t bmx_embedded_i2c_default_controller(void);
uint32_t bmx_embedded_i2c_default_sda_pin(void);
uint32_t bmx_embedded_i2c_default_scl_pin(void);
int32_t bmx_embedded_i2c_configure_pins(int32_t controller, uint32_t sda_pin,
    uint32_t scl_pin, int32_t pull_ups);
uint32_t bmx_embedded_i2c_init(int32_t controller, uint32_t baudrate);
int32_t bmx_embedded_i2c_deinit(int32_t controller);
uint32_t bmx_embedded_i2c_set_baudrate(int32_t controller, uint32_t baudrate);
int32_t bmx_embedded_i2c_write_blocking(int32_t controller, uint32_t address,
    void *data, int32_t length);
int32_t bmx_embedded_i2c_read_blocking(int32_t controller, uint32_t address,
    void *data, int32_t length);
int32_t bmx_embedded_i2c_write_timeout_us(int32_t controller, uint32_t address,
    void *data, int32_t length, uint32_t timeout_us);
int32_t bmx_embedded_i2c_read_timeout_us(int32_t controller, uint32_t address,
    void *data, int32_t length, uint32_t timeout_us);
int32_t bmx_embedded_i2c_write_read_blocking(int32_t controller, uint32_t address,
    void *write_data, int32_t write_length, void *read_data, int32_t read_length);
int32_t bmx_embedded_i2c_write_read_timeout_us(int32_t controller, uint32_t address,
    void *write_data, int32_t write_length, void *read_data, int32_t read_length,
    uint32_t timeout_us);

#ifdef __cplusplus
}
#endif

#endif
