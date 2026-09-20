#include "blitzmax/embedded_runtime.h"

#define CHECK(condition) do { if (!(condition)) return __LINE__; } while (0)

typedef struct TestObject {
    BMXEmbeddedObject object;
    struct TestObject *child;
    uint32_t value;
} TestObject;
static const uint32_t child_offsets[] = { offsetof(TestObject, child) };
static uint32_t calls, resurrected_root;
static int resurrect, throw_once;
static TestObject *resurrected;

static void finalize(void *value) {
    TestObject *object = value;
    ++calls;
    if (resurrect) {
        resurrected = object;
        resurrected_root = bmx_embedded_object_root_retain(&object->object);
    }
    if (throw_once) {
        throw_once = 0;
        bmx_embedded_exception_throw(bmx_embedded_exception_string(&bmx_embedded_empty_string));
    }
}
static const BMXEmbeddedTypeDescriptor ordinary_type = {
    .name = "SweepOrdinary", .instance_size = sizeof(TestObject),
    .reference_offsets = child_offsets, .reference_count = 1
};
static const BMXEmbeddedTypeDescriptor final_type = {
    .name = "SweepFinal", .instance_size = sizeof(TestObject),
    .reference_offsets = child_offsets, .reference_count = 1,
    .flags = BMX_EMBEDDED_TYPE_FLAG_HAS_FINALIZER, .finalizer = finalize
};

int32_t bmx_embedded_gc_sweep_conformance(void) {
    bmx_embedded_collect_objects();
    const uint32_t initial_live = bmx_embedded_object_live_count();
    const uint32_t initial_roots = bmx_embedded_object_root_count();
    calls = 0;
    resurrect = 1;
    TestObject *parent = bmx_embedded_object_allocate(&final_type);
    CHECK(parent);
    parent->child = bmx_embedded_object_allocate(&ordinary_type);
    CHECK(parent->child);
    parent->child->value = 12345;
    /* A finalizer cycle must not sweep its unreachable child. */
    CHECK(bmx_embedded_collect_objects() == 0 && calls == 1);
    CHECK(bmx_embedded_object_live_count() == initial_live + 2);
    CHECK(bmx_embedded_heap_integrity_valid());
    CHECK(resurrected == parent && parent->child->value == 12345);
    /* The all-live exit must clear per-collection statistics and state. */
    CHECK(bmx_embedded_collect_objects() == 0 && calls == 1);
    CHECK(bmx_embedded_last_finalized_object_count() == 0);
    CHECK(bmx_embedded_finalizer_pending_count() == 0);
    CHECK(bmx_embedded_last_reclaimed_bytes() == 0);
    CHECK(bmx_embedded_invalid_reference_count() == 0);
    bmx_embedded_object_root_release(resurrected_root);
    resurrected = NULL;
    resurrect = 0;
    CHECK(bmx_embedded_collect_objects() == 2 && calls == 1);
    CHECK(bmx_embedded_object_live_count() == initial_live);
    CHECK(bmx_embedded_heap_integrity_valid());

    /* Escaping a finalizer must leave pending finalizers eligible, and an
       already invoked finalizer must not run again. */
    CHECK(bmx_embedded_object_allocate(&final_type));
    CHECK(bmx_embedded_object_allocate(&final_type));
    throw_once = 1;
    BMXEmbeddedExceptionFrame frame;
    bmx_embedded_exception_enter(&frame);
    if (setjmp(frame.buffer) == 0) {
        bmx_embedded_collect_objects();
        bmx_embedded_exception_leave();
        return __LINE__;
    }
    BMXEmbeddedException caught = bmx_embedded_exception_catch();
    /* Throwing already removed the handler frame. */
    CHECK(caught.kind == BMX_EMBEDDED_EXCEPTION_STRING);
    CHECK(calls == 2 && bmx_embedded_finalizer_pending_count() == 0);
    CHECK(bmx_embedded_heap_integrity_valid());
    CHECK(bmx_embedded_collect_objects() == 0 && calls == 3);
    CHECK(bmx_embedded_collect_objects() == 2 && calls == 3);
    CHECK(bmx_embedded_object_live_count() == initial_live);
    /* Alternate live managed objects, garbage, and manual allocations.
       This exercises every boundary of a free run, including the tail. */
    TestObject *survivors[8];
    uint32_t tokens[8];
    void *raw[32];
    for (uint32_t i = 0; i < 32; ++i) {
        TestObject *object = bmx_embedded_object_allocate(&ordinary_type);
        CHECK(object);
        object->value = i;
        if (i % 4 == 0) {
            survivors[i / 4] = object;
            tokens[i / 4] = bmx_embedded_object_root_retain(&object->object);
        }
        raw[i] = bbMemAlloc(16);
        CHECK(raw[i]);
        *(uint32_t *)raw[i] = i + 100;
    }
    for (uint32_t i = 0; i < 32; i += 2) bbMemFree(raw[i]);
    CHECK(bmx_embedded_collect_objects() == 24);
    CHECK(bmx_embedded_heap_integrity_valid());
    for (uint32_t i = 0; i < 8; ++i) {
        CHECK(survivors[i]->value == i * 4);
        bmx_embedded_object_root_release(tokens[i]);
    }
    for (uint32_t i = 1; i < 32; i += 2) {
        CHECK(*(uint32_t *)raw[i] == i + 100);
        bbMemFree(raw[i]);
    }
    CHECK(bmx_embedded_collect_objects() == 8);
    CHECK(bmx_embedded_collect_objects() == 0);
    CHECK(bmx_embedded_last_reclaimed_bytes() == 0);
    CHECK(bmx_embedded_object_live_count() == initial_live);
    CHECK(bmx_embedded_object_root_count() == initial_roots);
    CHECK(bmx_embedded_heap_integrity_valid());
    return 0;
}
