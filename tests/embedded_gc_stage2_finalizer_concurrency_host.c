/* Stage 2: worker allocations during finalizers and an escaping exception. */
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

#define BMX_EMBEDDED_MULTICORE 1
#define BMX_EMBEDDED_GC_WAIT_BUDGET 100000u
#define BMX_EMBEDDED_ARENA_SIZE (64u * 1024u)
#include "embedded_runtime_test.c"

_Thread_local unsigned bmx_test_context_slot = UINT32_MAX;

typedef struct FinalizerNode {
    BMXEmbeddedObject object;
    uint32_t value;
} FinalizerNode;

static atomic_uint run_worker;
static atomic_uint worker_progress;
static atomic_uint worker_done;
static atomic_uint worker_exit;
static atomic_uint finalizer_calls;
static atomic_uint throw_once = 1u;

static void finalizer(void *object) {
    FinalizerNode *node = object;
    assert(node->value == 0x1234u);
    unsigned count = atomic_fetch_add_explicit(&finalizer_calls, 1u, memory_order_acq_rel) + 1u;
    if (count == 1u) atomic_store_explicit(&run_worker, 1u, memory_order_release);
    if (count == 2u && atomic_exchange_explicit(&throw_once, 0u, memory_order_acq_rel)) {
        for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
            if (atomic_load_explicit(&worker_progress, memory_order_acquire)) break;
            sched_yield();
        }
        assert(atomic_load_explicit(&worker_progress, memory_order_acquire));
        bmx_embedded_exception_throw(bmx_embedded_exception_string(&bmx_embedded_empty_string));
    }
}

static const BMXEmbeddedTypeDescriptor finalizable_type = {
    .name = "FinalizerNode", .instance_size = sizeof(FinalizerNode),
    .flags = BMX_EMBEDDED_TYPE_FLAG_HAS_FINALIZER, .finalizer = finalizer
};
static const BMXEmbeddedTypeDescriptor ordinary_type = {
    .name = "OrdinaryNode", .instance_size = sizeof(FinalizerNode)
};

static void *worker(void *unused) {
    (void)unused;
    assert(bmx_embedded_gc_multicore_register() == 1u);
    bmx_test_context_slot = 1u;
    FinalizerNode *node = NULL;
    BMXEmbeddedRootSlot slot = {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1u);
    while (!atomic_load_explicit(&run_worker, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        sched_yield();
    }
    for (unsigned index = 0; index < 300u; ++index) {
        node = bmx_embedded_object_allocate(&ordinary_type);
        assert(node);
        node->value = index;
        atomic_fetch_add_explicit(&worker_progress, 1u, memory_order_release);
        sched_yield();
    }
    node = NULL;
    atomic_store_explicit(&worker_done, 1u, memory_order_release);
    while (!atomic_load_explicit(&worker_exit, memory_order_acquire)) {
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
    assert(bmx_embedded_gc_multicore_register() == 0u);
    bmx_test_context_slot = 0u;
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, worker, NULL));
    for (unsigned index = 0; index < 24u; ++index) {
        FinalizerNode *node = bmx_embedded_object_allocate(&finalizable_type);
        assert(node);
        node->value = 0x1234u;
    }

    BMXEmbeddedExceptionFrame exception_frame;
    bmx_embedded_exception_enter(&exception_frame);
    if (setjmp(exception_frame.buffer) == 0) {
        (void)bmx_embedded_collect_objects();
        assert(!"second finalizer must throw");
    }
    BMXEmbeddedException caught = bmx_embedded_exception_catch();
    assert(caught.kind == BMX_EMBEDDED_EXCEPTION_STRING);
    assert(bmx_embedded_finalizer_invocation_count() == 2u);
    assert(bmx_embedded_finalizer_pending_count() == 0u);
    assert(bmx_embedded_heap_integrity_valid());

    while (!atomic_load_explicit(&worker_done, memory_order_acquire)) sched_yield();
    (void)bmx_embedded_collect_objects();
    assert(bmx_embedded_finalizer_invocation_count() == 24u);
    assert(bmx_embedded_finalizer_pending_count() == 0u);
    assert(bmx_embedded_heap_integrity_valid());
    (void)bmx_embedded_collect_objects();
    assert(bmx_embedded_object_live_count() == 0u);
    assert(bmx_embedded_heap_integrity_valid());

    atomic_store_explicit(&worker_exit, 1u, memory_order_release);
    assert(!pthread_join(thread, NULL));
    assert(bmx_embedded_gc_multicore_unregister());
    puts("PASS: worker allocation during finalizers and exception unwinding");
    return 0;
}
