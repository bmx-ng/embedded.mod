/* Stage 2: runtime-owned worker start, exception boundary, join and reuse. */
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

static int host_bind(unsigned slot);
static void host_unbind(unsigned slot);
static int host_worker_start(void (*entry)(void));
static int host_worker_join(void);

#define BMX_EMBEDDED_PLATFORM_GC_BIND(slot) host_bind(slot)
#define BMX_EMBEDDED_PLATFORM_GC_UNBIND(slot) host_unbind(slot)
#define BMX_EMBEDDED_PLATFORM_GC_WORKER_START(entry) host_worker_start(entry)
#define BMX_EMBEDDED_PLATFORM_GC_WORKER_JOIN() host_worker_join()
#define BMX_EMBEDDED_MULTICORE 1
#define BMX_EMBEDDED_GC_WAIT_BUDGET 100000u
#define BMX_EMBEDDED_ARENA_SIZE (64u * 1024u)
#include "embedded_runtime_test.c"

_Thread_local unsigned bmx_test_context_slot = UINT32_MAX;
static pthread_t host_thread;
static void (*host_entry)(void);
static int fail_next_start;

static int host_bind(unsigned slot) {
    if (bmx_test_context_slot != UINT32_MAX) return 0;
    bmx_test_context_slot = slot;
    return 1;
}

static void host_unbind(unsigned slot) {
    assert(bmx_test_context_slot == slot);
    bmx_test_context_slot = UINT32_MAX;
}

static void *host_trampoline(void *unused) {
    (void)unused;
    host_entry();
    return NULL;
}

static int host_worker_start(void (*entry)(void)) {
    if (fail_next_start) {
        fail_next_start = 0;
        return 0;
    }
    host_entry = entry;
    return pthread_create(&host_thread, NULL, host_trampoline, NULL) == 0;
}

static int host_worker_join(void) {
    return pthread_join(host_thread, NULL) == 0;
}

typedef struct WorkerNode {
    BMXEmbeddedObject object;
    uint32_t value;
} WorkerNode;
static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "WorkerNode", .instance_size = sizeof(WorkerNode)
};

typedef struct WorkerJob {
    atomic_uint stage;
    atomic_uint release;
    unsigned value;
    int should_throw;
} WorkerJob;

static void run_job(void *argument) {
    WorkerJob *job = argument;
    WorkerNode *node = NULL;
    BMXEmbeddedRootSlot slot = {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1u);
    node = bmx_embedded_object_allocate(&node_type);
    assert(node);
    node->value = job->value;
    atomic_store_explicit(&job->stage, 1u, memory_order_release);
    while (!atomic_load_explicit(&job->release, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        sched_yield();
    }
    assert(node->value == job->value);
    if (job->should_throw)
        bmx_embedded_exception_throw(bmx_embedded_exception_string(&bmx_embedded_empty_string));
    node = NULL;
    bmx_embedded_root_frame_leave(&frame);
}

static void await_stage(WorkerJob *job) {
    for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
        if (atomic_load_explicit(&job->stage, memory_order_acquire)) return;
        sched_yield();
    }
    assert(!"worker did not start its managed job");
}

int main(void) {
    bmx_embedded_gc_multicore_initialize();
    assert(bmx_embedded_gc_multicore_register() == 0u);
    fail_next_start = 1;
    assert(!bmx_embedded_gc_worker_start(run_job, NULL));
    assert(!bmx_embedded_gc_worker_join(0u));

    for (unsigned repeat = 0; repeat < 32u; ++repeat) {
        WorkerJob job = {.value = repeat + 1u, .should_throw = repeat == 17u};
        atomic_init(&job.stage, 0u);
        atomic_init(&job.release, 0u);
        assert(bmx_embedded_gc_worker_start(run_job, &job));
        assert(!bmx_embedded_gc_worker_start(run_job, &job));
        await_stage(&job);
        assert(!bmx_embedded_gc_worker_join(0u));
        (void)bmx_embedded_collect_objects();
        assert(bmx_embedded_object_live_count() == 1u);
        atomic_store_explicit(&job.release, 1u, memory_order_release);
        int joined = 0;
        for (unsigned attempt = 0; attempt < 100u && !joined; ++attempt)
            joined = bmx_embedded_gc_worker_join(100000u);
        assert(joined == (job.should_throw ? -1 : 1));
        assert(!bmx_embedded_gc_worker_join(0u));
        assert(bmx_embedded_collect_objects() == 1u);
        assert(bmx_embedded_object_live_count() == 0u);
        assert(bmx_embedded_heap_integrity_valid());
    }
    assert(bmx_embedded_gc_multicore_unregister());
    puts("PASS: runtime-created worker lifecycle, exception and repeated join");
    return 0;
}
