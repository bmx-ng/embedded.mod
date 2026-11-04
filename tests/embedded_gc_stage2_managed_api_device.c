#include <stdatomic.h>
#include <stdint.h>

#if defined(PICO_ON_DEVICE) && PICO_ON_DEVICE
#include "pico/stdlib.h"
static void api_yield(void) { tight_loop_contents(); }
#elif defined(BMX_ESP32) && BMX_ESP32
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
static void api_yield(void) { taskYIELD(); }
#else
#error "The managed worker API test supports Pico and ESP32"
#endif

static atomic_uint api_job;
static atomic_uint api_ready;
static atomic_uint api_release;
static atomic_uint api_failed;
static atomic_uintptr_t api_buffer;

void bmx_stage2_api_set_buffer(void *buffer) {
    atomic_store_explicit(&api_buffer, (uintptr_t)buffer, memory_order_release);
}

void *bmx_stage2_api_get_buffer(void) {
    return (void *)atomic_load_explicit(&api_buffer, memory_order_acquire);
}

void bmx_stage2_api_set_job(uint32_t job) {
    atomic_store_explicit(&api_ready, 0u, memory_order_relaxed);
    atomic_store_explicit(&api_release, 0u, memory_order_relaxed);
    atomic_store_explicit(&api_failed, 0u, memory_order_relaxed);
    atomic_store_explicit(&api_job, job, memory_order_release);
}

uint32_t bmx_stage2_api_job(void) {
    return atomic_load_explicit(&api_job, memory_order_acquire);
}

void bmx_stage2_api_ready(uint32_t job) {
    atomic_store_explicit(&api_ready, job, memory_order_release);
}

int32_t bmx_stage2_api_wait_ready(uint32_t job) {
    for (unsigned attempt = 0; attempt < 10000000u; ++attempt) {
        if (atomic_load_explicit(&api_ready, memory_order_acquire) == job)
            return 1;
        api_yield();
    }
    return 0;
}

void bmx_stage2_api_release(uint32_t job) {
    atomic_store_explicit(&api_release, job, memory_order_release);
}

uint32_t bmx_stage2_api_released(void) {
    return atomic_load_explicit(&api_release, memory_order_acquire);
}

void bmx_stage2_api_failed(void) {
    atomic_store_explicit(&api_failed, 1u, memory_order_release);
}

uint32_t bmx_stage2_api_failure(void) {
    return atomic_load_explicit(&api_failed, memory_order_acquire);
}

void bmx_stage2_api_yield(void) { api_yield(); }
