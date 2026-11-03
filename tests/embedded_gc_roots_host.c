/* Deterministic host stress for the precise root and collection contract. */
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#define BMX_EMBEDDED_ARENA_SIZE (128u * 1024u)
#include "embedded_runtime_test.c"

typedef struct HostNode {
    BMXEmbeddedObject object;
    struct HostNode *next;
    BMXEmbeddedArray *items;
    const BMXEmbeddedString *label;
    uint32_t serial;
} HostNode;

static const uint32_t node_refs[] = {offsetof(HostNode, next)};
static const uint32_t node_arrays[] = {offsetof(HostNode, items)};
static const uint32_t node_strings[] = {offsetof(HostNode, label)};
static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "HostNode", .instance_size = sizeof(HostNode),
    .reference_offsets = node_refs, .reference_count = 1,
    .array_offsets = node_arrays, .array_count = 1,
    .string_offsets = node_strings, .string_count = 1
};

static void check_heap(void) {
    assert(bmx_embedded_heap_integrity_valid());
    assert(bmx_embedded_invalid_reference_count() == 0);
}

int main(void) {
    HostNode *root = NULL;
    BMXEmbeddedRootSlot slot = {&root, BMX_EMBEDDED_ROOT_OBJECT, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1);

    for (uint32_t step = 1; step <= 600; ++step) {
        HostNode *node = (HostNode *)bmx_embedded_object_allocate(&node_type);
        assert(node);
        /* This local root protects the node while Array and String allocations
           may trigger collection, just as compiler-emitted temporaries do. */
        BMXEmbeddedRootSlot temporary = {&node, BMX_EMBEDDED_ROOT_OBJECT, NULL};
        BMXEmbeddedRootFrame local_frame;
        bmx_embedded_root_frame_enter(&local_frame, &temporary, 1);
        node->serial = step;
        node->next = root ? root : node;
        node->items = bmx_embedded_array_new_1d(3, sizeof(void *),
            BMX_EMBEDDED_ARRAY_ELEMENT_OBJECT, NULL, NULL);
        assert(node->items);
        node->label = bmx_embedded_string_allocate(4);
        assert(node->label);
        uint16_t *characters = (uint16_t *)node->label->buf;
        characters[0] = 'N'; characters[1] = 'O';
        characters[2] = 'D'; characters[3] = 'E';
        void **items = (void **)((uint8_t *)node->items +
            bmx_embedded_align_size((uint32_t)sizeof(BMXEmbeddedArray)));
        items[0] = node;
        items[1] = root ? (void *)root : (void *)node;
        root = node;
        bmx_embedded_root_frame_leave(&local_frame);

        if (step % 3 == 0) {
            bmx_embedded_collect_objects();
            check_heap();
            assert(root->serial == step);
            assert(root->label->buf[0] == 'N');
            assert(root->next->serial > 0 && root->next->serial <= step);
        }
        if (step % 11 == 0) {
            /* Rapid root changes release a cyclic graph. */
            root = NULL;
            bmx_embedded_collect_objects();
            check_heap();
            assert(bmx_embedded_object_live_count() == 0);
        }
    }
    root = NULL;
    bmx_embedded_collect_objects();
    check_heap();
    assert(bmx_embedded_object_live_count() == 0);

    /* An invalid precise edge must abort collection before sweeping. Once
       repaired, the same reachable object remains usable. */
    root = (HostNode *)bmx_embedded_object_allocate(&node_type);
    assert(root);
    root->serial = 700;
    root->next = (HostNode *)(uintptr_t)0x1234u;
    const uint32_t live_before_invalid = bmx_embedded_object_live_count();
    assert(bmx_embedded_collect_objects() == 0);
    assert(bmx_embedded_invalid_reference_count() > 0);
    assert(bmx_embedded_object_live_count() == live_before_invalid);
    assert(bmx_embedded_heap_integrity_valid());
    root->next = root;
    bmx_embedded_collect_objects();
    check_heap();
    assert(root->serial == 700);
    root = NULL;
    bmx_embedded_collect_objects();
    check_heap();
    assert(bmx_embedded_object_live_count() == 0);
    bmx_embedded_root_frame_leave(&frame);

    /* Fill every reusable block and the arena tail with non-collectable raw
       memory. Each managed allocation must throw its own prebuilt exception
       after an unsuccessful collection, leaving the heap valid. */
    void *raw[4096];
    uint32_t raw_count = 0;
    while (raw_count < 4096 && (raw[raw_count] = bmx_embedded_arena_allocate(16)))
        ++raw_count;
    assert(raw_count > 0 && raw_count < 4096);
    for (unsigned kind = 0; kind < 3; ++kind) {
        BMXEmbeddedExceptionFrame failure;
        bmx_embedded_exception_enter(&failure);
        if (setjmp(failure.buffer) == 0) {
            if (kind == 0) (void)bmx_embedded_object_allocate(&node_type);
            else if (kind == 1) (void)bmx_embedded_array_new_1d(8, sizeof(void *),
                BMX_EMBEDDED_ARRAY_ELEMENT_OBJECT, NULL, NULL);
            else (void)bmx_embedded_string_allocate(8);
            assert(!"managed allocation should throw when the arena is full");
        }
        BMXEmbeddedException caught = bmx_embedded_exception_catch();
        assert(caught.kind == BMX_EMBEDDED_EXCEPTION_STRING);
        check_heap();
    }
    while (raw_count) bbMemFree(raw[--raw_count]);
    bmx_embedded_collect_objects();
    check_heap();
    puts("PASS: root churn, collection validation and Object/Array/String exhaustion");
}
