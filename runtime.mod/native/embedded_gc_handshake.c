#include "blitzmax/embedded_gc_handshake.h"

static void bmx_gc_lock(BMXEmbeddedGCHandshake *handshake) {
    while (atomic_flag_test_and_set_explicit(&handshake->registry_lock, memory_order_acquire)) {}
}

static void bmx_gc_unlock(BMXEmbeddedGCHandshake *handshake) {
    atomic_flag_clear_explicit(&handshake->registry_lock, memory_order_release);
}

static void bmx_gc_wait(BMXEmbeddedGCWait wait, void *argument) {
    if (wait) wait(argument);
}

void bmx_embedded_gc_handshake_init(BMXEmbeddedGCHandshake *handshake) {
    *handshake = (BMXEmbeddedGCHandshake){ .registry_lock = ATOMIC_FLAG_INIT };
    atomic_init(&handshake->epoch, 0u);
    atomic_init(&handshake->request_epoch, 0u);
    atomic_init(&handshake->collector_slot_plus_one, 0u);
    for (unsigned slot = 0; slot < BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY; ++slot) {
        atomic_init(&handshake->state[slot], BMX_EMBEDDED_GC_TASK_EMPTY);
        atomic_init(&handshake->acknowledgement[slot], 0u);
    }
}

int bmx_embedded_gc_task_register_bound(BMXEmbeddedGCHandshake *handshake,
    unsigned *slot, BMXEmbeddedGCBind bind, void *argument) {
    if (!slot) return 0;
    bmx_gc_lock(handshake);
    if (atomic_load_explicit(&handshake->request_epoch, memory_order_relaxed)) {
        bmx_gc_unlock(handshake);
        return 0;
    }
    for (unsigned index = 0; index < BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY; ++index) {
        if (atomic_load_explicit(&handshake->state[index], memory_order_relaxed) != BMX_EMBEDDED_GC_TASK_EMPTY)
            continue;
        /* Bind before publishing RUNNING while a stop request is excluded by
           the registry lock. A failed bind leaves the slot unregistered. */
        if (bind && !bind(index, argument)) {
            bmx_gc_unlock(handshake);
            return 0;
        }
        atomic_store_explicit(&handshake->acknowledgement[index], 0u, memory_order_relaxed);
        atomic_store_explicit(&handshake->state[index], BMX_EMBEDDED_GC_TASK_RUNNING, memory_order_release);
        *slot = index;
        bmx_gc_unlock(handshake);
        return 1;
    }
    bmx_gc_unlock(handshake);
    return 0;
}

int bmx_embedded_gc_task_register(BMXEmbeddedGCHandshake *handshake, unsigned *slot) {
    return bmx_embedded_gc_task_register_bound(handshake, slot, NULL, NULL);
}

int bmx_embedded_gc_task_unregister(BMXEmbeddedGCHandshake *handshake, unsigned slot) {
    if (slot >= BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY) return 0;
    bmx_gc_lock(handshake);
    int allowed = !atomic_load_explicit(&handshake->request_epoch, memory_order_relaxed) &&
        atomic_load_explicit(&handshake->state[slot], memory_order_relaxed) == BMX_EMBEDDED_GC_TASK_RUNNING;
    if (allowed) atomic_store_explicit(&handshake->state[slot], BMX_EMBEDDED_GC_TASK_EMPTY, memory_order_release);
    bmx_gc_unlock(handshake);
    return allowed;
}

void bmx_embedded_gc_task_poll(BMXEmbeddedGCHandshake *handshake, unsigned slot,
    BMXEmbeddedGCWait wait, void *argument) {
    if (slot >= BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY) return;
    unsigned epoch = atomic_load_explicit(&handshake->request_epoch, memory_order_acquire);
    if (!epoch) return;
    if (atomic_load_explicit(&handshake->collector_slot_plus_one, memory_order_acquire) == slot + 1u) return;
    if (atomic_load_explicit(&handshake->state[slot], memory_order_acquire) != BMX_EMBEDDED_GC_TASK_RUNNING) return;
    atomic_store_explicit(&handshake->state[slot], BMX_EMBEDDED_GC_TASK_PARKED, memory_order_release);
    atomic_store_explicit(&handshake->acknowledgement[slot], epoch, memory_order_release);
    while (atomic_load_explicit(&handshake->request_epoch, memory_order_acquire) == epoch)
        bmx_gc_wait(wait, argument);
    atomic_store_explicit(&handshake->state[slot], BMX_EMBEDDED_GC_TASK_RUNNING, memory_order_release);
}

int bmx_embedded_gc_task_enter_native_safe(BMXEmbeddedGCHandshake *handshake, unsigned slot) {
    if (slot >= BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY) return 0;
    /* The caller must publish every live managed handle in registered roots
       before this release store, and must not touch the heap while safe. */
    bmx_gc_lock(handshake);
    int allowed = atomic_load_explicit(&handshake->state[slot], memory_order_relaxed) == BMX_EMBEDDED_GC_TASK_RUNNING;
    if (allowed) atomic_store_explicit(&handshake->state[slot], BMX_EMBEDDED_GC_TASK_NATIVE_SAFE, memory_order_release);
    bmx_gc_unlock(handshake);
    return allowed;
}

void bmx_embedded_gc_task_leave_native_safe(BMXEmbeddedGCHandshake *handshake, unsigned slot,
    BMXEmbeddedGCWait wait, void *argument) {
    if (slot >= BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY) return;
    for (;;) {
        bmx_gc_lock(handshake);
        if (!atomic_load_explicit(&handshake->request_epoch, memory_order_relaxed)) {
            if (atomic_load_explicit(&handshake->state[slot], memory_order_relaxed) == BMX_EMBEDDED_GC_TASK_NATIVE_SAFE)
                atomic_store_explicit(&handshake->state[slot], BMX_EMBEDDED_GC_TASK_RUNNING, memory_order_release);
            bmx_gc_unlock(handshake);
            return;
        }
        bmx_gc_unlock(handshake);
        bmx_gc_wait(wait, argument);
    }
}

static int bmx_gc_all_stopped(BMXEmbeddedGCHandshake *handshake, unsigned collector_slot, unsigned epoch) {
    for (unsigned slot = 0; slot < BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY; ++slot) {
        if (slot == collector_slot) continue;
        unsigned state = atomic_load_explicit(&handshake->state[slot], memory_order_acquire);
        if (state == BMX_EMBEDDED_GC_TASK_EMPTY || state == BMX_EMBEDDED_GC_TASK_NATIVE_SAFE) continue;
        if (state != BMX_EMBEDDED_GC_TASK_PARKED ||
            atomic_load_explicit(&handshake->acknowledgement[slot], memory_order_acquire) != epoch) return 0;
    }
    return 1;
}

int bmx_embedded_gc_stop_begin(BMXEmbeddedGCHandshake *handshake, unsigned collector_slot,
    unsigned wait_budget, BMXEmbeddedGCWait wait, void *argument) {
    if (collector_slot >= BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY) return 0;
    bmx_gc_lock(handshake);
    if (atomic_load_explicit(&handshake->request_epoch, memory_order_relaxed) ||
        atomic_load_explicit(&handshake->state[collector_slot], memory_order_relaxed) != BMX_EMBEDDED_GC_TASK_RUNNING) {
        bmx_gc_unlock(handshake);
        return 0;
    }
    unsigned epoch = atomic_load_explicit(&handshake->epoch, memory_order_relaxed) + 1u;
    if (!epoch) epoch = 1u;
    atomic_store_explicit(&handshake->epoch, epoch, memory_order_relaxed);
    atomic_store_explicit(&handshake->collector_slot_plus_one, collector_slot + 1u, memory_order_relaxed);
    atomic_store_explicit(&handshake->request_epoch, epoch, memory_order_release);
    bmx_gc_unlock(handshake);

    for (;;) {
        if (bmx_gc_all_stopped(handshake, collector_slot, epoch)) {
            /* Registration and NATIVE_SAFE exit use this same lock. Once the
               request is active, neither may enter managed execution. */
            bmx_gc_lock(handshake);
            int stopped = bmx_gc_all_stopped(handshake, collector_slot, epoch);
            bmx_gc_unlock(handshake);
            if (stopped) return 1;
        }
        if (!wait_budget--) break;
        bmx_gc_wait(wait, argument);
    }
    bmx_gc_lock(handshake);
    atomic_store_explicit(&handshake->request_epoch, 0u, memory_order_release);
    atomic_store_explicit(&handshake->collector_slot_plus_one, 0u, memory_order_relaxed);
    bmx_gc_unlock(handshake);
    return 0;
}

void bmx_embedded_gc_stop_end(BMXEmbeddedGCHandshake *handshake, unsigned collector_slot) {
    if (collector_slot >= BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY) return;
    bmx_gc_lock(handshake);
    if (atomic_load_explicit(&handshake->collector_slot_plus_one, memory_order_relaxed) == collector_slot + 1u) {
        atomic_store_explicit(&handshake->request_epoch, 0u, memory_order_release);
        atomic_store_explicit(&handshake->collector_slot_plus_one, 0u, memory_order_relaxed);
    }
    bmx_gc_unlock(handshake);
}
