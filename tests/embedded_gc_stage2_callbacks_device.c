#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_events.h"
#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The Stage 2 callback test requires opt-in multicore GC"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/stdlib.h"
static void callback_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void callback_yield(void) { taskYIELD(); }
#else
#error "The Stage 2 callback test supports Pico and ESP32"
#endif

enum { CALLBACK_COUNT = 10000u };
static atomic_uint callback_ack;
static atomic_uint callback_done;
static atomic_uint callback_failed;
static uint32_t callback_token;

static void callback_worker(void *unused) {
    (void)unused;
    for (uint32_t index = 1u; index <= CALLBACK_COUNT; ++index) {
        if (!bmx_embedded_event_post_ex(callback_token, index,
                index ^ 0x5a5au, index + 7u, index + 11u)) {
            atomic_store_explicit(&callback_failed, index, memory_order_release);
            break;
        }
        for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
            if (atomic_load_explicit(&callback_ack, memory_order_acquire) == index)
                break;
            bmx_embedded_gc_poll();
            callback_yield();
            if (attempt == 9999999u)
                atomic_store_explicit(&callback_failed, index, memory_order_release);
        }
        if (atomic_load_explicit(&callback_failed, memory_order_acquire)) break;
    }
    atomic_store_explicit(&callback_done, 1u, memory_order_release);
}

int32_t bmx_embedded_gc_stage2_callbacks_start(uint32_t token) {
    if (!token) return 0;
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 0;
    callback_token = token;
    atomic_store_explicit(&callback_ack, 0u, memory_order_relaxed);
    atomic_store_explicit(&callback_done, 0u, memory_order_relaxed);
    atomic_store_explicit(&callback_failed, 0u, memory_order_relaxed);
    return bmx_embedded_gc_worker_start(callback_worker, NULL);
}

void bmx_embedded_gc_stage2_callbacks_ack(uint32_t index) {
    atomic_store_explicit(&callback_ack, index, memory_order_release);
}

int32_t bmx_embedded_gc_stage2_callbacks_done(void) {
    return atomic_load_explicit(&callback_done, memory_order_acquire) != 0u;
}

uint32_t bmx_embedded_gc_stage2_callbacks_failed(void) {
    return atomic_load_explicit(&callback_failed, memory_order_acquire);
}

int32_t bmx_embedded_gc_stage2_callbacks_join(void) {
    for (unsigned attempt = 0; attempt < 100u; ++attempt) {
        int joined = bmx_embedded_gc_worker_join(100000u);
        if (joined) return joined;
    }
    return 0;
}
