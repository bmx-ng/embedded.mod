#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#define BMX_EMBEDDED_ARENA_SIZE (64u * 1024u)
#include "embedded_runtime_test.c"

typedef struct StaticFieldNode {
    BMXEmbeddedObject object;
    void *children[2];
} StaticFieldNode;

static const BMXEmbeddedTypeDescriptor child_type = {
    .name = "StaticFieldChild", .instance_size = sizeof(BMXEmbeddedObject)
};
static const BMXEmbeddedValueField node_fields[] = {
    { (uint32_t)offsetof(StaticFieldNode, children), (uint32_t)sizeof(void *),
      2u, BMX_EMBEDDED_VALUE_OBJECT, NULL }
};
static const BMXEmbeddedTypeDescriptor node_type = {
    .name = "StaticFieldNode", .instance_size = sizeof(StaticFieldNode),
    .value_fields = node_fields, .value_field_count = 1u
};

int main(void) {
    StaticFieldNode *node = (StaticFieldNode *)bmx_embedded_object_allocate(&node_type);
    assert(node);
    BMXEmbeddedRootSlot slot = { &node, BMX_EMBEDDED_ROOT_OBJECT, NULL };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1u);
    node->children[0] = bmx_embedded_object_allocate(&child_type);
    node->children[1] = bmx_embedded_object_allocate(&child_type);
    assert(node->children[0] && node->children[1]);
    assert(bmx_embedded_object_allocate(&child_type));
    assert(bmx_embedded_collect_objects() == 1u);
    assert(bmx_embedded_object_live_count() == 3u);
    assert(bmx_embedded_heap_integrity_valid());
    node = NULL;
    assert(bmx_embedded_collect_objects() == 3u);
    assert(bmx_embedded_object_live_count() == 0u);
    bmx_embedded_root_frame_leave(&frame);
    puts("PASS: fixed object-field array tracing and reclamation");
}
