#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The managed worker device test requires the opt-in GC multicore build"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/multicore.h"
#include "pico/stdlib.h"
static void bmx_managed_worker_yield_platform(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void bmx_managed_worker_yield_platform(void) { taskYIELD(); }
#else
#error "The managed worker device test supports Pico and ESP32"
#endif

/* The application unit owns this generated global function. */
extern int32_t _bb_main_ManagedWorkerHold(void *node);

static atomic_uintptr_t bmx_managed_worker_handoff;
static atomic_uint bmx_managed_worker_state;
static atomic_uint bmx_managed_worker_command;

int32_t bmx_gc_managed_worker_mode(void) {
    return (int32_t)atomic_load_explicit(&bmx_managed_worker_command, memory_order_acquire);
}

void bmx_gc_managed_worker_set_mode(int32_t mode) {
    atomic_store_explicit(&bmx_managed_worker_command, (unsigned)mode, memory_order_release);
}

void bmx_gc_managed_worker_ready(void) {
    atomic_store_explicit(&bmx_managed_worker_state, 1u, memory_order_release);
}

void bmx_gc_managed_worker_released(void) {
    atomic_store_explicit(&bmx_managed_worker_state, 2u, memory_order_release);
}

void bmx_gc_managed_worker_yield(void) {
    bmx_managed_worker_yield_platform();
}

int32_t bmx_gc_managed_worker_wait(int32_t state) {
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        if (atomic_load_explicit(&bmx_managed_worker_state, memory_order_acquire) == (unsigned)state)
            return 1;
        bmx_managed_worker_yield_platform();
    }
    return 0;
}

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
static void bmx_managed_worker_entry(void) {
#else
static void bmx_managed_worker_entry(void *unused) {
    (void)unused;
#endif
    if (bmx_embedded_gc_multicore_register() != 1u) {
        atomic_store_explicit(&bmx_managed_worker_state, 4u, memory_order_release);
        return;
    }
    void *node = (void *)atomic_load_explicit(&bmx_managed_worker_handoff, memory_order_acquire);
    int32_t result = _bb_main_ManagedWorkerHold(node);
    if (!bmx_embedded_gc_multicore_unregister() || result)
        atomic_store_explicit(&bmx_managed_worker_state, 4u, memory_order_release);
    else
        atomic_store_explicit(&bmx_managed_worker_state, 3u, memory_order_release);
#if defined(BMX_ESP32) && BMX_ESP32
    vTaskDelete(NULL);
#endif
}

int32_t bmx_gc_managed_worker_start(void *node) {
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 0;
    atomic_store_explicit(&bmx_managed_worker_handoff, (uintptr_t)node, memory_order_release);
#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
    multicore_launch_core1(bmx_managed_worker_entry);
    return 1;
#else
    TaskHandle_t worker = NULL;
    return xTaskCreatePinnedToCore(bmx_managed_worker_entry, "gc-managed", 2048, NULL,
        tskIDLE_PRIORITY + 1, &worker, 1) == pdPASS;
#endif
}
