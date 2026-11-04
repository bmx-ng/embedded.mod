#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The Stage 2 finalizer device test requires opt-in multicore GC"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/multicore.h"
#include "pico/stdlib.h"
static void finalizer_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void finalizer_yield(void) { taskYIELD(); }
#else
#error "The Stage 2 finalizer device test supports Pico and ESP32"
#endif

typedef struct FinalizerNode {
    BMXEmbeddedObject object;
    uint32_t value;
} FinalizerNode;
static atomic_uint ready;
static atomic_uint run_worker;
static atomic_uint worker_progress;
static atomic_uint worker_done;
static atomic_uint worker_exit;
static atomic_uint worker_exited;
static atomic_uint finalizer_calls;
static atomic_uint failed;

static void finalizer(void *object) {
    FinalizerNode *node = object;
    if (node->value != 0x1234u) atomic_store_explicit(&failed, 1u, memory_order_release);
    unsigned count = atomic_fetch_add_explicit(&finalizer_calls, 1u, memory_order_acq_rel) + 1u;
    if (count == 1u) atomic_store_explicit(&run_worker, 1u, memory_order_release);
    if (count == 2u) {
        for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
            if (atomic_load_explicit(&worker_progress, memory_order_acquire)) break;
            finalizer_yield();
        }
        if (!atomic_load_explicit(&worker_progress, memory_order_acquire))
            atomic_store_explicit(&failed, 2u, memory_order_release);
    }
}

static const BMXEmbeddedTypeDescriptor finalizable_type = {
    .name = "FinalizerNode", .instance_size = sizeof(FinalizerNode),
    .flags = BMX_EMBEDDED_TYPE_FLAG_HAS_FINALIZER, .finalizer = finalizer
};
static const BMXEmbeddedTypeDescriptor ordinary_type = {
    .name = "OrdinaryNode", .instance_size = sizeof(FinalizerNode)
};

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
static void finalizer_worker(void) {
#else
static void finalizer_worker(void *unused) {
    (void)unused;
#endif
    if (bmx_embedded_gc_multicore_register() != 1u) {
        atomic_store_explicit(&failed, 3u, memory_order_release);
        return;
    }
    FinalizerNode *node = NULL;
    BMXEmbeddedRootSlot slot = {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1u);
    atomic_store_explicit(&ready, 1u, memory_order_release);
    while (!atomic_load_explicit(&run_worker, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        finalizer_yield();
    }
    for (unsigned index = 0; index < 300u; ++index) {
        node = bmx_embedded_object_allocate(&ordinary_type);
        if (!node) {
            atomic_store_explicit(&failed, 4u, memory_order_release);
            return;
        }
        node->value = index;
        atomic_fetch_add_explicit(&worker_progress, 1u, memory_order_release);
        finalizer_yield();
    }
    node = NULL;
    atomic_store_explicit(&worker_done, 1u, memory_order_release);
    while (!atomic_load_explicit(&worker_exit, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        finalizer_yield();
    }
    bmx_embedded_root_frame_leave(&frame);
    if (!bmx_embedded_gc_multicore_unregister())
        atomic_store_explicit(&failed, 5u, memory_order_release);
    atomic_store_explicit(&worker_exited, 1u, memory_order_release);
#if defined(BMX_ESP32) && BMX_ESP32
    vTaskDelete(NULL);
#endif
}

static int wait_flag(atomic_uint *flag) {
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        if (atomic_load_explicit(flag, memory_order_acquire)) return 1;
        if (atomic_load_explicit(&failed, memory_order_acquire)) return 0;
        finalizer_yield();
    }
    return 0;
}

int32_t bmx_embedded_gc_stage2_finalizer_device_test(void) {
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 1;
    if (!bmx_embedded_arena_capacity()) return 2;
    (void)bmx_embedded_collect_objects();
    uint32_t baseline = bmx_embedded_object_live_count();
#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
    multicore_launch_core1(finalizer_worker);
#else
    TaskHandle_t worker = NULL;
    if (xTaskCreatePinnedToCore(finalizer_worker, "gc-finalize", 2048, NULL,
            tskIDLE_PRIORITY + 1, &worker, 1) != pdPASS) return 3;
#endif
    if (!wait_flag(&ready)) return 4;
    for (unsigned index = 0; index < 24u; ++index) {
        FinalizerNode *node = bmx_embedded_object_allocate(&finalizable_type);
        if (!node) return 5;
        node->value = 0x1234u;
    }
    (void)bmx_embedded_collect_objects();
    if (!wait_flag(&worker_done)) return 6;
    if (atomic_load_explicit(&failed, memory_order_acquire) ||
        atomic_load_explicit(&finalizer_calls, memory_order_acquire) != 24u ||
        bmx_embedded_finalizer_invocation_count() != 24u ||
        !bmx_embedded_heap_integrity_valid()) return 7;
    (void)bmx_embedded_collect_objects();
    if (bmx_embedded_object_live_count() != baseline ||
        bmx_embedded_finalizer_invocation_count() != 24u ||
        !bmx_embedded_heap_integrity_valid()) return 8;
    atomic_store_explicit(&worker_exit, 1u, memory_order_release);
    if (!wait_flag(&worker_exited)) return 9;
    return atomic_load_explicit(&failed, memory_order_acquire) ? 10 : 0;
}
