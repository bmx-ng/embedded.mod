#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_events.h"
#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The Stage 2 interrupt test requires opt-in multicore GC"
#endif

enum { INTERRUPT_COUNT = 1000u, INTERRUPT_TOKEN = 0x495251u };
static atomic_uint interrupt_worker_stop;
static atomic_uint interrupt_worker_ready;
static atomic_uint interrupt_post_failed;

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/stdlib.h"
static void interrupt_yield(void) { tight_loop_contents(); }
static int64_t interrupt_alarm(alarm_id_t id, void *argument) {
    (void)id;
    uint32_t index = (uint32_t)(uintptr_t)argument;
    if (!bmx_embedded_event_post_from_isr_ex(INTERRUPT_TOKEN, index,
            index ^ 0x7733u, index + 7u, index + 11u))
        atomic_store_explicit(&interrupt_post_failed, index, memory_order_release);
    return 0;
}
static int interrupt_arm(uint32_t index) {
    return add_alarm_in_us(100u, interrupt_alarm, (void *)(uintptr_t)index,
        false) > 0;
}
static int interrupt_init(void) { return 1; }
static void interrupt_cleanup(void) {}
#elif defined(BMX_ESP32) && BMX_ESP32
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
enum { INTERRUPT_GPIO = GPIO_NUM_4 };
static atomic_uint interrupt_expected;
static void interrupt_yield(void) { taskYIELD(); }
static void interrupt_gpio_handler(void *argument) {
    (void)argument;
    uint32_t index = atomic_load_explicit(&interrupt_expected,
        memory_order_acquire);
    if (!bmx_embedded_event_post_from_isr_ex(INTERRUPT_TOKEN, index,
            index ^ 0x7733u, index + 7u, index + 11u))
        atomic_store_explicit(&interrupt_post_failed, index, memory_order_release);
}
static int interrupt_init(void) {
    gpio_config_t config = {
        .pin_bit_mask = 1ull << INTERRUPT_GPIO,
        .mode = GPIO_MODE_INPUT_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_POSEDGE
    };
    if (gpio_config(&config) != ESP_OK ||
            gpio_set_level(INTERRUPT_GPIO, 0) != ESP_OK ||
            gpio_install_isr_service(0) != ESP_OK ||
            gpio_isr_handler_add(INTERRUPT_GPIO, interrupt_gpio_handler,
                NULL) != ESP_OK) return 0;
    return 1;
}
static int interrupt_arm(uint32_t index) {
    atomic_store_explicit(&interrupt_expected, index, memory_order_release);
    if (gpio_set_level(INTERRUPT_GPIO, 0) != ESP_OK) return 0;
    vTaskDelay(1u);
    return gpio_set_level(INTERRUPT_GPIO, 1) == ESP_OK;
}
static void interrupt_cleanup(void) {
    (void)gpio_isr_handler_remove(INTERRUPT_GPIO);
    gpio_uninstall_isr_service();
    (void)gpio_reset_pin(INTERRUPT_GPIO);
}
#else
#error "The Stage 2 interrupt test supports Pico and ESP32"
#endif

static void interrupt_worker(void *unused) {
    (void)unused;
    atomic_store_explicit(&interrupt_worker_ready, 1u, memory_order_release);
    while (!atomic_load_explicit(&interrupt_worker_stop, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        interrupt_yield();
    }
}

int32_t bmx_embedded_gc_stage2_interrupt_device_test(void) {
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 1;
    atomic_store_explicit(&interrupt_worker_stop, 0u, memory_order_relaxed);
    atomic_store_explicit(&interrupt_worker_ready, 0u, memory_order_relaxed);
    atomic_store_explicit(&interrupt_post_failed, 0u, memory_order_relaxed);
    uint32_t dropped_before = bmx_embedded_event_dropped();
    if (bmx_embedded_event_pending() || !interrupt_init()) return 2;
    if (!bmx_embedded_gc_worker_start(interrupt_worker, NULL)) {
        interrupt_cleanup();
        return 3;
    }
    int32_t failed = 0;
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        if (atomic_load_explicit(&interrupt_worker_ready, memory_order_acquire))
            break;
        if (attempt == 9999999u) failed = 4;
        interrupt_yield();
    }
    for (uint32_t index = 1u; index <= INTERRUPT_COUNT && !failed; ++index) {
        if (!interrupt_arm(index)) { failed = 5; break; }
        (void)bmx_embedded_collect_objects();
        if (!bmx_embedded_heap_integrity_valid()) { failed = 6; break; }
        for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
            uint32_t token, data, mods, x, y;
            if (bmx_embedded_event_take(&token, &data, &mods, &x, &y)) {
                if (token != INTERRUPT_TOKEN || data != index ||
                        mods != (index ^ 0x7733u) ||
                        x != index + 7u || y != index + 11u) failed = 7;
                break;
            }
            if (atomic_load_explicit(&interrupt_post_failed,
                    memory_order_acquire)) { failed = 8; break; }
            if (attempt == 9999999u) failed = 9;
            bmx_embedded_gc_poll();
            interrupt_yield();
        }
    }
    atomic_store_explicit(&interrupt_worker_stop, 1u, memory_order_release);
    int joined = 0;
    for (unsigned attempt = 0; attempt < 100u && !joined; ++attempt)
        joined = bmx_embedded_gc_worker_join(100000u);
    interrupt_cleanup();
    if (!failed && joined != 1) failed = 10;
    if (!failed && (bmx_embedded_event_pending() ||
            bmx_embedded_event_dropped() != dropped_before)) failed = 11;
    return failed;
}
