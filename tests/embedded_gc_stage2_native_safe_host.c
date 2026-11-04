/* Stage 2: rooted worker native block, collection and safe re-entry. */
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

#define BMX_EMBEDDED_MULTICORE 1
#define BMX_EMBEDDED_GC_WAIT_BUDGET 0u
#define BMX_EMBEDDED_ARENA_SIZE (64u * 1024u)
#include "embedded_runtime_test.c"

_Thread_local unsigned bmx_test_context_slot = UINT32_MAX;
typedef struct NativeNode {
    BMXEmbeddedObject object;
    uint32_t value;
} NativeNode;
static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "NativeNode", .instance_size = sizeof(NativeNode)
};
static atomic_uintptr_t handoff;
static atomic_uintptr_t array_handoff;
static atomic_uintptr_t raw_handoff;
static atomic_uint phase;
static atomic_uint command;
static atomic_uint leave_started;
static atomic_uint leave_finished;

static void await_phase(unsigned expected) {
    for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
        if (atomic_load_explicit(&phase, memory_order_acquire) == expected) return;
        sched_yield();
    }
    assert(!"worker did not reach native-safe phase");
}

static void *worker(void *unused) {
    (void)unused;
    assert(bmx_embedded_gc_multicore_register() == 1u);
    bmx_test_context_slot = 1u;
    NativeNode *node = (NativeNode *)atomic_load_explicit(&handoff, memory_order_acquire);
    BMXEmbeddedArray *array = (BMXEmbeddedArray *)atomic_load_explicit(
        &array_handoff, memory_order_acquire);
    uint8_t *raw = (uint8_t *)atomic_load_explicit(&raw_handoff, memory_order_acquire);
    BMXEmbeddedRootSlot slots[] = {
        {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL},
        {&array, BMX_EMBEDDED_ROOT_ARRAY, NULL}
    };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, 2u);
    uint8_t stack_buffer[8] = {0};
    assert(!bmx_embedded_gc_enter_native_safe_for_buffers(&node->value,
        sizeof(node->value), NULL, 0u));
    assert(!bmx_embedded_gc_enter_native_safe_for_buffers(
        bmx_embedded_array_data(array), sizeof(uint32_t), NULL, 0u));
    assert(!bmx_embedded_gc_enter_native_safe_for_buffers(raw, 4u,
        bmx_embedded_array_data(array), sizeof(uint32_t)));
    assert(!bmx_embedded_gc_enter_native_safe_for_buffers(stack_buffer,
        sizeof(stack_buffer), &node->value, sizeof(node->value)));
    assert(!bmx_embedded_gc_enter_native_safe_for_buffers(
        bmx_embedded_arena_base() + BMX_EMBEDDED_ARENA_SIZE - 1u, 2u, NULL, 0u));
    assert(!bmx_embedded_gc_enter_native_safe_for_buffers(
        (void *)(uintptr_t)(UINTPTR_MAX - 1u), 4u, NULL, 0u));
    assert(bmx_embedded_gc_enter_native_safe_for_buffers(raw + 2u, 4u,
        stack_buffer, sizeof(stack_buffer)));
    assert(bmx_embedded_gc_leave_native_safe());
    assert(!bmx_embedded_gc_enter_native_safe_for_buffers(raw + 7u, 2u,
        NULL, 0u));
    assert(!bmx_embedded_gc_enter_native_safe_for_three_buffers(raw, 4u,
        stack_buffer, sizeof(stack_buffer), bmx_embedded_array_data(array),
        sizeof(uint32_t)));
    assert(bmx_embedded_gc_enter_native_safe_for_three_buffers(raw, 4u,
        stack_buffer, sizeof(stack_buffer), NULL, 0u));
    assert(bmx_embedded_gc_leave_native_safe());
    assert(bmx_embedded_gc_enter_native_safe_for_buffers(raw + 2u, 4u,
        stack_buffer, sizeof(stack_buffer)));
    raw[2] = 0xa5u;
    assert(!bmx_embedded_gc_enter_native_safe());
    atomic_store_explicit(&phase, 1u, memory_order_release);
    while (atomic_load_explicit(&command, memory_order_acquire) == 0u) sched_yield();
    atomic_store_explicit(&leave_started, 1u, memory_order_release);
    assert(bmx_embedded_gc_leave_native_safe());
    atomic_store_explicit(&leave_finished, 1u, memory_order_release);
    assert(node->value == 0x1234u);
    assert(*(uint32_t *)bmx_embedded_array_data(array) == 0x5678u);
    atomic_store_explicit(&phase, 2u, memory_order_release);
    while (atomic_load_explicit(&command, memory_order_acquire) == 1u) {
        bmx_embedded_gc_poll();
        sched_yield();
    }
    node = NULL;
    array = NULL;
    bmx_embedded_root_frame_leave(&frame);
    assert(bmx_embedded_gc_multicore_unregister());
    atomic_store_explicit(&phase, 3u, memory_order_release);
    bmx_test_context_slot = UINT32_MAX;
    return NULL;
}

int main(void) {
    bmx_embedded_gc_multicore_initialize();
    assert(bmx_embedded_gc_multicore_register() == 0u);
    bmx_test_context_slot = 0u;
    assert(!bmx_embedded_gc_enter_native_safe());
    NativeNode *node = bmx_embedded_object_allocate(&node_type);
    assert(node);
    node->value = 0x1234u;
    BMXEmbeddedArray *array = bmx_embedded_array_new_1d(1, sizeof(uint32_t),
        BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
    assert(array);
    *(uint32_t *)bmx_embedded_array_data(array) = 0x5678u;
    uint8_t *raw = bbMemAlloc(8u);
    assert(raw);
    raw[0] = 0x5au;
    atomic_store_explicit(&handoff, (uintptr_t)node, memory_order_release);
    atomic_store_explicit(&array_handoff, (uintptr_t)array, memory_order_release);
    atomic_store_explicit(&raw_handoff, (uintptr_t)raw, memory_order_release);
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, worker, NULL));
    await_phase(1u);
    node = NULL;
    array = NULL;
    assert(bmx_embedded_collect_objects() == 0u);
    assert(bmx_embedded_object_live_count() == 1u);
    assert(bmx_embedded_array_live_count() == 1u);
    assert(bmx_embedded_heap_integrity_valid());
    assert(raw[0] == 0x5au);
    assert(raw[2] == 0xa5u);

    assert(bmx_embedded_gc_stop_begin(&bmx_embedded_handshake, 0u, 0u, NULL, NULL));
    atomic_store_explicit(&command, 1u, memory_order_release);
    for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
        if (atomic_load_explicit(&leave_started, memory_order_acquire)) break;
        sched_yield();
    }
    assert(atomic_load_explicit(&leave_started, memory_order_acquire));
    for (unsigned spin = 0; spin < 1000u; ++spin) sched_yield();
    assert(!atomic_load_explicit(&leave_finished, memory_order_acquire));
    bmx_embedded_gc_stop_end(&bmx_embedded_handshake, 0u);
    await_phase(2u);
    assert(atomic_load_explicit(&leave_finished, memory_order_acquire));
    atomic_store_explicit(&command, 2u, memory_order_release);
    await_phase(3u);
    assert(bmx_embedded_collect_objects() == 1u);
    assert(bmx_embedded_object_live_count() == 0u);
    assert(bmx_embedded_array_live_count() == 0u);
    assert(bmx_embedded_heap_integrity_valid());
    assert(!pthread_join(thread, NULL));
    bbMemFree(raw);
    assert(bmx_embedded_gc_multicore_unregister());
    puts("PASS: native-safe worker root and collection re-entry");
    return 0;
}
