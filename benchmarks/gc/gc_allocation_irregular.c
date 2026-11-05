#include <stdint.h>
#include <blitzmax/embedded_runtime.h>

typedef struct {
    BMXEmbeddedObject object;
    uint32_t value;
    uint8_t payload[8];
} IrregularSmallNode;

typedef struct {
    BMXEmbeddedObject object;
    uint32_t value;
    uint8_t payload[40];
} IrregularMediumNode;

typedef struct {
    BMXEmbeddedObject object;
    uint32_t value;
    uint8_t payload[104];
} IrregularLargeNode;

typedef struct {
    BMXEmbeddedObject object;
    uint32_t value;
    uint8_t payload[232];
} IrregularXLNode;

static const BMXEmbeddedTypeDescriptor irregular_types[4] = {
    { .name = "IrregularSmallNode", .instance_size = sizeof(IrregularSmallNode) },
    { .name = "IrregularMediumNode", .instance_size = sizeof(IrregularMediumNode) },
    { .name = "IrregularLargeNode", .instance_size = sizeof(IrregularLargeNode) },
    { .name = "IrregularXLNode", .instance_size = sizeof(IrregularXLNode) }
};

static uint32_t worker_checksum;

/* The owner collects only after both tasks finish a batch. The native loop
   avoids generated loop polls and root-frame work in the timed interval. */
uint32_t bmx_gc_allocation_irregular_batch(uint32_t seed, uint32_t count) {
    uint32_t state = seed ^ 0x9e3779b9u;
    uint32_t checksum = 0;
    for (uint32_t index = 0; index < count; ++index) {
        state = state * 1664525u + 1013904223u;
        IrregularSmallNode *node = (IrregularSmallNode *)
            bmx_embedded_object_allocate(&irregular_types[state >> 30]);
        node->value = seed + index;
        checksum += node->value;
    }
    return checksum;
}

void bmx_gc_allocation_irregular_add_worker_checksum(uint32_t checksum) {
    worker_checksum += checksum;
}

uint32_t bmx_gc_allocation_irregular_worker_checksum(void) {
    return worker_checksum;
}

uint32_t bmx_gc_allocation_irregular_size(uint32_t kind) {
    return kind < 4u ? irregular_types[kind].instance_size : 0u;
}
