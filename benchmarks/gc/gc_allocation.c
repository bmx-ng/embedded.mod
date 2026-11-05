#include <stdatomic.h>
#include <stdint.h>
#include <blitzmax/embedded_runtime.h>

#ifndef BMX_EMBEDDED_MULTICORE
#define BMX_EMBEDDED_MULTICORE 0
#endif

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/stdlib.h"
static void benchmark_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void benchmark_yield(void) { taskYIELD(); }
#else
#error "The allocation benchmark supports Pico and ESP32"
#endif

static atomic_uint requested_batch;
static atomic_uint completed_batch;
#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE && defined(BMX_EMBEDDED_GC_PERF_COUNTERS) && BMX_EMBEDDED_GC_PERF_COUNTERS
static atomic_flag benchmark_uncontended_lock = ATOMIC_FLAG_INIT;
#endif
/* Written by the worker and read only after join. Avoid a 64-bit atomic on
   targets where the compiler would need a libatomic helper. */
static uint64_t worker_allocation_us;

typedef struct {
    BMXEmbeddedObject object;
    uint32_t value;
} BenchmarkNativeNode;

static const BMXEmbeddedTypeDescriptor benchmark_native_type = {
    .name = "BenchmarkNativeNode",
    .instance_size = sizeof(BenchmarkNativeNode)
};

/* Only called in a batch with enough arena space and no concurrent
   collection. It removes generated loop polls and root-frame traffic from
   the timed allocation comparison. */
uint32_t bmx_gc_allocation_native_batch(uint32_t seed) {
    uint32_t checksum = 0;
    for (uint32_t index = 0; index < 64u; ++index) {
        BenchmarkNativeNode *node = (BenchmarkNativeNode *)
            bmx_embedded_object_allocate(&benchmark_native_type);
        node->value = seed + index;
        checksum += node->value;
    }
    return checksum;
}

int32_t bmx_gc_allocation_multicore(void) { return BMX_EMBEDDED_MULTICORE; }
int32_t bmx_gc_allocation_instrumented(void) {
#if defined(BMX_EMBEDDED_GC_PERF_COUNTERS) && BMX_EMBEDDED_GC_PERF_COUNTERS
    return 1;
#else
    return 0;
#endif
}
void bmx_gc_allocation_stats_reset(void) {
#if defined(BMX_EMBEDDED_GC_PERF_COUNTERS) && BMX_EMBEDDED_GC_PERF_COUNTERS
    bmx_embedded_gc_allocator_lock_counters_reset();
#endif
}
uint32_t bmx_gc_allocation_lock_entries(void) {
#if defined(BMX_EMBEDDED_GC_PERF_COUNTERS) && BMX_EMBEDDED_GC_PERF_COUNTERS
    return bmx_embedded_gc_allocator_lock_entries();
#else
    return 0u;
#endif
}
uint32_t bmx_gc_allocation_lock_contended(void) {
#if defined(BMX_EMBEDDED_GC_PERF_COUNTERS) && BMX_EMBEDDED_GC_PERF_COUNTERS
    return bmx_embedded_gc_allocator_lock_contended();
#else
    return 0u;
#endif
}
uint32_t bmx_gc_allocation_lock_spins(void) {
#if defined(BMX_EMBEDDED_GC_PERF_COUNTERS) && BMX_EMBEDDED_GC_PERF_COUNTERS
    return bmx_embedded_gc_allocator_lock_spins();
#else
    return 0u;
#endif
}
uint64_t bmx_gc_allocation_lock_wait_us(void) {
#if defined(BMX_EMBEDDED_GC_PERF_TIME) && BMX_EMBEDDED_GC_PERF_TIME
    return bmx_embedded_gc_allocator_lock_wait_us();
#else
    return 0u;
#endif
}
int32_t bmx_gc_allocation_timed(void) {
#if defined(BMX_EMBEDDED_GC_PERF_TIME) && BMX_EMBEDDED_GC_PERF_TIME
    return 1;
#else
    return 0;
#endif
}
uint32_t bmx_gc_allocation_lock_pair_million_us(void) {
#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE && defined(BMX_EMBEDDED_GC_PERF_COUNTERS) && BMX_EMBEDDED_GC_PERF_COUNTERS
    uint32_t started = time_us_32();
    for (uint32_t index = 0; index < 1000000u; ++index) {
        while (atomic_flag_test_and_set_explicit(&benchmark_uncontended_lock,
                memory_order_acquire)) {}
        atomic_flag_clear_explicit(&benchmark_uncontended_lock, memory_order_release);
    }
    return time_us_32() - started;
#else
    return 0u;
#endif
}
int32_t bmx_gc_allocation_prepare(void) {
#if BMX_EMBEDDED_MULTICORE
    bmx_embedded_gc_multicore_initialize();
    return bmx_embedded_gc_multicore_register() == 0u;
#else
    return 1;
#endif
}
void bmx_gc_allocation_request(uint32_t batch) {
    atomic_store_explicit(&requested_batch, batch, memory_order_release);
}
uint32_t bmx_gc_allocation_requested(void) {
    return atomic_load_explicit(&requested_batch, memory_order_acquire);
}
void bmx_gc_allocation_complete(uint32_t batch) {
    atomic_store_explicit(&completed_batch, batch, memory_order_release);
}
uint32_t bmx_gc_allocation_completed(void) {
    return atomic_load_explicit(&completed_batch, memory_order_acquire);
}
void bmx_gc_allocation_add_worker_time(uint64_t us) {
    worker_allocation_us += us;
}
uint64_t bmx_gc_allocation_worker_time(void) {
    return worker_allocation_us;
}
void bmx_gc_allocation_yield(void) { benchmark_yield(); }
