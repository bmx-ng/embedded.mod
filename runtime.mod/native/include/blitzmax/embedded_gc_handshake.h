#ifndef BLITZMAX_EMBEDDED_GC_HANDSHAKE_H
#define BLITZMAX_EMBEDDED_GC_HANDSHAKE_H

#include <stdatomic.h>
#include <stdint.h>

/* Internal Stage 1 protocol. No managed worker or collector uses this yet.
   A target adapter supplies a wait callback and binds each slot to one task.
   The two-slot limit deliberately matches the initial two-mutator design. */
#define BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY 2u

typedef enum BMXEmbeddedGCTaskState {
    BMX_EMBEDDED_GC_TASK_EMPTY = 0,
    BMX_EMBEDDED_GC_TASK_RUNNING = 1,
    BMX_EMBEDDED_GC_TASK_PARKED = 2,
    BMX_EMBEDDED_GC_TASK_NATIVE_SAFE = 3
} BMXEmbeddedGCTaskState;

typedef struct BMXEmbeddedGCHandshake {
    atomic_flag registry_lock;
    atomic_uint epoch;
    atomic_uint request_epoch;
    atomic_uint collector_slot_plus_one;
    atomic_uint state[BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY];
    atomic_uint acknowledgement[BMX_EMBEDDED_GC_HANDSHAKE_CAPACITY];
} BMXEmbeddedGCHandshake;

typedef void (*BMXEmbeddedGCWait)(void *argument);

void bmx_embedded_gc_handshake_init(BMXEmbeddedGCHandshake *handshake);
int bmx_embedded_gc_task_register(BMXEmbeddedGCHandshake *handshake, unsigned *slot);
int bmx_embedded_gc_task_unregister(BMXEmbeddedGCHandshake *handshake, unsigned slot);
void bmx_embedded_gc_task_poll(BMXEmbeddedGCHandshake *handshake, unsigned slot,
    BMXEmbeddedGCWait wait, void *argument);
int bmx_embedded_gc_task_enter_native_safe(BMXEmbeddedGCHandshake *handshake, unsigned slot);
void bmx_embedded_gc_task_leave_native_safe(BMXEmbeddedGCHandshake *handshake, unsigned slot,
    BMXEmbeddedGCWait wait, void *argument);
int bmx_embedded_gc_stop_begin(BMXEmbeddedGCHandshake *handshake, unsigned collector_slot,
    unsigned wait_budget, BMXEmbeddedGCWait wait, void *argument);
void bmx_embedded_gc_stop_end(BMXEmbeddedGCHandshake *handshake, unsigned collector_slot);

#endif
