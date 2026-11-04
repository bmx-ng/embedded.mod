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
    BMXEmbeddedRootSlot slot = {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1u);
    assert(bmx_embedded_gc_enter_native_safe());
    assert(!bmx_embedded_gc_enter_native_safe());
    atomic_store_explicit(&phase, 1u, memory_order_release);
    while (atomic_load_explicit(&command, memory_order_acquire) == 0u) sched_yield();
    atomic_store_explicit(&leave_started, 1u, memory_order_release);
    assert(bmx_embedded_gc_leave_native_safe());
    atomic_store_explicit(&leave_finished, 1u, memory_order_release);
    assert(node->value == 0x1234u);
    atomic_store_explicit(&phase, 2u, memory_order_release);
    while (atomic_load_explicit(&command, memory_order_acquire) == 1u) {
        bmx_embedded_gc_poll();
        sched_yield();
    }
    node = NULL;
    bmx_embedded_root_frame_leave(&frame);
    atomic_store_explicit(&phase, 3u, memory_order_release);
    assert(bmx_embedded_gc_multicore_unregister());
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
    atomic_store_explicit(&handoff, (uintptr_t)node, memory_order_release);
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, worker, NULL));
    await_phase(1u);
    node = NULL;
    assert(bmx_embedded_collect_objects() == 0u);
    assert(bmx_embedded_object_live_count() == 1u);
    assert(bmx_embedded_heap_integrity_valid());

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
    assert(bmx_embedded_heap_integrity_valid());
    assert(!pthread_join(thread, NULL));
    assert(bmx_embedded_gc_multicore_unregister());
    puts("PASS: native-safe worker root and collection re-entry");
    return 0;
}
