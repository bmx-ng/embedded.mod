/* Stage 2 managed allocation: initialization, roots and worker-local OOM. */
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>

#define BMX_EMBEDDED_MULTICORE 1
#define BMX_EMBEDDED_GC_WAIT_BUDGET 1000u
#define BMX_EMBEDDED_ARENA_SIZE (64u * 1024u)
#include "embedded_runtime_test.c"

_Thread_local unsigned bmx_test_context_slot = UINT32_MAX;

typedef struct TestNode {
    BMXEmbeddedObject object;
    uint32_t value;
} TestNode;

static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "Stage2Node", .instance_size = sizeof(TestNode)
};
static atomic_int initializer_entered;
static atomic_int initializer_continue;
static atomic_int worker_ready;
static atomic_int worker_drop;
static atomic_int worker_dropped;
static atomic_int stress_start;
static atomic_int stress_done;
static atomic_int worker_exit;

static void wait_flag(atomic_int *flag) {
    for (unsigned attempt = 0; attempt < 1000000u; ++attempt) {
        if (atomic_load_explicit(flag, memory_order_acquire)) return;
        sched_yield();
    }
    assert(!"worker did not reach the expected phase");
}

static void initialize_element(void *element) {
    if (!atomic_exchange_explicit(&initializer_entered, 1, memory_order_acq_rel))
        wait_flag(&initializer_continue);
    *(uint32_t *)element = 0x1234u;
}

static void *worker(void *unused) {
    (void)unused;
    unsigned slot = bmx_embedded_gc_multicore_register();
    assert(slot == 1u);
    bmx_test_context_slot = slot;

    TestNode *node = NULL;
    BMXEmbeddedArray *array = NULL;
    BMXEmbeddedString *text = NULL;
    BMXEmbeddedRootSlot slots[] = {
        {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL},
        {&array, BMX_EMBEDDED_ROOT_ARRAY, NULL},
        {&text, BMX_EMBEDDED_ROOT_STRING, NULL}
    };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, 3u);

    node = (TestNode *)bmx_embedded_object_allocate(&node_type);
    assert(node);
    node->value = 0x5678u;
    array = bmx_embedded_array_new_1d(8, sizeof(uint32_t),
        BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, initialize_element, NULL);
    assert(array);
    text = bmx_embedded_string_allocate(4);
    assert(text);
    uint16_t *characters = (uint16_t *)text->buf;
    for (unsigned index = 0; index < 4u; ++index) characters[index] = (uint16_t)('A' + index);

    /* The worker cannot collect on allocation failure. Its own handler must
       receive the preallocated OOM exception without disturbing the owner. */
    BMXEmbeddedExceptionFrame exception_frame;
    bmx_embedded_exception_enter(&exception_frame);
    if (setjmp(exception_frame.buffer) == 0) {
        (void)bmx_embedded_string_allocate(40000);
        assert(!"oversize worker allocation must throw");
    }
    BMXEmbeddedException caught = bmx_embedded_exception_catch();
    assert(caught.kind == BMX_EMBEDDED_EXCEPTION_STRING);

    atomic_store_explicit(&worker_ready, 1, memory_order_release);
    while (!atomic_load_explicit(&worker_drop, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        sched_yield();
    }
    assert(node->value == 0x5678u);
    for (unsigned index = 0; index < 8u; ++index)
        assert(*(uint32_t *)bmx_embedded_array_element(array, (int32_t)index, sizeof(uint32_t)) == 0x1234u);
    for (unsigned index = 0; index < 4u; ++index) assert(text->buf[index] == (uint16_t)('A' + index));
    node = NULL;
    array = NULL;
    text = NULL;
    atomic_store_explicit(&worker_dropped, 1, memory_order_release);
    while (!atomic_load_explicit(&stress_start, memory_order_acquire)) {
        bmx_embedded_gc_poll();
        sched_yield();
    }
    for (unsigned index = 0; index < 64u; ++index) {
        node = (TestNode *)bmx_embedded_object_allocate(&node_type);
        array = bmx_embedded_array_new_1d(8, sizeof(uint32_t),
            BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
        text = bmx_embedded_string_allocate(4);
        assert(node && array && text);
        bmx_embedded_gc_poll();
    }
    node = NULL;
    array = NULL;
    text = NULL;
    atomic_store_explicit(&stress_done, 1, memory_order_release);
    while (!atomic_load_explicit(&worker_exit, memory_order_acquire)) {
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
    bmx_test_context_slot = bmx_embedded_gc_multicore_register();
    assert(bmx_test_context_slot == 0u);
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, worker, NULL));

    wait_flag(&initializer_entered);
    uint32_t collections_before = bmx_embedded_collection_count();
    assert(bmx_embedded_collect_objects() == 0u);
    assert(bmx_embedded_collection_count() == collections_before);
    assert(bmx_embedded_heap_integrity_valid());
    atomic_store_explicit(&initializer_continue, 1, memory_order_release);
    wait_flag(&worker_ready);

    assert(bmx_embedded_collect_objects() == 0u);
    assert(bmx_embedded_object_live_count() == 1u);
    assert(bmx_embedded_array_live_count() == 1u);
    assert(bmx_embedded_string_live_count() == 1u);
    assert(bmx_embedded_heap_integrity_valid());
    atomic_store_explicit(&worker_drop, 1, memory_order_release);
    wait_flag(&worker_dropped);
    assert(bmx_embedded_collect_objects() == 1u);
    assert(bmx_embedded_last_reclaimed_array_count() == 1u);
    assert(bmx_embedded_last_reclaimed_string_count() == 1u);
    assert(bmx_embedded_object_live_count() == 0u);
    assert(bmx_embedded_array_live_count() == 0u);
    assert(bmx_embedded_string_live_count() == 0u);
    assert(bmx_embedded_heap_integrity_valid());

    TestNode *owner_node = NULL;
    BMXEmbeddedArray *owner_array = NULL;
    BMXEmbeddedString *owner_text = NULL;
    BMXEmbeddedRootSlot owner_slots[] = {
        {&owner_node, BMX_EMBEDDED_ROOT_OBJECT, NULL},
        {&owner_array, BMX_EMBEDDED_ROOT_ARRAY, NULL},
        {&owner_text, BMX_EMBEDDED_ROOT_STRING, NULL}
    };
    BMXEmbeddedRootFrame owner_frame;
    bmx_embedded_root_frame_enter(&owner_frame, owner_slots, 3u);
    atomic_store_explicit(&stress_start, 1, memory_order_release);
    for (unsigned index = 0; index < 64u; ++index) {
        owner_node = (TestNode *)bmx_embedded_object_allocate(&node_type);
        owner_array = bmx_embedded_array_new_1d(8, sizeof(uint32_t),
            BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
        owner_text = bmx_embedded_string_allocate(4);
        assert(owner_node && owner_array && owner_text);
        assert(bmx_embedded_object_live_count() <= 128u);
        assert(bmx_embedded_array_live_count() <= 128u);
        assert(bmx_embedded_string_live_count() <= 128u);
    }
    owner_node = NULL;
    owner_array = NULL;
    owner_text = NULL;
    bmx_embedded_root_frame_leave(&owner_frame);
    wait_flag(&stress_done);
    assert(bmx_embedded_heap_integrity_valid());
    assert(bmx_embedded_collect_objects() == 128u);
    assert(bmx_embedded_last_reclaimed_array_count() == 128u);
    assert(bmx_embedded_last_reclaimed_string_count() == 128u);
    assert(bmx_embedded_heap_integrity_valid());

    atomic_store_explicit(&worker_exit, 1, memory_order_release);
    assert(!pthread_join(thread, NULL));
    assert(bmx_embedded_gc_multicore_unregister());
    puts("PASS: concurrent Object/Array/String allocation, initialization, OOM and reclamation");
}
