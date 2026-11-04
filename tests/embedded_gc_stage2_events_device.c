#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_events.h"
#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The Stage 2 event test requires opt-in multicore GC"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/stdlib.h"
static void event_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void event_yield(void) { taskYIELD(); }
#else
#error "The Stage 2 event test supports Pico and ESP32"
#endif

enum { EVENT_COUNT = 100000u, EVENT_TOKEN = 0x535432u };

typedef struct EventJob {
    atomic_uint finished;
    atomic_uint failed;
} EventJob;

static void event_worker(void *argument) {
    EventJob *job = argument;
    for (uint32_t index = 1u; index <= EVENT_COUNT; ++index) {
        while (bmx_embedded_event_pending() >= 30u) {
            bmx_embedded_gc_poll();
            event_yield();
        }
        if (!bmx_embedded_event_post_ex(EVENT_TOKEN, index,
                index ^ 0x55aa55aau, index + 7u, index + 11u)) {
            atomic_store_explicit(&job->failed, index, memory_order_release);
            break;
        }
        if ((index & 255u) == 0u) bmx_embedded_gc_poll();
    }
    atomic_store_explicit(&job->finished, 1u, memory_order_release);
}

int32_t bmx_embedded_gc_stage2_events_device_test(void) {
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 1;
    EventJob job;
    atomic_init(&job.finished, 0u);
    atomic_init(&job.failed, 0u);
    uint32_t dropped_before = bmx_embedded_event_dropped();
    if (bmx_embedded_event_pending()) return 2;
    if (!bmx_embedded_gc_worker_start(event_worker, &job)) return 3;
    uint32_t received = 0u;
    uint32_t idle = 0u;
    while (received < EVENT_COUNT) {
        uint32_t token, data, mods, x, y;
        if (bmx_embedded_event_take(&token, &data, &mods, &x, &y)) {
            ++received;
            idle = 0u;
            if (token != EVENT_TOKEN || data != received ||
                    mods != (received ^ 0x55aa55aau) ||
                    x != received + 7u || y != received + 11u) return 4;
            if ((received & 1023u) == 0u) {
                (void)bmx_embedded_collect_objects();
                if (!bmx_embedded_heap_integrity_valid()) return 5;
            }
        } else {
            if (atomic_load_explicit(&job.failed, memory_order_acquire)) return 6;
            if (atomic_load_explicit(&job.finished, memory_order_acquire) &&
                    !bmx_embedded_event_pending()) return 7;
            if (++idle == 10000000u) return 8;
            bmx_embedded_gc_poll();
            event_yield();
        }
    }
    int joined = 0;
    for (unsigned attempt = 0; attempt < 100u && !joined; ++attempt)
        joined = bmx_embedded_gc_worker_join(100000u);
    if (joined != 1) return 9;
    if (bmx_embedded_event_pending() ||
            bmx_embedded_event_dropped() != dropped_before) return 10;
    return 0;
}
