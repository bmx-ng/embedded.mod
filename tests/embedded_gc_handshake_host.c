#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdio.h>

#include "blitzmax/embedded_gc_handshake.h"

static BMXEmbeddedGCHandshake handshake;
static atomic_int command;
static atomic_int observed;
static atomic_uint progress;

static void yield_task(void *unused) {
    (void)unused;
    sched_yield();
}

static int reject_worker_bind(unsigned slot, void *unused) {
    (void)unused;
    assert(slot == 1u);
    return 0;
}

static void await_observed(int expected) {
    for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
        if (atomic_load_explicit(&observed, memory_order_acquire) == expected) return;
        sched_yield();
    }
    assert(!"worker did not reach expected state");
}

static void *worker(void *unused) {
    (void)unused;
    unsigned slot;
    assert(bmx_embedded_gc_task_register(&handshake, &slot));
    atomic_store_explicit(&observed, 10, memory_order_release);
    for (;;) {
        int action = atomic_load_explicit(&command, memory_order_acquire);
        if (action == 4) break;
        if (action == 1) {
            atomic_store_explicit(&observed, 1, memory_order_release);
            sched_yield();
            continue;
        }
        if (action == 2) {
            assert(bmx_embedded_gc_task_enter_native_safe(&handshake, slot));
            atomic_store_explicit(&observed, 2, memory_order_release);
            while (atomic_load_explicit(&command, memory_order_acquire) == 2) sched_yield();
            bmx_embedded_gc_task_leave_native_safe(&handshake, slot, yield_task, NULL);
            atomic_store_explicit(&observed, 3, memory_order_release);
            continue;
        }
        atomic_fetch_add_explicit(&progress, 1u, memory_order_relaxed);
        bmx_embedded_gc_task_poll(&handshake, slot, yield_task, NULL);
        sched_yield();
    }
    assert(bmx_embedded_gc_task_unregister(&handshake, slot));
    return NULL;
}

int main(void) {
    bmx_embedded_gc_handshake_init(&handshake);
    unsigned owner;
    assert(bmx_embedded_gc_task_register(&handshake, &owner));
    unsigned rejected;
    assert(!bmx_embedded_gc_task_register_bound(&handshake, &rejected,
        reject_worker_bind, NULL));
    assert(atomic_load_explicit(&handshake.state[1], memory_order_acquire) ==
        BMX_EMBEDDED_GC_TASK_EMPTY);
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, worker, NULL));
    await_observed(10);

    for (unsigned repeat = 0; repeat < 100u; ++repeat) {
        assert(bmx_embedded_gc_stop_begin(&handshake, owner, 1000000u, yield_task, NULL));
        unsigned other;
        assert(!bmx_embedded_gc_task_register(&handshake, &other));
        assert(!bmx_embedded_gc_task_unregister(&handshake, owner));
        unsigned stationary = atomic_load_explicit(&progress, memory_order_relaxed);
        for (unsigned spin = 0; spin < 100u; ++spin) sched_yield();
        assert(atomic_load_explicit(&progress, memory_order_relaxed) == stationary);
        bmx_embedded_gc_stop_end(&handshake, owner);
    }

    atomic_store_explicit(&command, 1, memory_order_release);
    await_observed(1);
    assert(!bmx_embedded_gc_stop_begin(&handshake, owner, 1000u, yield_task, NULL));
    assert(!atomic_load_explicit(&handshake.request_epoch, memory_order_acquire));
    atomic_store_explicit(&command, 0, memory_order_release);
    assert(bmx_embedded_gc_stop_begin(&handshake, owner, 1000000u, yield_task, NULL));
    bmx_embedded_gc_stop_end(&handshake, owner);

    atomic_store_explicit(&command, 2, memory_order_release);
    await_observed(2);
    assert(bmx_embedded_gc_stop_begin(&handshake, owner, 0u, yield_task, NULL));
    atomic_store_explicit(&command, 3, memory_order_release);
    for (unsigned spin = 0; spin < 100u; ++spin) sched_yield();
    assert(atomic_load_explicit(&observed, memory_order_acquire) == 2);
    bmx_embedded_gc_stop_end(&handshake, owner);
    await_observed(3);

    atomic_store_explicit(&command, 4, memory_order_release);
    assert(!pthread_join(thread, NULL));
    assert(bmx_embedded_gc_task_unregister(&handshake, owner));
    puts("PASS: cooperative stop, timeout, native-safe and registry exclusion");
}
