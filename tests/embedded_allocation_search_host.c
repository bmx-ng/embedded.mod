/* Standalone host regression: run with run_allocation_search_host.py. */
#include <assert.h>
#include <stdio.h>
#define BMX_EMBEDDED_ARENA_SIZE 65536
#include "embedded_runtime_test.c"
int main(void) {
    unsigned cases = 0;
    for (unsigned split = 0; split < 2; ++split) {
        for (int count = 0; count <= 16; ++count) {
            for (int match = -1; match < count; ++match) {
                bmx_embedded_arena_offset = bmx_embedded_arena_high_water_mark = 0;
                bmx_embedded_heap_first = bmx_embedded_heap_last = bmx_embedded_heap_free = NULL;
                void *holes[16], *guards[16];
                for (int i = 0; i < count; ++i) {
                    holes[i] = bmx_embedded_arena_allocate(i == match ? (split ? 256 : 64) : 16);
                    guards[i] = bmx_embedded_arena_allocate(16);
                    assert(holes[i] && guards[i]);
                    memset(guards[i], i + 1, 16);
                }
                for (int i = count - 1; i >= 0; --i) bbMemFree(holes[i]);
                uint32_t before = bmx_embedded_arena_used();
                void *actual = bmx_embedded_arena_allocate(64);
                assert(actual);
                if (match >= 0) {
                    assert(actual == holes[match]);
                    assert(bmx_embedded_arena_used() == before);
                } else assert(bmx_embedded_arena_used() > before);
                memset(actual, 0xa5, 64);
                assert(bmx_embedded_heap_integrity_valid());
                for (int i = 0; i < count; ++i)
                    for (int j = 0; j < 16; ++j) assert(((unsigned char *)guards[i])[j] == i + 1);
                bbMemFree(actual);
                for (int i = 0; i < count; ++i) bbMemFree(guards[i]);
                assert(bmx_embedded_heap_integrity_valid());
                ++cases;
            }
        }
    }
    printf("PASS: %u exact/split/miss cases, free-list lengths 0..16, every match position\n", cases);
}
