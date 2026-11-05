/* Native core-to-core protocol test; it does not run managed code on core 1. */
#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_gc_handshake.h"
#include "pico/multicore.h"
#include "pico/stdlib.h"

static BMXEmbeddedGCHandshake bmx_device_handshake = { .registry_lock = ATOMIC_FLAG_INIT };
static atomic_uint bmx_device_mode;
static atomic_uint bmx_device_ready;
static atomic_uint bmx_device_blocked;
static atomic_uint bmx_device_done;

static void bmx_device_wait(void *unused) {
    (void)unused;
    tight_loop_contents();
}

static void bmx_device_worker(void) {
    unsigned slot;
    if (!bmx_embedded_gc_task_register(&bmx_device_handshake, &slot) || slot != 1u) {
        atomic_store_explicit(&bmx_device_ready, 2u, memory_order_release);
        return;
    }
    atomic_store_explicit(&bmx_device_ready, 1u, memory_order_release);
    for (;;) {
        unsigned mode = atomic_load_explicit(&bmx_device_mode, memory_order_acquire);
        if (mode == 2u) break;
        if (mode == 1u) {
            atomic_store_explicit(&bmx_device_blocked, 1u, memory_order_release);
            while (atomic_load_explicit(&bmx_device_mode, memory_order_acquire) == 1u)
                tight_loop_contents();
            atomic_store_explicit(&bmx_device_blocked, 0u, memory_order_release);
        } else {
            bmx_embedded_gc_task_poll(&bmx_device_handshake, slot, bmx_device_wait, NULL);
        }
    }
    atomic_store_explicit(&bmx_device_done,
        bmx_embedded_gc_task_unregister(&bmx_device_handshake, slot) ? 1u : 2u,
        memory_order_release);
}

static int bmx_device_wait_for(atomic_uint *value, unsigned expected) {
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        if (atomic_load_explicit(value, memory_order_acquire) == expected) return 1;
        tight_loop_contents();
    }
    return 0;
}

int32_t bmx_embedded_gc_handshake_device_test(void) {
    bmx_embedded_gc_handshake_init(&bmx_device_handshake);
    unsigned owner;
    if (!bmx_embedded_gc_task_register(&bmx_device_handshake, &owner) || owner != 0u) return 1;
    multicore_launch_core1(bmx_device_worker);
    if (!bmx_device_wait_for(&bmx_device_ready, 1u)) return 2;
    if (!bmx_embedded_gc_stop_begin(&bmx_device_handshake, owner,
            10000000u, bmx_device_wait, NULL)) return 3;
    bmx_embedded_gc_stop_end(&bmx_device_handshake, owner);

    atomic_store_explicit(&bmx_device_mode, 1u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_blocked, 1u)) return 4;
    if (bmx_embedded_gc_stop_begin(&bmx_device_handshake, owner,
            10000u, bmx_device_wait, NULL)) return 5;
    atomic_store_explicit(&bmx_device_mode, 0u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_blocked, 0u)) return 6;
    if (!bmx_embedded_gc_stop_begin(&bmx_device_handshake, owner,
            10000000u, bmx_device_wait, NULL)) return 7;
    bmx_embedded_gc_stop_end(&bmx_device_handshake, owner);

    atomic_store_explicit(&bmx_device_mode, 2u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_done, 1u)) return 8;
    if (!bmx_embedded_gc_task_unregister(&bmx_device_handshake, owner)) return 9;
    return 0;
}
