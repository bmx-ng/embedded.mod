#include "blitzmax/embedded_runtime.h"
#include <string.h>

#define BATCH 32
#define MAX_HOLES 512
#define CHURN_SLOTS 64
#define CHURN_STEPS 2048
static void *holes[MAX_HOLES], *guards[MAX_HOLES + BATCH];
static void *targets[BATCH], *allocated[BATCH], *churn[CHURN_SLOTS];
static uint32_t churn_sizes[CHURN_SLOTS];
static uint8_t churn_values[CHURN_SLOTS];
static uint32_t automatic_before, used_before, failures_before;
static int32_t hole_count;

/* Free targets backwards so exact-fit cases select targets[0..31].
   Guard payloads must survive; split cases also allow target coalescing.
   Setup and validation are never timed. */
static void free_targets(void) {
    for (int i = BATCH - 1; i >= 0; --i) bbMemFree(targets[i]);
}

int32_t bmx_allocation_prepare(int32_t kind, int32_t count) {
    if (count < 2 || count > MAX_HOLES) return 0;
    bmx_embedded_collect_objects();
    automatic_before = bmx_embedded_automatic_collection_count();
    hole_count = count;
    if (kind == 5) {
        for (int i = 0; i < CHURN_SLOTS; ++i) {
            churn_sizes[i] = 16 + (i * 73u) % 256;
            churn_values[i] = (uint8_t)i;
            churn[i] = bbMemAlloc(churn_sizes[i]);
            if (!churn[i]) return 0;
            memset(churn[i], churn_values[i], churn_sizes[i]);
        }
    } else {
        for (int i = 0; i < count; ++i) {
            holes[i] = bbMemAlloc(16);
            guards[i] = bbMemAlloc(16);
            if (!holes[i] || !guards[i]) return 0;
            memset(guards[i], 0x5a, 16);
        }
        for (int i = 0; i < BATCH; ++i) {
            targets[i] = bbMemAlloc(kind == 3 ? 256 : 128);
            guards[count + i] = bbMemAlloc(kind == 3 ? 256 : 128);
            if (!targets[i] || !guards[count + i]) return 0;
            memset(guards[count + i], 0x5a, 16);
            allocated[i] = NULL;
        }
        if (kind >= 2) free_targets();
        for (int i = 0; i < count; ++i) {
            if (kind == 1 && i == count / 2) free_targets();
            bbMemFree(holes[i]);
        }
        if (kind == 0) free_targets();
    }
    used_before = bmx_embedded_arena_used();
    failures_before = bmx_embedded_arena_failure_count();
    return bmx_embedded_heap_integrity_valid() &&
        automatic_before == bmx_embedded_automatic_collection_count();
}

int32_t bmx_allocation_run(int32_t kind) {
    if (kind == 5) {
        uint32_t random = 12345;
        for (int i = 0; i < CHURN_STEPS; ++i) {
            const uint32_t slot = (uint32_t)i * 17 % CHURN_SLOTS;
            bbMemFree(churn[slot]);
            random = random * 1664525u + 1013904223u;
            churn_sizes[slot] = 16 + ((random >> 16) % 497);
            churn_values[slot] = (uint8_t)i;
            churn[slot] = bbMemAlloc(churn_sizes[slot]);
            if (!churn[slot]) return 0;
            memset(churn[slot], churn_values[slot], churn_sizes[slot]);
        }
    } else {
        const uint32_t size = kind == 3 ? 192 : 128;
        for (int i = 0; i < BATCH; ++i) {
            /* Use the non-collecting API for deliberate failure, so this
               control measures a single unsuccessful free-list search. */
            allocated[i] = kind == 4 ?
                bmx_embedded_arena_allocate(bmx_embedded_arena_capacity()) : bbMemAlloc(size);
        }
    }
    return 1;
}

int32_t bmx_allocation_check(int32_t kind) {
    if (!bmx_embedded_heap_integrity_valid() ||
        automatic_before != bmx_embedded_automatic_collection_count()) return -__LINE__;
    if (bmx_embedded_arena_failure_count() != failures_before + (kind == 4 ? BATCH : 0)) return -__LINE__;
    if (kind == 5) {
        for (int i = 0; i < CHURN_SLOTS; ++i) {
            for (uint32_t j = 0; j < churn_sizes[i]; ++j)
                if (((uint8_t *)churn[i])[j] != churn_values[i]) return -__LINE__;
            bbMemFree(churn[i]);
            churn[i] = NULL;
        }
    } else {
        if (bmx_embedded_arena_used() != used_before) return -__LINE__;
        for (int i = 0; i < BATCH; ++i) {
            if (kind == 4) { if (allocated[i]) return -__LINE__; }
            else {
                /* Larger targets may have coalesced before this split case:
                   validate reuse and non-overlap rather than assuming that
                   each result begins at an original target address. */
                if (!allocated[i] || (kind != 3 && allocated[i] != targets[i])) return -__LINE__;
                memset(allocated[i], i + 1, kind == 3 ? 192 : 128);
            }
        }
        for (int i = 0; i < hole_count + BATCH; ++i)
            for (int j = 0; j < 16; ++j)
                if (((uint8_t *)guards[i])[j] != 0x5a) return -__LINE__;
        if (kind != 4) {
            for (int i = 0; i < BATCH; ++i)
                for (int j = 0; j < (kind == 3 ? 192 : 128); ++j)
                    if (((uint8_t *)allocated[i])[j] != i + 1) return -__LINE__;
        }
        for (int i = 0; i < BATCH; ++i) bbMemFree(allocated[i]);
        for (int i = 0; i < hole_count + BATCH; ++i) bbMemFree(guards[i]);
    }
    return bmx_embedded_heap_integrity_valid();
}
