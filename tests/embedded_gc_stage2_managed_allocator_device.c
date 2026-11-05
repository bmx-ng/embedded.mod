#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The Stage 2 allocator device test requires opt-in multicore GC"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/multicore.h"
#include "pico/stdlib.h"
static void bmx_stage2_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void bmx_stage2_yield(void) { taskYIELD(); }
#else
#error "The Stage 2 allocator device test supports Pico and ESP32"
#endif

typedef struct BMXStage2Node {
    BMXEmbeddedObject object;
    uint32_t value;
} BMXStage2Node;

static const BMXEmbeddedTypeDescriptor bmx_stage2_node_type = {
    .name = "BMXStage2Node", .instance_size = sizeof(BMXStage2Node)
};
static atomic_uint bmx_stage2_state;
static atomic_uint bmx_stage2_command;

static int bmx_stage2_wait(unsigned state) {
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        if (atomic_load_explicit(&bmx_stage2_state, memory_order_acquire) == state) return 1;
        bmx_stage2_yield();
    }
    return 0;
}

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
static void bmx_stage2_worker(void) {
#else
static void bmx_stage2_worker(void *unused) {
    (void)unused;
#endif
    if (bmx_embedded_gc_multicore_register() != 1u) {
        atomic_store_explicit(&bmx_stage2_state, 9u, memory_order_release);
        return;
    }
    BMXStage2Node *node = NULL;
    BMXEmbeddedArray *array = NULL;
    BMXEmbeddedString *text = NULL;
    BMXEmbeddedRootSlot slots[] = {
        {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL},
        {&array, BMX_EMBEDDED_ROOT_ARRAY, NULL},
        {&text, BMX_EMBEDDED_ROOT_STRING, NULL}
    };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, 3u);
    node = (BMXStage2Node *)bmx_embedded_object_allocate(&bmx_stage2_node_type);
    array = bmx_embedded_array_new_1d(8, sizeof(uint32_t),
        BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
    text = bmx_embedded_string_allocate(4);
    if (!node || !array || !text) {
        atomic_store_explicit(&bmx_stage2_state, 8u, memory_order_release);
        return;
    }
    node->value = 123u;
    ((uint16_t *)text->buf)[0] = 'T';

    BMXEmbeddedExceptionFrame exception_frame;
    bmx_embedded_exception_enter(&exception_frame);
    if (setjmp(exception_frame.buffer) == 0) {
        (void)bmx_embedded_string_allocate(40000);
        atomic_store_explicit(&bmx_stage2_state, 7u, memory_order_release);
        return;
    }
    BMXEmbeddedException caught = bmx_embedded_exception_catch();
    if (caught.kind != BMX_EMBEDDED_EXCEPTION_STRING) {
        atomic_store_explicit(&bmx_stage2_state, 6u, memory_order_release);
        return;
    }

    /* The rooted worker blocks in native code while the owner collects. */
    if (!bmx_embedded_gc_enter_native_safe()) {
        atomic_store_explicit(&bmx_stage2_state, 10u, memory_order_release);
        return;
    }
    atomic_store_explicit(&bmx_stage2_state, 1u, memory_order_release);
    while (atomic_load_explicit(&bmx_stage2_command, memory_order_acquire) == 0u) {
        bmx_stage2_yield();
    }
    if (!bmx_embedded_gc_leave_native_safe()) {
        atomic_store_explicit(&bmx_stage2_state, 11u, memory_order_release);
        return;
    }
    if (node->value != 123u || text->buf[0] != 'T' || array->length != 8) {
        atomic_store_explicit(&bmx_stage2_state, 5u, memory_order_release);
        return;
    }
    node = NULL;
    array = NULL;
    text = NULL;
    atomic_store_explicit(&bmx_stage2_state, 2u, memory_order_release);
    while (atomic_load_explicit(&bmx_stage2_command, memory_order_acquire) == 1u) {
        bmx_embedded_gc_poll();
        bmx_stage2_yield();
    }
    bmx_embedded_root_frame_leave(&frame);
    atomic_store_explicit(&bmx_stage2_state,
        bmx_embedded_gc_multicore_unregister() ? 3u : 4u, memory_order_release);
#if defined(BMX_ESP32) && BMX_ESP32
    vTaskDelete(NULL);
#endif
}

int32_t bmx_embedded_gc_stage2_managed_allocator_device_test(void) {
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 1;
    if (!bmx_embedded_arena_capacity()) return 2;
    (void)bmx_embedded_collect_objects();
    uint32_t objects = bmx_embedded_object_live_count();
    uint32_t arrays = bmx_embedded_array_live_count();
    uint32_t strings = bmx_embedded_string_live_count();
#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
    multicore_launch_core1(bmx_stage2_worker);
#else
    TaskHandle_t worker = NULL;
    if (xTaskCreatePinnedToCore(bmx_stage2_worker, "gc-stage2", 2048, NULL,
            tskIDLE_PRIORITY + 1, &worker, 1) != pdPASS) return 3;
#endif
    if (!bmx_stage2_wait(1u)) return 4;
    (void)bmx_embedded_collect_objects();
    if (bmx_embedded_object_live_count() != objects + 1u ||
        bmx_embedded_array_live_count() != arrays + 1u ||
        bmx_embedded_string_live_count() != strings + 1u ||
        !bmx_embedded_heap_integrity_valid()) return 5;
    atomic_store_explicit(&bmx_stage2_command, 1u, memory_order_release);
    if (!bmx_stage2_wait(2u)) return 6;
    (void)bmx_embedded_collect_objects();
    if (bmx_embedded_object_live_count() != objects ||
        bmx_embedded_array_live_count() != arrays ||
        bmx_embedded_string_live_count() != strings ||
        !bmx_embedded_heap_integrity_valid()) return 7;
    atomic_store_explicit(&bmx_stage2_command, 2u, memory_order_release);
    if (!bmx_stage2_wait(3u)) return 8;
    return 0;
}
