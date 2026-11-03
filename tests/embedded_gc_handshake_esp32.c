/* Native task-to-task protocol test; the worker does not enter managed code. */
#include <stdatomic.h>
#include <stdint.h>

#include "blitzmax/embedded_gc_handshake.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static BMXEmbeddedGCHandshake bmx_device_handshake = { .registry_lock = ATOMIC_FLAG_INIT };
static atomic_uint bmx_device_mode;
static atomic_uint bmx_device_ready;
static atomic_uint bmx_device_blocked;
static atomic_uint bmx_device_done;

static void bmx_device_wait(void *unused) {
    (void)unused;
    taskYIELD();
}

static void bmx_device_worker(void *unused) {
    (void)unused;
    unsigned slot;
    if (!bmx_embedded_gc_task_register(&bmx_device_handshake, &slot) || slot != 1u) {
        atomic_store_explicit(&bmx_device_ready, 2u, memory_order_release);
        vTaskDelete(NULL);
    }
    atomic_store_explicit(&bmx_device_ready, 1u, memory_order_release);
    for (;;) {
        unsigned mode = atomic_load_explicit(&bmx_device_mode, memory_order_acquire);
        if (mode == 2u) break;
        if (mode == 1u) {
            atomic_store_explicit(&bmx_device_blocked, 1u, memory_order_release);
            while (atomic_load_explicit(&bmx_device_mode, memory_order_acquire) == 1u)
                taskYIELD();
            atomic_store_explicit(&bmx_device_blocked, 0u, memory_order_release);
        } else {
            bmx_embedded_gc_task_poll(&bmx_device_handshake, slot, bmx_device_wait, NULL);
            taskYIELD();
        }
    }
    atomic_store_explicit(&bmx_device_done,
        bmx_embedded_gc_task_unregister(&bmx_device_handshake, slot) ? 1u : 2u,
        memory_order_release);
    vTaskDelete(NULL);
}

static int bmx_device_wait_for(atomic_uint *value, unsigned expected) {
    for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
        if (atomic_load_explicit(value, memory_order_acquire) == expected) return 1;
        taskYIELD();
    }
    return 0;
}

int32_t bmx_embedded_gc_handshake_device_test(void) {
    bmx_embedded_gc_handshake_init(&bmx_device_handshake);
    unsigned owner;
    if (!bmx_embedded_gc_task_register(&bmx_device_handshake, &owner) || owner != 0u) return 1;
    TaskHandle_t worker = NULL;
    if (xTaskCreatePinnedToCore(bmx_device_worker, "gc-handshake", 2048, NULL,
            tskIDLE_PRIORITY + 1, &worker, 1) != pdPASS) return 2;
    if (!bmx_device_wait_for(&bmx_device_ready, 1u)) return 3;
    if (!bmx_embedded_gc_stop_begin(&bmx_device_handshake, owner,
            1000000u, bmx_device_wait, NULL)) return 4;
    bmx_embedded_gc_stop_end(&bmx_device_handshake, owner);

    atomic_store_explicit(&bmx_device_mode, 1u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_blocked, 1u)) return 5;
    if (bmx_embedded_gc_stop_begin(&bmx_device_handshake, owner,
            10000u, bmx_device_wait, NULL)) return 6;
    atomic_store_explicit(&bmx_device_mode, 0u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_blocked, 0u)) return 7;
    if (!bmx_embedded_gc_stop_begin(&bmx_device_handshake, owner,
            1000000u, bmx_device_wait, NULL)) return 8;
    bmx_embedded_gc_stop_end(&bmx_device_handshake, owner);

    atomic_store_explicit(&bmx_device_mode, 2u, memory_order_release);
    if (!bmx_device_wait_for(&bmx_device_done, 1u)) return 9;
    if (!bmx_embedded_gc_task_unregister(&bmx_device_handshake, owner)) return 10;
    return 0;
}
