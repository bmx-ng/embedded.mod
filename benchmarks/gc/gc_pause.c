#include <stdatomic.h>
#include <stdint.h>
#include <blitzmax/embedded_runtime.h>

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/stdlib.h"
static void benchmark_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void benchmark_yield(void) { taskYIELD(); }
#else
#error "The pause benchmark supports Pico and ESP32"
#endif

static atomic_uint worker_ready;
static atomic_uint worker_run = 1u;

int32_t bmx_gc_pause_prepare(void) {
#if BMX_EMBEDDED_MULTICORE
    bmx_embedded_gc_multicore_initialize();
    return bmx_embedded_gc_multicore_register() == 0u;
#else
    return 0;
#endif
}

void bmx_gc_pause_worker_ready(void) {
    atomic_store_explicit(&worker_ready, 1u, memory_order_release);
}

uint32_t bmx_gc_pause_ready(void) {
    return atomic_load_explicit(&worker_ready, memory_order_acquire);
}

uint32_t bmx_gc_pause_run(void) {
    return atomic_load_explicit(&worker_run, memory_order_acquire);
}

void bmx_gc_pause_stop(void) {
    atomic_store_explicit(&worker_run, 0u, memory_order_release);
}

void bmx_gc_pause_yield(void) { benchmark_yield(); }
