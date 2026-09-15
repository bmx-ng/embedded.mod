#ifndef BLITZMAX_EMBEDDED_SPI_H
#define BLITZMAX_EMBEDDED_SPI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t bmx_embedded_spi_controller_count(void);
int32_t bmx_embedded_spi_default_controller(void);
uint32_t bmx_embedded_spi_default_rx_pin(void);
uint32_t bmx_embedded_spi_default_tx_pin(void);
uint32_t bmx_embedded_spi_default_sck_pin(void);
uint32_t bmx_embedded_spi_default_csn_pin(void);
int32_t bmx_embedded_spi_configure_pins(int32_t controller, uint32_t rx_pin,
    uint32_t tx_pin, uint32_t sck_pin);
uint32_t bmx_embedded_spi_init(int32_t controller, uint32_t baudrate);
int32_t bmx_embedded_spi_deinit(int32_t controller);
uint32_t bmx_embedded_spi_set_baudrate(int32_t controller, uint32_t baudrate);
uint32_t bmx_embedded_spi_get_baudrate(int32_t controller);
int32_t bmx_embedded_spi_set_format(int32_t controller, uint32_t data_bits,
    uint32_t polarity, uint32_t phase, uint32_t bit_order);
int32_t bmx_embedded_spi_write_read_blocking(int32_t controller, void *source,
    void *destination, int32_t length);
int32_t bmx_embedded_spi_write_blocking(int32_t controller, void *source, int32_t length);
int32_t bmx_embedded_spi_read_blocking(int32_t controller, uint32_t repeated_data,
    void *destination, int32_t length);
int32_t bmx_embedded_spi_write16_read16_blocking(int32_t controller, uint16_t *source,
    uint16_t *destination, int32_t length);
int32_t bmx_embedded_spi_write16_blocking(int32_t controller, uint16_t *source,
    int32_t length);
int32_t bmx_embedded_spi_read16_blocking(int32_t controller, uint32_t repeated_data,
    uint16_t *destination, int32_t length);

#ifdef __cplusplus
}
#endif

#endif
