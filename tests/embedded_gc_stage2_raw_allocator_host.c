/* Stage 2 allocator foundation: concurrent non-collecting raw allocations. */
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

#define BMX_EMBEDDED_MULTICORE 1
#define BMX_EMBEDDED_ARENA_SIZE (64u * 1024u)
#include "embedded_runtime_test.c"

_Thread_local unsigned bmx_test_context_slot = UINT32_MAX;

enum { ALLOCATION_COUNT = 128, ALLOCATION_SIZE = 32 };
static uint8_t *blocks[2][ALLOCATION_COUNT];
static void *reusable[ALLOCATION_COUNT / 8];
static atomic_int worker_ready;
static atomic_int start_allocating;
static atomic_int worker_done;
static atomic_int worker_exit;

static void allocate_blocks(unsigned slot) {
    for (unsigned index = 0; index < ALLOCATION_COUNT; ++index) {
        uint8_t *block = bmx_embedded_arena_allocate(ALLOCATION_SIZE);
        assert(block);
        for (unsigned byte = 0; byte < ALLOCATION_SIZE; ++byte)
            block[byte] = (uint8_t)(slot * ALLOCATION_COUNT + index + byte);
        blocks[slot][index] = block;
        if (slot == 0u && index % 8u == 0u) {
            bbMemFree(reusable[index / 8u]);
            assert(bmx_embedded_arena_used() <= bmx_embedded_arena_capacity());
            assert(bmx_embedded_arena_remaining() <= bmx_embedded_arena_capacity());
        }
        bmx_embedded_gc_poll();
    }
}

static void *worker(void *unused) {
    (void)unused;
    unsigned slot = bmx_embedded_gc_multicore_register();
    assert(slot == 1u);
    bmx_test_context_slot = slot;
    atomic_store_explicit(&worker_ready, 1, memory_order_release);
    while (!atomic_load_explicit(&start_allocating, memory_order_acquire)) sched_yield();
    allocate_blocks(slot);
    atomic_store_explicit(&worker_done, 1, memory_order_release);
    while (!atomic_load_explicit(&worker_exit, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        sched_yield();
    }
    assert(bmx_embedded_gc_multicore_unregister());
    bmx_test_context_slot = UINT32_MAX;
    return NULL;
}

int main(void) {
    bmx_embedded_gc_multicore_initialize();
    bmx_test_context_slot = bmx_embedded_gc_multicore_register();
    assert(bmx_test_context_slot == 0u);
    for (unsigned index = 0; index < ALLOCATION_COUNT / 8u; ++index) {
        reusable[index] = bbMemAlloc(ALLOCATION_SIZE);
        assert(reusable[index]);
    }
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, worker, NULL));
    while (!atomic_load_explicit(&worker_ready, memory_order_acquire)) sched_yield();
    atomic_store_explicit(&start_allocating, 1, memory_order_release);
    allocate_blocks(0u);
    while (!atomic_load_explicit(&worker_done, memory_order_acquire)) sched_yield();

    assert(bmx_embedded_arena_allocation_count() == 2u * ALLOCATION_COUNT + ALLOCATION_COUNT / 8u);
    assert(bmx_embedded_heap_integrity_valid());
    assert(bmx_embedded_collect_objects() == 0u);
    assert(bmx_embedded_heap_integrity_valid());
    for (unsigned slot = 0; slot < 2u; ++slot) {
        for (unsigned index = 0; index < ALLOCATION_COUNT; ++index) {
            uint8_t *block = blocks[slot][index];
            for (unsigned byte = 0; byte < ALLOCATION_SIZE; ++byte)
                assert(block[byte] == (uint8_t)(slot * ALLOCATION_COUNT + index + byte));
            for (unsigned other = index + 1u; other < ALLOCATION_COUNT; ++other)
                assert(block != blocks[slot][other]);
            for (unsigned other = 0; other < ALLOCATION_COUNT; ++other)
                if (slot == 0u) assert(block != blocks[1][other]);
        }
    }

    atomic_store_explicit(&worker_exit, 1, memory_order_release);
    assert(!pthread_join(thread, NULL));
    assert(bmx_embedded_gc_multicore_unregister());
    puts("PASS: concurrent raw allocation, free/reuse and collector rendezvous");
}
