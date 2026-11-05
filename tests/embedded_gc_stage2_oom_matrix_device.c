#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_runtime.h"

#if !defined(BMX_EMBEDDED_MULTICORE) || !BMX_EMBEDDED_MULTICORE
#error "The Stage 2 OOM matrix requires opt-in multicore GC"
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/stdlib.h"
static void oom_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void oom_yield(void) { taskYIELD(); }
#else
#error "The Stage 2 OOM matrix supports Pico and ESP32"
#endif

enum { ROOT_COUNT = 60u };
static const BMXEmbeddedTypeDescriptor small_type = {
    .name = "SmallBlock", .instance_size = 1024u
};
static const BMXEmbeddedTypeDescriptor large_type = {
    .name = "LargeBlock", .instance_size = 4096u
};
static atomic_uint worker_ready;
static atomic_uint worker_release;

static void waiting_worker(void *unused) {
    (void)unused;
    atomic_store_explicit(&worker_ready, 1u, memory_order_release);
    while (!atomic_load_explicit(&worker_release, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        oom_yield();
    }
}

static int expect_oom(unsigned kind) {
    BMXEmbeddedExceptionFrame frame;
    bmx_embedded_exception_enter(&frame);
    if (setjmp(frame.buffer) == 0) {
        if (kind == 0u) (void)bmx_embedded_object_allocate(&large_type);
        else if (kind == 1u) (void)bmx_embedded_array_new_1d(1024,
            sizeof(uint32_t), BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
        else (void)bmx_embedded_string_allocate(2048);
        bmx_embedded_exception_leave();
        return 0;
    }
    return bmx_embedded_exception_catch().kind == BMX_EMBEDDED_EXCEPTION_STRING;
}

int32_t bmx_embedded_gc_stage2_oom_matrix_device_test(void) {
    bmx_embedded_gc_multicore_initialize();
    if (bmx_embedded_gc_multicore_register() != 0u) return 1;
    if (!bmx_embedded_arena_capacity()) return 2;
    (void)bmx_embedded_collect_objects();
    uint32_t baseline_objects = bmx_embedded_object_live_count();
    uint32_t baseline_arrays = bmx_embedded_array_live_count();
    uint32_t baseline_strings = bmx_embedded_string_live_count();
    atomic_store_explicit(&worker_ready, 0u, memory_order_relaxed);
    atomic_store_explicit(&worker_release, 0u, memory_order_relaxed);
    if (!bmx_embedded_gc_worker_start(waiting_worker, NULL)) return 3;
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        if (atomic_load_explicit(&worker_ready, memory_order_acquire)) break;
        if (attempt == 9999999u) return 4;
        oom_yield();
    }
    int32_t failed = 0;
    uint32_t arena_failures = bmx_embedded_arena_failure_count();
    if (bmx_embedded_arena_allocate(65537u) ||
            bmx_embedded_arena_failure_count() != arena_failures + 1u)
        failed = 5;
    BMXEmbeddedObject *blocks[ROOT_COUNT] = {0};
    BMXEmbeddedRootSlot slots[ROOT_COUNT];
    for (unsigned index = 0; index < ROOT_COUNT; ++index)
        slots[index] = (BMXEmbeddedRootSlot){&blocks[index],
            BMX_EMBEDDED_ROOT_OBJECT, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, ROOT_COUNT);
    uint32_t count = 0u;
    while (!failed && count < ROOT_COUNT &&
            bmx_embedded_arena_remaining() >= 1120u) {
        blocks[count] = bmx_embedded_object_allocate(&small_type);
        if (!blocks[count]) { failed = 6; break; }
        ++count;
    }
    if (!failed && (count < 20u || bmx_embedded_arena_remaining() >= 4096u))
        failed = 7;
    for (uint32_t index = 0u; index < count; index += 2u) blocks[index] = NULL;
    if (!failed) {
        (void)bmx_embedded_collect_objects();
        if (bmx_embedded_heap_reusable_bytes() <= 8192u ||
                bmx_embedded_heap_largest_free_block() >= 4096u ||
                !bmx_embedded_heap_integrity_valid()) failed = 8;
    }
    if (!failed && (!expect_oom(0u) || !expect_oom(1u) ||
            !expect_oom(2u))) failed = 9;
    for (uint32_t index = 0u; index < count; ++index) blocks[index] = NULL;
    bmx_embedded_root_frame_leave(&frame);
    if (!failed) {
        (void)bmx_embedded_collect_objects();
        BMXEmbeddedObject *large = NULL;
        BMXEmbeddedArray *array = NULL;
        BMXEmbeddedString *text = NULL;
        BMXEmbeddedRootSlot recovery_slots[] = {
            {&large, BMX_EMBEDDED_ROOT_OBJECT, NULL},
            {&array, BMX_EMBEDDED_ROOT_ARRAY, NULL},
            {&text, BMX_EMBEDDED_ROOT_STRING, NULL}
        };
        BMXEmbeddedRootFrame recovery_frame;
        bmx_embedded_root_frame_enter(&recovery_frame, recovery_slots, 3u);
        large = bmx_embedded_object_allocate(&large_type);
        array = bmx_embedded_array_new_1d(1024, sizeof(uint32_t),
            BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
        text = bmx_embedded_string_allocate(2048);
        if (!large || !array || !text) failed = 10;
        large = NULL;
        array = NULL;
        text = NULL;
        bmx_embedded_root_frame_leave(&recovery_frame);
        (void)bmx_embedded_collect_objects();
        if (bmx_embedded_object_live_count() != baseline_objects ||
                bmx_embedded_array_live_count() != baseline_arrays ||
                bmx_embedded_string_live_count() != baseline_strings ||
                !bmx_embedded_heap_integrity_valid()) failed = 11;
    }
    atomic_store_explicit(&worker_release, 1u, memory_order_release);
    int joined = 0;
    for (unsigned attempt = 0; attempt < 100u && !joined; ++attempt)
        joined = bmx_embedded_gc_worker_join(100000u);
    if (!failed && joined != 1) failed = 12;
    return failed;
}
