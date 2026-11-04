#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>

#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The Stage 2 publication device test requires opt-in multicore GC"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/multicore.h"
#include "pico/stdlib.h"
static void publication_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void publication_yield(void) { taskYIELD(); }
#else
#error "The Stage 2 publication device test supports Pico and ESP32"
#endif

typedef struct PublicationNode {
    BMXEmbeddedObject object;
    struct PublicationNode *next;
    uint32_t value;
} PublicationNode;

static const uint32_t node_references[] = {offsetof(PublicationNode, next)};
static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "PublicationNode", .instance_size = sizeof(PublicationNode),
    .reference_offsets = node_references, .reference_count = 1u
};
static BMXEmbeddedAtomicReference shared_object;
static BMXEmbeddedAtomicReference shared_array;
static BMXEmbeddedAtomicReference shared_string;
static atomic_uint state;
static atomic_uint command;

static int wait_state(unsigned expected) {
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        unsigned value = atomic_load_explicit(&state, memory_order_acquire);
        if (value == expected) return 1;
        if (value > expected) return 0;
        publication_yield();
    }
    return 0;
}

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
static void publication_worker(void) {
#else
static void publication_worker(void *unused) {
    (void)unused;
#endif
    if (bmx_embedded_gc_multicore_register() != 1u) {
        atomic_store_explicit(&state, 9u, memory_order_release);
        return;
    }
    PublicationNode *node = NULL;
    BMXEmbeddedArray *array = NULL;
    BMXEmbeddedString *text = NULL;
    BMXEmbeddedRootSlot slots[] = {
        {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL},
        {&array, BMX_EMBEDDED_ROOT_ARRAY, NULL},
        {&text, BMX_EMBEDDED_ROOT_STRING, NULL}
    };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, 3u);
    node = bmx_embedded_object_allocate(&node_type);
    array = bmx_embedded_array_new_1d(1, sizeof(uint32_t),
        BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
    text = bmx_embedded_string_allocate(1);
    if (!node || !array || !text) {
        atomic_store_explicit(&state, 10u, memory_order_release);
        return;
    }
    node->next = node;
    node->value = 11u;
    *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) = 12u;
    ((uint16_t *)text->buf)[0] = 'A';
    bmx_embedded_atomic_reference_store(&shared_object, node);
    bmx_embedded_atomic_reference_store(&shared_array, array);
    bmx_embedded_atomic_reference_store(&shared_string, text);
    node = NULL;
    array = NULL;
    text = NULL;
    atomic_store_explicit(&state, 1u, memory_order_release);

    while (!atomic_load_explicit(&command, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        publication_yield();
    }
    node = bmx_embedded_atomic_reference_load(&shared_object);
    array = bmx_embedded_atomic_reference_load(&shared_array);
    text = bmx_embedded_atomic_reference_load(&shared_string);
    if (!node || node->next != node || node->value != 22u ||
        *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) != 23u ||
        text->buf[0] != 'B') {
        atomic_store_explicit(&state, 11u, memory_order_release);
        return;
    }
    node->value = 31u;
    *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) = 32u;
    ((uint16_t *)text->buf)[0] = 'C';
    node = NULL;
    array = NULL;
    text = NULL;
    atomic_store_explicit(&state, 2u, memory_order_release);

    while (atomic_load_explicit(&command, memory_order_acquire) == 1u) {
        bmx_embedded_gc_poll();
        publication_yield();
    }
    bmx_embedded_root_frame_leave(&frame);
    atomic_store_explicit(&state,
        bmx_embedded_gc_multicore_unregister() ? 3u : 12u, memory_order_release);
#if defined(BMX_ESP32) && BMX_ESP32
    vTaskDelete(NULL);
#endif
}

int32_t bmx_embedded_gc_stage2_publication_device_test(void) {
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 1;
    if (!bmx_embedded_arena_capacity()) return 2;
    (void)bmx_embedded_collect_objects();
    uint32_t objects = bmx_embedded_object_live_count();
    uint32_t arrays = bmx_embedded_array_live_count();
    uint32_t strings = bmx_embedded_string_live_count();
    BMXEmbeddedRootSlot slots[] = {
        {&shared_object, BMX_EMBEDDED_ROOT_ATOMIC_OBJECT, NULL},
        {&shared_array, BMX_EMBEDDED_ROOT_ATOMIC_ARRAY, NULL},
        {&shared_string, BMX_EMBEDDED_ROOT_ATOMIC_STRING, NULL}
    };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, 3u);
#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
    multicore_launch_core1(publication_worker);
#else
    TaskHandle_t worker = NULL;
    if (xTaskCreatePinnedToCore(publication_worker, "gc-publish", 2048, NULL,
            tskIDLE_PRIORITY + 1, &worker, 1) != pdPASS) return 3;
#endif
    if (!wait_state(1u)) return 4;
    (void)bmx_embedded_collect_objects();
    if (bmx_embedded_object_live_count() != objects + 1u ||
        bmx_embedded_array_live_count() != arrays + 1u ||
        bmx_embedded_string_live_count() != strings + 1u ||
        bmx_embedded_invalid_reference_count() != 0u ||
        !bmx_embedded_heap_integrity_valid()) return 5;

    PublicationNode *node = bmx_embedded_atomic_reference_load(&shared_object);
    BMXEmbeddedArray *array = bmx_embedded_atomic_reference_load(&shared_array);
    BMXEmbeddedString *text = bmx_embedded_atomic_reference_load(&shared_string);
    if (!node || node->next != node || node->value != 11u ||
        *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) != 12u ||
        text->buf[0] != 'A') return 6;
    node->value = 22u;
    *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) = 23u;
    ((uint16_t *)text->buf)[0] = 'B';
    node = NULL;
    array = NULL;
    text = NULL;
    atomic_store_explicit(&command, 1u, memory_order_release);
    if (!wait_state(2u)) return 7;
    node = bmx_embedded_atomic_reference_load(&shared_object);
    array = bmx_embedded_atomic_reference_load(&shared_array);
    text = bmx_embedded_atomic_reference_load(&shared_string);
    if (node->value != 31u ||
        *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) != 32u ||
        text->buf[0] != 'C') return 8;
    node = NULL;
    array = NULL;
    text = NULL;
    bmx_embedded_atomic_reference_store(&shared_object, NULL);
    bmx_embedded_atomic_reference_store(&shared_array, NULL);
    bmx_embedded_atomic_reference_store(&shared_string, NULL);
    (void)bmx_embedded_collect_objects();
    if (bmx_embedded_object_live_count() != objects ||
        bmx_embedded_array_live_count() != arrays ||
        bmx_embedded_string_live_count() != strings ||
        !bmx_embedded_heap_integrity_valid()) return 9;
    atomic_store_explicit(&command, 2u, memory_order_release);
    if (!wait_state(3u)) return 10;
    bmx_embedded_root_frame_leave(&frame);
    /* The generated BlitzMax main still owns its global root frame. */
    return 0;
}
