/* Internal Stage 1 integration: one allocating owner and one root-only worker. */
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

#define BMX_EMBEDDED_MULTICORE 1
#define BMX_EMBEDDED_GC_WAIT_BUDGET 1000000u
#define BMX_EMBEDDED_ARENA_SIZE (64u * 1024u)
#include "embedded_runtime_test.c"

_Thread_local unsigned bmx_test_context_slot = UINT32_MAX;

typedef struct TestNode {
    BMXEmbeddedObject object;
    uint32_t value;
} TestNode;

static atomic_uint worker_progress;
static atomic_uint finalizer_calls;
static void finalize_throw(void *object);
static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "TestNode", .instance_size = sizeof(TestNode)
};
static const BMXEmbeddedTypeDescriptor finalizable_type = {
    .name = "FinalizableNode", .instance_size = sizeof(TestNode),
    .flags = BMX_EMBEDDED_TYPE_FLAG_HAS_FINALIZER, .finalizer = finalize_throw
};

static atomic_uintptr_t handoff;
static atomic_int command;
static atomic_int observed;

static void finalize_throw(void *object) {
    (void)object;
    atomic_fetch_add_explicit(&finalizer_calls, 1u, memory_order_relaxed);
    unsigned before = atomic_load_explicit(&worker_progress, memory_order_relaxed);
    for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
        if (atomic_load_explicit(&worker_progress, memory_order_relaxed) != before) break;
        sched_yield();
    }
    assert(atomic_load_explicit(&worker_progress, memory_order_relaxed) != before);
    bmx_embedded_exception_throw(bmx_embedded_exception_string(&bmx_embedded_empty_string));
}

static void wait_observed(int expected) {
    for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
        if (atomic_load_explicit(&observed, memory_order_acquire) == expected) return;
        sched_yield();
    }
    assert(!"worker did not reach expected state");
}

static void *worker(void *unused) {
    (void)unused;
    unsigned slot = bmx_embedded_gc_multicore_register();
    assert(slot == 1u);
    bmx_test_context_slot = slot;
    TestNode *root = (TestNode *)atomic_load_explicit(&handoff, memory_order_acquire);
    BMXEmbeddedRootSlot root_slot = {&root, BMX_EMBEDDED_ROOT_OBJECT, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &root_slot, 1);
    assert(bmx_embedded_collect_objects() == 0u);
    atomic_store_explicit(&observed, 1, memory_order_release);
    for (;;) {
        int action = atomic_load_explicit(&command, memory_order_acquire);
        if (action == 4) break;
        if (action == 1) {
            root = NULL;
            atomic_store_explicit(&observed, 2, memory_order_release);
            while (atomic_load_explicit(&command, memory_order_acquire) == 1) bmx_embedded_gc_poll();
        } else if (action == 2) {
            atomic_store_explicit(&observed, 3, memory_order_release);
            while (atomic_load_explicit(&command, memory_order_acquire) == 2) sched_yield();
        }
        atomic_fetch_add_explicit(&worker_progress, 1u, memory_order_relaxed);
        bmx_embedded_gc_poll();
        sched_yield();
    }
    bmx_embedded_root_frame_leave(&frame);
    assert(bmx_embedded_gc_multicore_unregister());
    bmx_test_context_slot = UINT32_MAX;
    return NULL;
}

int main(void) {
    bmx_embedded_gc_multicore_initialize();
    bmx_test_context_slot = bmx_embedded_gc_multicore_register();
    assert(bmx_test_context_slot == 0u);
    TestNode *node = (TestNode *)bmx_embedded_object_allocate(&node_type);
    assert(node);
    node->value = 123u;
    atomic_store_explicit(&handoff, (uintptr_t)node, memory_order_release);
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, worker, NULL));
    wait_observed(1);
    node = NULL;
    assert(bmx_embedded_reachability_audit() == 1u);
    assert(bmx_embedded_collect_objects() == 0);
    assert(bmx_embedded_object_live_count() == 1u);
    assert(bmx_embedded_heap_integrity_valid());

    atomic_store_explicit(&command, 1, memory_order_release);
    wait_observed(2);
    assert(bmx_embedded_collect_objects() == 1u);
    assert(bmx_embedded_object_live_count() == 0u);
    assert(bmx_embedded_heap_integrity_valid());
    atomic_store_explicit(&command, 2, memory_order_release);
    wait_observed(3);
    node = (TestNode *)bmx_embedded_object_allocate(&node_type);
    assert(node);
    node = NULL;
    uint32_t collections_before_timeout = bmx_embedded_collection_count();
    assert(bmx_embedded_reachability_audit() == 0u);
    assert(bmx_embedded_collection_count() == collections_before_timeout);
    assert(bmx_embedded_collect_objects() == 0u);
    assert(bmx_embedded_object_live_count() == 1u);
    assert(bmx_embedded_heap_integrity_valid());
    atomic_store_explicit(&command, 0, memory_order_release);
    assert(bmx_embedded_collect_objects() == 1u);
    assert(bmx_embedded_object_live_count() == 0u);
    assert(bmx_embedded_heap_integrity_valid());

    /* Finalizers run after workers unpark. An escaping exception must leave
       the collection state usable and must not invoke that finalizer twice. */
    node = (TestNode *)bmx_embedded_object_allocate(&finalizable_type);
    assert(node);
    node = NULL;
    BMXEmbeddedExceptionFrame exception_frame;
    bmx_embedded_exception_enter(&exception_frame);
    if (setjmp(exception_frame.buffer) == 0) {
        (void)bmx_embedded_collect_objects();
        assert(!"finalizer exception must escape collection");
    }
    BMXEmbeddedException caught = bmx_embedded_exception_catch();
    assert(caught.kind == BMX_EMBEDDED_EXCEPTION_STRING);
    assert(atomic_load_explicit(&finalizer_calls, memory_order_relaxed) == 1u);
    assert(bmx_embedded_heap_integrity_valid());
    assert(bmx_embedded_collect_objects() == 1u);
    assert(atomic_load_explicit(&finalizer_calls, memory_order_relaxed) == 1u);

    atomic_store_explicit(&command, 4, memory_order_release);
    assert(!pthread_join(thread, NULL));
    assert(bmx_embedded_gc_multicore_unregister());
    puts("PASS: runtime root survival, reclamation and timeout without sweep");
}
