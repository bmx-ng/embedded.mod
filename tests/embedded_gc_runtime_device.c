/* Stage 1 target integration: the worker holds roots and polls but never
   allocates or mutates the managed heap. Compile only with GC multicore on. */
#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The runtime device test requires the opt-in GC multicore build"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/multicore.h"
#include "pico/stdlib.h"
static void bmx_device_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void bmx_device_yield(void) { taskYIELD(); }
#else
#error "The runtime device test supports Pico and ESP32"
#endif

typedef struct BMXDeviceNode {
    BMXEmbeddedObject object;
    uint32_t value;
} BMXDeviceNode;

static const BMXEmbeddedTypeDescriptor bmx_device_node_type = {
    .name = "BMXDeviceNode", .instance_size = sizeof(BMXDeviceNode)
};
static atomic_uintptr_t bmx_device_handoff;
static atomic_uint bmx_device_mode;
static atomic_uint bmx_device_ready;
static atomic_uint bmx_device_observed;
static atomic_uint bmx_device_done;

static int bmx_device_wait_for(atomic_uint *value, unsigned expected) {
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        if (atomic_load_explicit(value, memory_order_acquire) == expected) return 1;
        bmx_device_yield();
    }
    return 0;
}

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
static void bmx_device_worker(void) {
#else
static void bmx_device_worker(void *unused) {
    (void)unused;
#endif
    uint32_t slot = bmx_embedded_gc_multicore_register();
    if (slot != 1u) {
        atomic_store_explicit(&bmx_device_ready, 2u, memory_order_release);
        return;
    }
    BMXDeviceNode *root = (BMXDeviceNode *)atomic_load_explicit(
        &bmx_device_handoff, memory_order_acquire);
    BMXEmbeddedRootSlot root_slot = {&root, BMX_EMBEDDED_ROOT_OBJECT, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &root_slot, 1u);
    atomic_store_explicit(&bmx_device_ready, 1u, memory_order_release);
    for (;;) {
        unsigned mode = atomic_load_explicit(&bmx_device_mode, memory_order_acquire);
        if (mode == 3u) break;
        if (mode == 1u) {
            root = NULL;
            atomic_store_explicit(&bmx_device_observed, 1u, memory_order_release);
            while (atomic_load_explicit(&bmx_device_mode, memory_order_acquire) == 1u)
                bmx_embedded_gc_poll();
        } else if (mode == 2u) {
            atomic_store_explicit(&bmx_device_observed, 2u, memory_order_release);
            while (atomic_load_explicit(&bmx_device_mode, memory_order_acquire) == 2u)
                bmx_device_yield();
            atomic_store_explicit(&bmx_device_observed, 0u, memory_order_release);
        } else {
            bmx_embedded_gc_poll();
            bmx_device_yield();
        }
    }
    bmx_embedded_root_frame_leave(&frame);
    atomic_store_explicit(&bmx_device_done,
        bmx_embedded_gc_multicore_unregister() ? 1u : 2u, memory_order_release);
#if defined(BMX_ESP32) && BMX_ESP32
    vTaskDelete(NULL);
#endif
}

int32_t bmx_embedded_gc_runtime_device_test(void) {
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 1;
    (void)bmx_embedded_collect_objects();
    uint32_t baseline = bmx_embedded_object_live_count();
    BMXDeviceNode *node = (BMXDeviceNode *)bmx_embedded_object_allocate(&bmx_device_node_type);
    if (!node) return 2;
    node->value = 123u;
    atomic_store_explicit(&bmx_device_handoff, (uintptr_t)node, memory_order_release);
#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
    multicore_launch_core1(bmx_device_worker);
#else
    TaskHandle_t worker = NULL;
    if (xTaskCreatePinnedToCore(bmx_device_worker, "gc-runtime", 2048, NULL,
            tskIDLE_PRIORITY + 1, &worker, 1) != pdPASS) return 3;
#endif
    if (!bmx_device_wait_for(&bmx_device_ready, 1u)) return 4;
    node = NULL;
    BMXDeviceNode *garbage = (BMXDeviceNode *)bmx_embedded_object_allocate(
        &bmx_device_node_type);
    if (!garbage) return 5;
    garbage = NULL;
    if (!bmx_embedded_collect_objects() ||
        bmx_embedded_object_live_count() != baseline + 1u ||
        !bmx_embedded_heap_integrity_valid()) return 5;

    atomic_store_explicit(&bmx_device_mode, 1u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_observed, 1u)) return 6;
    (void)bmx_embedded_collect_objects();
    if (bmx_embedded_object_live_count() != baseline ||
        !bmx_embedded_heap_integrity_valid()) return 7;

    node = (BMXDeviceNode *)bmx_embedded_object_allocate(&bmx_device_node_type);
    if (!node) return 8;
    node = NULL;
    uint32_t before_timeout = bmx_embedded_object_live_count();
    atomic_store_explicit(&bmx_device_mode, 2u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_observed, 2u)) return 9;
    (void)bmx_embedded_collect_objects();
    if (bmx_embedded_object_live_count() != before_timeout ||
        !bmx_embedded_heap_integrity_valid()) return 10;
    atomic_store_explicit(&bmx_device_mode, 0u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_observed, 0u)) return 11;
    (void)bmx_embedded_collect_objects();
    if (bmx_embedded_object_live_count() != baseline ||
        !bmx_embedded_heap_integrity_valid()) return 12;

    atomic_store_explicit(&bmx_device_mode, 3u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_done, 1u)) return 13;
    return 0;
}
