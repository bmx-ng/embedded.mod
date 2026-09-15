#ifndef BLITZMAX_EMBEDDED_UART_H
#define BLITZMAX_EMBEDDED_UART_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t bmx_embedded_uart_controller_count(void);
int32_t bmx_embedded_uart_default_controller(void);
uint32_t bmx_embedded_uart_default_baudrate(void);
int32_t bmx_embedded_uart_configure_pins(int32_t controller, uint32_t tx_pin,
    uint32_t rx_pin);
int32_t bmx_embedded_uart_configure_flow_pins(int32_t controller,
    uint32_t cts_pin, uint32_t rts_pin);
uint32_t bmx_embedded_uart_init(int32_t controller, uint32_t baudrate);
int32_t bmx_embedded_uart_deinit(int32_t controller);
uint32_t bmx_embedded_uart_set_baudrate(int32_t controller, uint32_t baudrate);
int32_t bmx_embedded_uart_set_format(int32_t controller, uint32_t data_bits,
    uint32_t stop_bits, uint32_t parity);
int32_t bmx_embedded_uart_set_flow_control(int32_t controller, int32_t cts,
    int32_t rts);
int32_t bmx_embedded_uart_is_enabled(int32_t controller);
int32_t bmx_embedded_uart_is_writable(int32_t controller);
int32_t bmx_embedded_uart_is_readable(int32_t controller);
int32_t bmx_embedded_uart_is_readable_within_us(int32_t controller,
    uint32_t timeout_us);
int32_t bmx_embedded_uart_write_blocking(int32_t controller,
    const void *source, int32_t length);
int32_t bmx_embedded_uart_read_blocking(int32_t controller,
    void *destination, int32_t length);
int32_t bmx_embedded_uart_read_timeout_us(int32_t controller,
    void *destination, int32_t length, uint32_t timeout_us);
int32_t bmx_embedded_uart_read_available(int32_t controller,
    void *destination, int32_t capacity);
int32_t bmx_embedded_uart_put_byte(int32_t controller, uint32_t value);
int32_t bmx_embedded_uart_tx_wait_blocking(int32_t controller);
int32_t bmx_embedded_uart_set_break(int32_t controller, int32_t enabled);
int32_t bmx_embedded_uart_set_translate_crlf(int32_t controller,
    int32_t enabled);
uint32_t bmx_embedded_uart_get_errors(int32_t controller);
int32_t bmx_embedded_uart_clear_errors(int32_t controller);
int32_t bmx_embedded_uart_async_open(int32_t controller,
    uint32_t rx_capacity, uint32_t tx_capacity, uint32_t rx_token,
    uint32_t tx_token, uint32_t error_token);
int32_t bmx_embedded_uart_async_close(int32_t controller);
int32_t bmx_embedded_uart_async_is_open(int32_t controller);
int32_t bmx_embedded_uart_async_read(int32_t controller, void *destination,
    int32_t capacity);
int32_t bmx_embedded_uart_async_write(int32_t controller, const void *source,
    int32_t length);
uint32_t bmx_embedded_uart_async_read_available(int32_t controller);
uint32_t bmx_embedded_uart_async_write_available(int32_t controller);
uint32_t bmx_embedded_uart_async_rx_dropped(int32_t controller);
int32_t bmx_embedded_uart_async_tx_idle(int32_t controller);

#ifdef __cplusplus
}
#endif

#endif
