#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The Stage 2 worker lifecycle test requires opt-in multicore GC"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/stdlib.h"
static void lifecycle_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void lifecycle_yield(void) { taskYIELD(); }
#else
#error "The Stage 2 worker lifecycle test supports Pico and ESP32"
#endif

typedef struct LifecycleNode {
    BMXEmbeddedObject object;
    uint32_t value;
} LifecycleNode;
static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "LifecycleNode", .instance_size = sizeof(LifecycleNode)
};
static const BMXEmbeddedTypeDescriptor oversized_type = {
    .name = "OversizedNode", .instance_size = 70u * 1024u
};
typedef struct LifecycleJob {
    atomic_uint stage;
    atomic_uint release;
    uint32_t value;
    uint32_t throw_exception;
} LifecycleJob;

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

static void lifecycle_worker(void *argument) {
    LifecycleJob *job = argument;
    LifecycleNode *node = NULL;
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
        atomic_store_explicit(&job->stage, 9u, memory_order_release);
        bmx_embedded_root_frame_leave(&frame);
        return;
    }
    node->value = job->value;
    *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) = job->value;
    ((uint16_t *)text->buf)[0] = (uint16_t)('A' + job->value);
    if (!expect_oom(0u) || !expect_oom(1u) || !expect_oom(2u)) {
        atomic_store_explicit(&job->stage, 11u, memory_order_release);
        bmx_embedded_root_frame_leave(&frame);
        return;
    }
    atomic_store_explicit(&job->stage, 1u, memory_order_release);
    while (!atomic_load_explicit(&job->release, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        lifecycle_yield();
    }
    if (node->value != job->value ||
        *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) != job->value ||
        text->buf[0] != (uint16_t)('A' + job->value)) {
        atomic_store_explicit(&job->stage, 10u, memory_order_release);
        bmx_embedded_root_frame_leave(&frame);
        return;
    }
    if (job->throw_exception)
        bmx_embedded_exception_throw(bmx_embedded_exception_string(&bmx_embedded_empty_string));
    node = NULL;
    array = NULL;
    text = NULL;
    bmx_embedded_root_frame_leave(&frame);
}

static int wait_stage(LifecycleJob *job) {
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        unsigned stage = atomic_load_explicit(&job->stage, memory_order_acquire);
        if (stage == 1u) return 1;
        if (stage > 1u) return 0;
        lifecycle_yield();
    }
    return 0;
}

int32_t bmx_embedded_gc_stage2_worker_lifecycle_device_test(uint32_t cycles) {
    if (!cycles || cycles > 1000000u) return 11;
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 1;
    if (!bmx_embedded_arena_capacity()) return 2;
    (void)bmx_embedded_collect_objects();
    uint32_t objects = bmx_embedded_object_live_count();
    uint32_t arrays = bmx_embedded_array_live_count();
    uint32_t strings = bmx_embedded_string_live_count();
    for (uint32_t repeat = 0; repeat < cycles; ++repeat) {
        LifecycleJob job = {.value = repeat + 1u, .throw_exception = repeat == 7u};
        atomic_init(&job.stage, 0u);
        atomic_init(&job.release, 0u);
        if (!bmx_embedded_gc_worker_start(lifecycle_worker, &job)) return 3;
        if (bmx_embedded_gc_worker_start(lifecycle_worker, &job)) return 4;
        if (!wait_stage(&job)) return 5;
        if (bmx_embedded_gc_worker_join(0u)) return 6;
        (void)bmx_embedded_collect_objects();
        if (bmx_embedded_object_live_count() != objects + 1u ||
            bmx_embedded_array_live_count() != arrays + 1u ||
            bmx_embedded_string_live_count() != strings + 1u ||
            !bmx_embedded_heap_integrity_valid()) return 7;
        atomic_store_explicit(&job.release, 1u, memory_order_release);
        int joined = 0;
        for (unsigned attempt = 0; attempt < 100u && !joined; ++attempt)
            joined = bmx_embedded_gc_worker_join(100000u);
        if (joined != (job.throw_exception ? -1 : 1)) return 8;
        if (bmx_embedded_gc_worker_join(0u)) return 9;
        (void)bmx_embedded_collect_objects();
        if (bmx_embedded_object_live_count() != objects ||
            bmx_embedded_array_live_count() != arrays ||
            bmx_embedded_string_live_count() != strings ||
            !bmx_embedded_heap_integrity_valid()) return 10;
        uint32_t progress_interval = cycles >= 100000u ? 100000u : 1000u;
        if (cycles >= 1000u && (repeat + 1u) % progress_interval == 0u)
            printf("GC_STAGE2_SOAK,progress=%lu/%lu\n",
                (unsigned long)(repeat + 1u), (unsigned long)cycles);
    }
    return 0;
}
