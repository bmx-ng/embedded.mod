#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The Stage 2 stress test requires opt-in multicore GC"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/stdlib.h"
static void stress_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void stress_yield(void) { taskYIELD(); }
#else
#error "The Stage 2 stress test supports Pico and ESP32"
#endif

enum { STRESS_ROUNDS = 10000u };
typedef struct StressNode {
    BMXEmbeddedObject object;
    struct StressNode *next;
    uint32_t value;
} StressNode;
static const uint32_t node_references[] = {offsetof(StressNode, next)};
static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "StressNode", .instance_size = sizeof(StressNode),
    .reference_offsets = node_references, .reference_count = 1u
};
static const BMXEmbeddedTypeDescriptor oversized_type = {
    .name = "OversizedNode", .instance_size = 70u * 1024u
};
static BMXEmbeddedAtomicReference shared_object;
static BMXEmbeddedAtomicReference shared_array;
static BMXEmbeddedAtomicReference shared_string;
static atomic_uint stress_state;
static atomic_uint stress_failed;

static int wait_state(unsigned expected) {
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        unsigned state = atomic_load_explicit(&stress_state, memory_order_acquire);
        if (state == expected) return 1;
        if (state == 9u) return 0;
        bmx_embedded_gc_poll();
        stress_yield();
    }
    return 0;
}

static int expect_oom(unsigned kind) {
    BMXEmbeddedExceptionFrame frame;
    bmx_embedded_exception_enter(&frame);
    if (setjmp(frame.buffer) == 0) {
        if (kind == 0u) (void)bmx_embedded_object_allocate(&oversized_type);
        else if (kind == 1u) (void)bmx_embedded_array_new_1d(20000,
            sizeof(uint32_t), BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
        else (void)bmx_embedded_string_allocate(40000);
        bmx_embedded_exception_leave();
        return 0;
    }
    return bmx_embedded_exception_catch().kind == BMX_EMBEDDED_EXCEPTION_STRING;
}

static void stress_worker(void *unused) {
    (void)unused;
    for (uint32_t round = 1u; round <= STRESS_ROUNDS; ++round) {
        if (!wait_state(4u)) goto failed;
        atomic_store_explicit(&stress_state, 0u, memory_order_release);
        if (!wait_state(5u)) goto failed;
        StressNode *node = NULL;
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
            bmx_embedded_root_frame_leave(&frame);
            goto failed;
        }
        node->next = node;
        node->value = round;
        *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) = round;
        ((uint16_t *)text->buf)[0] = (uint16_t)('A' + round % 26u);
        if ((round & 127u) == 0u &&
                (!expect_oom(0u) || !expect_oom(1u) || !expect_oom(2u))) {
            bmx_embedded_root_frame_leave(&frame);
            goto failed;
        }
        bmx_embedded_atomic_reference_store(&shared_object, node);
        bmx_embedded_atomic_reference_store(&shared_array, array);
        bmx_embedded_atomic_reference_store(&shared_string, text);
        node = NULL;
        array = NULL;
        text = NULL;
        atomic_store_explicit(&stress_state, 1u, memory_order_release);
        if (!wait_state(2u)) {
            bmx_embedded_root_frame_leave(&frame);
            goto failed;
        }
        node = bmx_embedded_atomic_reference_load(&shared_object);
        array = bmx_embedded_atomic_reference_load(&shared_array);
        text = bmx_embedded_atomic_reference_load(&shared_string);
        if (!node || node->next != node || node->value != round + 100000u ||
                !array || *(uint32_t *)bmx_embedded_array_element(array, 0,
                    sizeof(uint32_t)) != round + 200000u ||
                !text || text->buf[0] != (uint16_t)('a' + round % 26u)) {
            bmx_embedded_root_frame_leave(&frame);
            goto failed;
        }
        node = NULL;
        array = NULL;
        text = NULL;
        bmx_embedded_atomic_reference_store(&shared_object, NULL);
        bmx_embedded_atomic_reference_store(&shared_array, NULL);
        bmx_embedded_atomic_reference_store(&shared_string, NULL);
        bmx_embedded_root_frame_leave(&frame);
        atomic_store_explicit(&stress_state, 3u, memory_order_release);
    }
    return;
failed:
    atomic_store_explicit(&stress_failed, 1u, memory_order_release);
    atomic_store_explicit(&stress_state, 9u, memory_order_release);
}

int32_t bmx_embedded_gc_stage2_stress_device_test(void) {
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 1;
    if (!bmx_embedded_arena_capacity()) return 2;
    (void)bmx_embedded_collect_objects();
    uint32_t objects = bmx_embedded_object_live_count();
    uint32_t arrays = bmx_embedded_array_live_count();
    uint32_t strings = bmx_embedded_string_live_count();
    BMXEmbeddedRootSlot shared_slots[] = {
        {&shared_object, BMX_EMBEDDED_ROOT_ATOMIC_OBJECT, NULL},
        {&shared_array, BMX_EMBEDDED_ROOT_ATOMIC_ARRAY, NULL},
        {&shared_string, BMX_EMBEDDED_ROOT_ATOMIC_STRING, NULL}
    };
    BMXEmbeddedRootFrame shared_frame;
    bmx_embedded_root_frame_enter(&shared_frame, shared_slots, 3u);
    atomic_store_explicit(&stress_state, 4u, memory_order_release);
    atomic_store_explicit(&stress_failed, 0u, memory_order_release);
    if (!bmx_embedded_gc_worker_start(stress_worker, NULL)) return 3;
    int32_t failed = 0;
    for (uint32_t round = 1u; round <= STRESS_ROUNDS; ++round) {
        if (!wait_state(0u)) { failed = 4; break; }
        atomic_store_explicit(&stress_state, 5u, memory_order_release);
        StressNode *own_node = NULL;
        BMXEmbeddedArray *own_array = NULL;
        BMXEmbeddedString *own_text = NULL;
        BMXEmbeddedRootSlot own_slots[] = {
            {&own_node, BMX_EMBEDDED_ROOT_OBJECT, NULL},
            {&own_array, BMX_EMBEDDED_ROOT_ARRAY, NULL},
            {&own_text, BMX_EMBEDDED_ROOT_STRING, NULL}
        };
        BMXEmbeddedRootFrame own_frame;
        bmx_embedded_root_frame_enter(&own_frame, own_slots, 3u);
        own_node = bmx_embedded_object_allocate(&node_type);
        own_array = bmx_embedded_array_new_1d(1, sizeof(uint32_t),
            BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
        own_text = bmx_embedded_string_allocate(1);
        own_node->next = own_node;
        own_node->value = round;
        *(uint32_t *)bmx_embedded_array_element(own_array, 0,
            sizeof(uint32_t)) = round;
        ((uint16_t *)own_text->buf)[0] = (uint16_t)('Z' - round % 26u);
        if ((round & 127u) == 0u &&
                (!expect_oom(0u) || !expect_oom(1u) || !expect_oom(2u)))
            failed = 5;
        own_node = NULL;
        own_array = NULL;
        own_text = NULL;
        bmx_embedded_root_frame_leave(&own_frame);
        if (failed || !wait_state(1u)) { if (!failed) failed = 6; break; }
        (void)bmx_embedded_collect_objects();
        if (bmx_embedded_object_live_count() != objects + 1u ||
                bmx_embedded_array_live_count() != arrays + 1u ||
                bmx_embedded_string_live_count() != strings + 1u ||
                bmx_embedded_invalid_reference_count() ||
                !bmx_embedded_heap_integrity_valid()) { failed = 7; break; }
        StressNode *node = bmx_embedded_atomic_reference_load(&shared_object);
        BMXEmbeddedArray *array = bmx_embedded_atomic_reference_load(&shared_array);
        BMXEmbeddedString *text = bmx_embedded_atomic_reference_load(&shared_string);
        if (!node || node->next != node || node->value != round ||
                !array || *(uint32_t *)bmx_embedded_array_element(array, 0,
                    sizeof(uint32_t)) != round ||
                !text || text->buf[0] != (uint16_t)('A' + round % 26u)) {
            failed = 8;
            break;
        }
        node->value = round + 100000u;
        *(uint32_t *)bmx_embedded_array_element(array, 0,
            sizeof(uint32_t)) = round + 200000u;
        ((uint16_t *)text->buf)[0] = (uint16_t)('a' + round % 26u);
        atomic_store_explicit(&stress_state, 2u, memory_order_release);
        if (!wait_state(3u)) { failed = 9; break; }
        (void)bmx_embedded_collect_objects();
        if (bmx_embedded_object_live_count() != objects ||
                bmx_embedded_array_live_count() != arrays ||
                bmx_embedded_string_live_count() != strings ||
                bmx_embedded_invalid_reference_count() ||
                !bmx_embedded_heap_integrity_valid()) { failed = 10; break; }
        atomic_store_explicit(&stress_state, 4u, memory_order_release);
        if (round % 1000u == 0u)
            printf("GC_STAGE2_STRESS,progress=%lu/%u\n",
                (unsigned long)round, STRESS_ROUNDS);
    }
    if (!failed && atomic_load_explicit(&stress_failed,
            memory_order_acquire)) failed = 11;
    int joined = 0;
    if (!failed) {
        for (unsigned attempt = 0; attempt < 100u && !joined; ++attempt)
            joined = bmx_embedded_gc_worker_join(100000u);
        if (joined != 1) failed = 12;
    }
    bmx_embedded_root_frame_leave(&shared_frame);
    return failed;
}
