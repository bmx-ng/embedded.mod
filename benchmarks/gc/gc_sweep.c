#include "blitzmax/embedded_runtime.h"
#include <string.h>

/* Keep setup and validation outside the timed collection. Raw gaps are
   deliberately freed in address order, reversing the old free-list order. */
typedef struct SweepNode {
    BMXEmbeddedObject object;
    struct SweepNode *next;
    uint32_t value;
} SweepNode;
static const uint32_t offsets[] = { offsetof(SweepNode, next) };
static const BMXEmbeddedTypeDescriptor type = {
    .name = "SweepNode", .instance_size = sizeof(SweepNode),
    .reference_offsets = offsets, .reference_count = 1
};
static void *gaps[2048];
static SweepNode *head;
static uint32_t root_token;
static uint32_t automatic_before;

int32_t bmx_sweep_prepare(int32_t kind, int32_t count) {
    if (count < 1 || count > 2048) return 0;
    bmx_embedded_collect_objects();
    automatic_before = bmx_embedded_automatic_collection_count();
    head = NULL;
    SweepNode *tail = NULL;
    for (int32_t i = 0; i < count; ++i) {
        SweepNode *node = bmx_embedded_object_allocate(&type);
        if (!node) return 0;
        node->value = (uint32_t)i + 1;
        if (kind == 0) {
            if (tail) tail->next = node;
            else { head = node; root_token = bmx_embedded_object_root_retain(&head->object); }
            tail = node;
        }
        gaps[i] = NULL;
        if (kind >= 2) {
            gaps[i] = bbMemAlloc(16);
            if (!gaps[i]) return 0;
            memset(gaps[i], 0x5a, 16);
        }
    }
    if (kind >= 2) {
        for (int32_t i = 0; i < count; ++i) {
            if (kind == 2 || (i % 2 == 0)) {
                bbMemFree(gaps[i]);
                gaps[i] = NULL;
            }
        }
    }
    return automatic_before == bmx_embedded_automatic_collection_count() &&
        bmx_embedded_heap_integrity_valid();
}

int32_t bmx_sweep_check(int32_t kind, int32_t count) {
    if (!bmx_embedded_heap_integrity_valid() || bmx_embedded_invalid_reference_count() ||
        bmx_embedded_last_reclaimed_object_count() != (uint32_t)(kind ? count : 0) ||
        automatic_before != bmx_embedded_automatic_collection_count()) return 0;
    if (kind == 0) {
        SweepNode *node = head;
        for (int32_t i = 0; i < count; ++i) {
            if (!node || node->value != (uint32_t)i + 1) return 0;
            node = node->next;
        }
        if (node) return 0;
        bmx_embedded_object_root_release(root_token);
        head = NULL;
    }
    for (int32_t i = 0; i < count; ++i) {
        if (gaps[i]) {
            for (int j = 0; j < 16; ++j) if (((unsigned char *)gaps[i])[j] != 0x5a) return 0;
            bbMemFree(gaps[i]);
            gaps[i] = NULL;
        }
    }
    bmx_embedded_collect_objects();
    /* Exercise the rebuilt free list, splitting and rejoining a free run. */
    void *reused = bbMemAlloc((size_t)count * 32);
    if (!reused) return 0;
    memset(reused, 0xa5, (size_t)count * 32);
    bbMemFree(reused);
    return bmx_embedded_heap_integrity_valid();
}
