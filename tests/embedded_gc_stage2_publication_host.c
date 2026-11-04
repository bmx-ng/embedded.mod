/* Stage 2: atomic Object/Array/String handoff and GC roots across mutators. */
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#define BMX_EMBEDDED_MULTICORE 1
#define BMX_EMBEDDED_GC_WAIT_BUDGET 100000u
#define BMX_EMBEDDED_ARENA_SIZE (64u * 1024u)
#include "embedded_runtime_test.c"

_Thread_local unsigned bmx_test_context_slot = UINT32_MAX;

typedef struct PublicationNode {
    BMXEmbeddedObject object;
    struct PublicationNode *next;
    uint32_t value;
} PublicationNode;

static const uint32_t node_references[] = {offsetof(PublicationNode, next)};
static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "PublicationNode", .instance_size = sizeof(PublicationNode),
    .reference_offsets = node_references, .reference_count = 1u
};

static BMXEmbeddedAtomicReference shared_object;
static BMXEmbeddedAtomicReference shared_array;
static BMXEmbeddedAtomicReference shared_string;
static atomic_uint phase;
static atomic_uint command;

static void wait_phase(unsigned expected) {
    for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
        unsigned value = atomic_load_explicit(&phase, memory_order_acquire);
        assert(value <= expected);
        if (value == expected) return;
        sched_yield();
    }
    assert(!"worker did not reach publication phase");
}

static void *worker(void *unused) {
    (void)unused;
    assert(bmx_embedded_gc_multicore_register() == 1u);
    bmx_test_context_slot = 1u;

    PublicationNode *node = NULL;
    BMXEmbeddedArray *array = NULL;
    BMXEmbeddedString *text = NULL;
    BMXEmbeddedRootSlot slots[] = {
        {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL},
        {&array, BMX_EMBEDDED_ROOT_ARRAY, NULL},
        {&text, BMX_EMBEDDED_ROOT_STRING, NULL}
    };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, 3u);
    node = bmx_embedded_object_allocate(&node_type);
    array = bmx_embedded_array_new_1d(1, sizeof(uint32_t),
        BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
    text = bmx_embedded_string_allocate(1);
    assert(node && array && text);
    node->next = node;
    node->value = 11u;
    *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) = 12u;
    ((uint16_t *)text->buf)[0] = 'A';

    bmx_embedded_atomic_reference_store(&shared_object, node);
    bmx_embedded_atomic_reference_store(&shared_array, array);
    bmx_embedded_atomic_reference_store(&shared_string, text);
    node = NULL;
    array = NULL;
    text = NULL;
    atomic_store_explicit(&phase, 1u, memory_order_release);

    while (!atomic_load_explicit(&command, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        sched_yield();
    }
    node = bmx_embedded_atomic_reference_load(&shared_object);
    array = bmx_embedded_atomic_reference_load(&shared_array);
    text = bmx_embedded_atomic_reference_load(&shared_string);
    assert(node && node->next == node && node->value == 22u);
    assert(*(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) == 23u);
    assert(text->buf[0] == 'B');
    node->value = 31u;
    *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) = 32u;
    ((uint16_t *)text->buf)[0] = 'C';
    node = NULL;
    array = NULL;
    text = NULL;
    atomic_store_explicit(&phase, 2u, memory_order_release);

    while (atomic_load_explicit(&command, memory_order_acquire) == 1u) {
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

    BMXEmbeddedRootSlot slots[] = {
        {&shared_object, BMX_EMBEDDED_ROOT_ATOMIC_OBJECT, NULL},
        {&shared_array, BMX_EMBEDDED_ROOT_ATOMIC_ARRAY, NULL},
        {&shared_string, BMX_EMBEDDED_ROOT_ATOMIC_STRING, NULL}
    };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, 3u);
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, worker, NULL));
    wait_phase(1u);

    assert(bmx_embedded_collect_objects() == 0u);
    assert(bmx_embedded_object_live_count() == 1u);
    assert(bmx_embedded_array_live_count() == 1u);
    assert(bmx_embedded_string_live_count() == 1u);
    assert(bmx_embedded_invalid_reference_count() == 0u);
    assert(bmx_embedded_heap_integrity_valid());

    PublicationNode *node = bmx_embedded_atomic_reference_load(&shared_object);
    BMXEmbeddedArray *array = bmx_embedded_atomic_reference_load(&shared_array);
    BMXEmbeddedString *text = bmx_embedded_atomic_reference_load(&shared_string);
    assert(node && node->next == node && node->value == 11u);
    assert(*(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) == 12u);
    assert(text->buf[0] == 'A');
    node->value = 22u;
    *(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) = 23u;
    ((uint16_t *)text->buf)[0] = 'B';
    node = NULL;
    array = NULL;
    text = NULL;
    atomic_store_explicit(&command, 1u, memory_order_release);
    wait_phase(2u);

    node = bmx_embedded_atomic_reference_load(&shared_object);
    array = bmx_embedded_atomic_reference_load(&shared_array);
    text = bmx_embedded_atomic_reference_load(&shared_string);
    assert(node->value == 31u);
    assert(*(uint32_t *)bmx_embedded_array_element(array, 0, sizeof(uint32_t)) == 32u);
    assert(text->buf[0] == 'C');
    node = NULL;
    array = NULL;
    text = NULL;
    bmx_embedded_atomic_reference_store(&shared_object, NULL);
    bmx_embedded_atomic_reference_store(&shared_array, NULL);
    bmx_embedded_atomic_reference_store(&shared_string, NULL);
    assert(bmx_embedded_collect_objects() == 1u);
    assert(bmx_embedded_last_reclaimed_array_count() == 1u);
    assert(bmx_embedded_last_reclaimed_string_count() == 1u);
    assert(bmx_embedded_object_live_count() == 0u);
    assert(bmx_embedded_array_live_count() == 0u);
    assert(bmx_embedded_string_live_count() == 0u);
    assert(bmx_embedded_heap_integrity_valid());

    atomic_store_explicit(&command, 2u, memory_order_release);
    assert(!pthread_join(thread, NULL));
    bmx_embedded_root_frame_leave(&frame);
    assert(bmx_embedded_gc_multicore_unregister());
    puts("PASS: atomic Object/Array/String publication, cycle and handoff reclamation");
    return 0;
}
