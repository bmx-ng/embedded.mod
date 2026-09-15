#include <stddef.h>
#include <stdint.h>

#include "blitzmax/embedded_runtime.h"

#define BMX_EMBEDDED_TEST_OOM_BLOCK_COUNT 1024u

static void *bmx_embedded_test_oom_blocks[BMX_EMBEDDED_TEST_OOM_BLOCK_COUNT];
static uint32_t bmx_embedded_test_oom_block_count;

void bmx_embedded_test_oom_end(void);

const BMXEmbeddedString *bmx_embedded_test_object_to_string(BMXEmbeddedObject *object) {
    if (!object || !object->type || !object->type->to_string) return NULL;
    return object->type->to_string(object);
}

int32_t bmx_embedded_test_oom_begin(void) {
    static const size_t sizes[] = { 256u, 64u, 16u };
    if (bmx_embedded_test_oom_block_count) return 0;
    for (size_t size_index = 0u; size_index < sizeof(sizes) / sizeof(sizes[0]); ++size_index) {
        while (bmx_embedded_test_oom_block_count < BMX_EMBEDDED_TEST_OOM_BLOCK_COUNT) {
            void *block = bbMemAlloc(sizes[size_index]);
            if (!block) break;
            bmx_embedded_test_oom_blocks[bmx_embedded_test_oom_block_count++] = block;
        }
    }
    const int32_t ready = bmx_embedded_test_oom_block_count > 0u &&
        bmx_embedded_test_oom_block_count < BMX_EMBEDDED_TEST_OOM_BLOCK_COUNT &&
        bmx_embedded_heap_integrity_valid();
    if (!ready) bmx_embedded_test_oom_end();
    return ready;
}

void bmx_embedded_test_oom_end(void) {
    while (bmx_embedded_test_oom_block_count) {
        bbMemFree(bmx_embedded_test_oom_blocks[--bmx_embedded_test_oom_block_count]);
        bmx_embedded_test_oom_blocks[bmx_embedded_test_oom_block_count] = NULL;
    }
}
