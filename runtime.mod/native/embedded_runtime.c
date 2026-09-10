#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "blitzmax/embedded_runtime.h"
#include "blitzmax/embedded_platform.h"

#ifndef BMX_EMBEDDED_ARENA_SIZE
#define BMX_EMBEDDED_ARENA_SIZE (16u * 1024u)
#endif

#ifndef BMX_EMBEDDED_ARENA_IN_PSRAM
#define BMX_EMBEDDED_ARENA_IN_PSRAM 0
#endif

#ifndef BMX_EMBEDDED_ROOT_CAPACITY
#define BMX_EMBEDDED_ROOT_CAPACITY 64u
#endif

#define BMX_EMBEDDED_MEMORY_ALIGNMENT 16u

typedef union BMXEmbeddedHeapBlock BMXEmbeddedHeapBlock;

union BMXEmbeddedHeapBlock {
    max_align_t alignment;
    struct {
        BMXEmbeddedHeapBlock *previous;
        BMXEmbeddedHeapBlock *next;
        BMXEmbeddedHeapBlock *free_next;
        uint32_t capacity;
        uint32_t requested_size;
        uint32_t flags;
        uint32_t mark_epoch;
        uint32_t scan_epoch;
    } state;
};

_Static_assert(sizeof(BMXEmbeddedHeapBlock) % BMX_EMBEDDED_MEMORY_ALIGNMENT == 0,
    "embedded heap headers must preserve manual-memory alignment");

#define BMX_EMBEDDED_HEAP_BLOCK_FREE 0x0001u
#define BMX_EMBEDDED_HEAP_BLOCK_OBJECT 0x0002u
#define BMX_EMBEDDED_HEAP_BLOCK_ARRAY 0x0004u
#define BMX_EMBEDDED_HEAP_BLOCK_FINALIZER_PENDING 0x0008u
#define BMX_EMBEDDED_HEAP_BLOCK_FINALIZED 0x0010u
#define BMX_EMBEDDED_HEAP_BLOCK_STRING 0x0020u
#define BMX_EMBEDDED_HEAP_BLOCK_RAW 0x0040u

static _Alignas(BMX_EMBEDDED_MEMORY_ALIGNMENT) uint8_t
    BMX_EMBEDDED_ARENA_STORAGE(bmx_embedded_arena)[BMX_EMBEDDED_ARENA_SIZE];

static uint32_t bmx_embedded_arena_offset;
static uint32_t bmx_embedded_arena_high_water_mark;
static uint32_t bmx_embedded_arena_allocations;
static uint32_t bmx_embedded_arena_failures;
static uint32_t bmx_embedded_array_failures;
static uint32_t bmx_embedded_array_allocations;
static uint32_t bmx_embedded_array_bytes;
static uint32_t bmx_embedded_live_arrays;
static uint32_t bmx_embedded_live_array_bytes;
static uint32_t bmx_embedded_string_failures;
static uint32_t bmx_embedded_string_allocations;
static uint32_t bmx_embedded_string_bytes;
static uint32_t bmx_embedded_live_strings;
static uint32_t bmx_embedded_live_string_bytes;
static uint32_t bmx_embedded_enum_failures;
static uint32_t bmx_embedded_object_failures;
static uint32_t bmx_embedded_object_allocations;
static uint32_t bmx_embedded_object_bytes;
static uint32_t bmx_embedded_live_objects;
static uint32_t bmx_embedded_live_object_bytes;
static BMXEmbeddedHeapBlock *bmx_embedded_heap_first;
static BMXEmbeddedHeapBlock *bmx_embedded_heap_last;
static BMXEmbeddedHeapBlock *bmx_embedded_heap_free;
static void *bmx_embedded_object_roots[BMX_EMBEDDED_ROOT_CAPACITY];
static uint32_t bmx_embedded_object_root_total;
static uint32_t bmx_embedded_reachability_epoch;
static uint32_t bmx_embedded_reachable_objects;
static uint32_t bmx_embedded_unreachable_objects;
static uint32_t bmx_embedded_invalid_references;
static uint32_t bmx_embedded_reachable_arrays;
static uint32_t bmx_embedded_unreachable_arrays;
static uint32_t bmx_embedded_reachable_strings;
static uint32_t bmx_embedded_unreachable_strings;
static BMXEmbeddedRootFrame *bmx_embedded_root_frames;
static uint32_t bmx_embedded_root_frame_total;
static uint32_t bmx_embedded_root_slot_total;
static BMXEmbeddedExceptionFrame *bmx_embedded_exception_frames;
static BMXEmbeddedException bmx_embedded_exception_value;
static uint32_t bmx_embedded_exception_depth_total;
static uint32_t bmx_embedded_exception_throw_total;
static uint32_t bmx_embedded_exception_catch_total;
static uint32_t bmx_embedded_exception_max_depth_total;
static uint32_t bmx_embedded_exception_unhandled_total;
static uint32_t bmx_embedded_collection_total;
static uint32_t bmx_embedded_automatic_collection_total;
static uint32_t bmx_embedded_collection_active;
static uint32_t bmx_embedded_last_reclaimed_objects;
static uint32_t bmx_embedded_last_reclaimed_byte_total;
static uint32_t bmx_embedded_last_reclaimed_arrays;
static uint32_t bmx_embedded_last_reclaimed_array_byte_total;
static uint32_t bmx_embedded_last_reclaimed_strings;
static uint32_t bmx_embedded_last_reclaimed_string_byte_total;
static uint32_t bmx_embedded_finalizer_pending_objects;
static uint32_t bmx_embedded_finalizer_invocation_total;
static uint32_t bmx_embedded_last_finalized_objects;

const BMXEmbeddedString bmx_embedded_empty_string = {0, NULL};
static const uint16_t bmx_embedded_invalid_utf16_data[] = {
    'F','a','i','l','e','d',' ','t','o',' ','c','r','e','a','t','e',' ','U','T','F','3','2','.',
    ' ','I','n','v','a','l','i','d',' ','U','T','F','-','1','6',' ','s','u','r','r','o','g','a','t','e','.'
};
static const BMXEmbeddedString bmx_embedded_invalid_utf16_string = {
    (int32_t)(sizeof(bmx_embedded_invalid_utf16_data) / sizeof(bmx_embedded_invalid_utf16_data[0])),
    bmx_embedded_invalid_utf16_data
};
BMXEmbeddedArray bmx_embedded_empty_array = {0, 0, BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, 0, NULL, NULL};
BMXEmbeddedObject bmx_embedded_null_object = {NULL};

static uint32_t bmx_embedded_align_size(uint32_t bytes) {
    const uint32_t alignment = BMX_EMBEDDED_MEMORY_ALIGNMENT;
    return (bytes + alignment - 1u) & ~(alignment - 1u);
}

static void bmx_embedded_record_arena_failure(void) {
    __atomic_fetch_add(&bmx_embedded_arena_failures, 1u, __ATOMIC_RELAXED);
}

static void bmx_embedded_heap_free_remove(BMXEmbeddedHeapBlock *block) {
    BMXEmbeddedHeapBlock **link = &bmx_embedded_heap_free;
    while (*link && *link != block) link = &(*link)->state.free_next;
    if (*link) *link = block->state.free_next;
    block->state.free_next = NULL;
}

static void bmx_embedded_heap_free_add(BMXEmbeddedHeapBlock *block) {
    block->state.free_next = bmx_embedded_heap_free;
    bmx_embedded_heap_free = block;
}

static BMXEmbeddedHeapBlock *bmx_embedded_heap_release(BMXEmbeddedHeapBlock *block) {
    block->state.requested_size = 0;
    block->state.flags = BMX_EMBEDDED_HEAP_BLOCK_FREE;
    block->state.mark_epoch = 0;
    block->state.scan_epoch = 0;

    BMXEmbeddedHeapBlock *next = block->state.next;
    if (next && (next->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE)) {
        bmx_embedded_heap_free_remove(next);
        block->state.capacity += (uint32_t)sizeof(BMXEmbeddedHeapBlock) + next->state.capacity;
        block->state.next = next->state.next;
        if (block->state.next) block->state.next->state.previous = block;
        else bmx_embedded_heap_last = block;
    }

    BMXEmbeddedHeapBlock *previous = block->state.previous;
    if (previous && (previous->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE)) {
        bmx_embedded_heap_free_remove(previous);
        previous->state.capacity += (uint32_t)sizeof(BMXEmbeddedHeapBlock) + block->state.capacity;
        previous->state.next = block->state.next;
        if (previous->state.next) previous->state.next->state.previous = previous;
        else bmx_embedded_heap_last = previous;
        block = previous;
    }

    bmx_embedded_heap_free_add(block);
    return block;
}

static void *bmx_embedded_heap_allocate(uint32_t bytes, uint32_t flags) {
    if (!bytes) return NULL;
    const uint32_t aligned_bytes = bmx_embedded_align_size(bytes);
    if (aligned_bytes < bytes) return NULL;

    BMXEmbeddedHeapBlock *block = bmx_embedded_heap_free;
    while (block && block->state.capacity < aligned_bytes) block = block->state.free_next;
    if (block) {
        bmx_embedded_heap_free_remove(block);
        const uint32_t minimum_remainder = (uint32_t)sizeof(BMXEmbeddedHeapBlock) + (uint32_t)_Alignof(max_align_t);
        if (block->state.capacity >= aligned_bytes + minimum_remainder) {
            BMXEmbeddedHeapBlock *remainder = (BMXEmbeddedHeapBlock *)((uint8_t *)(block + 1) + aligned_bytes);
            remainder->state.previous = block;
            remainder->state.next = block->state.next;
            if (remainder->state.next) remainder->state.next->state.previous = remainder;
            else bmx_embedded_heap_last = remainder;
            remainder->state.free_next = NULL;
            remainder->state.capacity = block->state.capacity - aligned_bytes - (uint32_t)sizeof(BMXEmbeddedHeapBlock);
            remainder->state.requested_size = 0;
            remainder->state.flags = BMX_EMBEDDED_HEAP_BLOCK_FREE;
            remainder->state.mark_epoch = 0;
            remainder->state.scan_epoch = 0;
            block->state.next = remainder;
            block->state.capacity = aligned_bytes;
            bmx_embedded_heap_free_add(remainder);
        }
    } else {
        if (aligned_bytes > UINT32_MAX - sizeof(BMXEmbeddedHeapBlock)) return NULL;
        const uint32_t total_size = (uint32_t)sizeof(BMXEmbeddedHeapBlock) + aligned_bytes;
        if (total_size > BMX_EMBEDDED_ARENA_SIZE - bmx_embedded_arena_offset) return NULL;
        block = (BMXEmbeddedHeapBlock *)&bmx_embedded_arena[bmx_embedded_arena_offset];
        bmx_embedded_arena_offset += total_size;
        block->state.previous = bmx_embedded_heap_last;
        block->state.next = NULL;
        if (bmx_embedded_heap_last) bmx_embedded_heap_last->state.next = block;
        else bmx_embedded_heap_first = block;
        bmx_embedded_heap_last = block;
        block->state.capacity = aligned_bytes;
    }
    block->state.free_next = NULL;
    block->state.requested_size = bytes;
    block->state.flags = flags;
    block->state.mark_epoch = 0;
    block->state.scan_epoch = 0;
    bmx_embedded_arena_allocations += 1u;
    if (bmx_embedded_arena_offset > bmx_embedded_arena_high_water_mark) bmx_embedded_arena_high_water_mark = bmx_embedded_arena_offset;
    return block + 1;
}

static void *bmx_embedded_heap_allocate_with_collection(uint32_t bytes, uint32_t flags) {
    void *result = bmx_embedded_heap_allocate(bytes, flags);
    if (!result && !bmx_embedded_collection_active) {
        bmx_embedded_automatic_collection_total += 1u;
        bmx_embedded_collect_objects();
        if (bmx_embedded_last_finalized_objects) {
            bmx_embedded_automatic_collection_total += 1u;
            bmx_embedded_collect_objects();
        }
        result = bmx_embedded_heap_allocate(bytes, flags);
    }
    return result;
}

void *bmx_embedded_arena_allocate(uint32_t bytes) {
    if (!bytes || !BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_arena_failure();
        return NULL;
    }
    void *result = bmx_embedded_heap_allocate(bytes, BMX_EMBEDDED_HEAP_BLOCK_RAW);
    if (!result) bmx_embedded_record_arena_failure();
    return result;
}

uint32_t bmx_embedded_arena_capacity(void) {
    return BMX_EMBEDDED_ARENA_SIZE;
}

uint32_t bmx_embedded_arena_used(void) {
    return bmx_embedded_arena_offset;
}

uint32_t bmx_embedded_arena_remaining(void) {
    return BMX_EMBEDDED_ARENA_SIZE - bmx_embedded_arena_offset;
}

uint32_t bmx_embedded_arena_high_water(void) {
    return bmx_embedded_arena_high_water_mark;
}

uint32_t bmx_embedded_arena_allocation_count(void) {
    return bmx_embedded_arena_allocations;
}

uint32_t bmx_embedded_arena_failure_count(void) {
    return __atomic_load_n(&bmx_embedded_arena_failures, __ATOMIC_RELAXED);
}

static void bmx_embedded_record_array_failure(void) {
    __atomic_fetch_add(&bmx_embedded_array_failures, 1u, __ATOMIC_RELAXED);
}

BMXEmbeddedArray *bmx_embedded_array_new_1d(int32_t length, uint32_t element_size, uint16_t element_kind, BMXEmbeddedArrayInitializer initializer, const BMXEmbeddedValueDescriptor *element_descriptor) {
    if (length < 0 || !element_size || element_kind > BMX_EMBEDDED_ARRAY_ELEMENT_OBJECT ||
        (initializer && element_kind != BMX_EMBEDDED_ARRAY_ELEMENT_VALUE) ||
        (element_descriptor && element_kind != BMX_EMBEDDED_ARRAY_ELEMENT_VALUE) ||
        (element_descriptor && element_descriptor->size != element_size) ||
        (element_kind != BMX_EMBEDDED_ARRAY_ELEMENT_VALUE && element_size != sizeof(void *))) {
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_array;
    }
    if (!length) return &bmx_embedded_empty_array;

    const uint32_t header_size = bmx_embedded_align_size((uint32_t)sizeof(BMXEmbeddedArray));
    const uint32_t count = (uint32_t)length;
    if (count > (UINT32_MAX - header_size) / element_size) {
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_array;
    }

    const uint32_t total_size = header_size + count * element_size;
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_arena_failure();
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_array;
    }
    BMXEmbeddedArray *array = (BMXEmbeddedArray *)bmx_embedded_heap_allocate_with_collection(total_size, BMX_EMBEDDED_HEAP_BLOCK_ARRAY);
    if (!array) {
        bmx_embedded_record_arena_failure();
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_array;
    }
    array->length = length;
    array->element_size = element_size;
    array->element_kind = element_kind;
    array->reserved = 0;
    array->initializer = initializer;
    array->element_descriptor = element_descriptor;
    void *elements = (uint8_t *)array + header_size;
    if (element_kind == BMX_EMBEDDED_ARRAY_ELEMENT_OBJECT) {
        void **references = (void **)elements;
        for (uint32_t index = 0; index < count; ++index) references[index] = &bmx_embedded_null_object;
    } else if (element_kind == BMX_EMBEDDED_ARRAY_ELEMENT_STRING) {
        const BMXEmbeddedString **references = (const BMXEmbeddedString **)elements;
        for (uint32_t index = 0; index < count; ++index) references[index] = &bmx_embedded_empty_string;
    } else {
        memset(elements, 0, count * element_size);
        if (initializer) {
            BMXEmbeddedArray *array_root = array;
            BMXEmbeddedRootSlot slot = {(void *)&array_root, BMX_EMBEDDED_ROOT_ARRAY, NULL};
            BMXEmbeddedRootFrame frame;
            bmx_embedded_root_frame_enter(&frame, &slot, 1);
            for (uint32_t index = 0; index < count; ++index) initializer((uint8_t *)elements + index * element_size);
            bmx_embedded_root_frame_leave(&frame);
        }
    }
    bmx_embedded_array_allocations += 1u;
    bmx_embedded_array_bytes += total_size;
    bmx_embedded_live_arrays += 1u;
    bmx_embedded_live_array_bytes += total_size;
    return array;
}

BMXEmbeddedArray *bmx_embedded_array_from_data(int32_t length, uint32_t element_size,
    uint16_t element_kind, BMXEmbeddedArrayInitializer initializer,
    const BMXEmbeddedValueDescriptor *element_descriptor, const void *data) {
    if (length > 0 && !data) {
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_array;
    }
    BMXEmbeddedArray *array = bmx_embedded_array_new_1d(length, element_size, element_kind,
        initializer, element_descriptor);
    if (array != &bmx_embedded_empty_array && length > 0) {
        memcpy(bmx_embedded_array_data(array), data, (size_t)length * element_size);
    }
    return array;
}

BMXEmbeddedArray *bmx_embedded_array_concat(BMXEmbeddedArray *left, BMXEmbeddedArray *right) {
    if (!left || !right) {
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_array;
    }
    if (!left->length && !right->length) return &bmx_embedded_empty_array;

    BMXEmbeddedArray *shape = left->length ? left : right;
    if ((left->length && (left->element_size != shape->element_size ||
            left->element_kind != shape->element_kind ||
            left->element_descriptor != shape->element_descriptor)) ||
        (right->length && (right->element_size != shape->element_size ||
            right->element_kind != shape->element_kind ||
            right->element_descriptor != shape->element_descriptor)) ||
        left->length > INT32_MAX - right->length) {
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_array;
    }

    BMXEmbeddedArray *left_root = left;
    BMXEmbeddedArray *right_root = right;
    BMXEmbeddedRootSlot slots[2] = {
        {(void *)&left_root, BMX_EMBEDDED_ROOT_ARRAY, NULL},
        {(void *)&right_root, BMX_EMBEDDED_ROOT_ARRAY, NULL}
    };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, 2);
    BMXEmbeddedArray *result = bmx_embedded_array_new_1d(left->length + right->length,
        shape->element_size, shape->element_kind, NULL, shape->element_descriptor);
    if (result != &bmx_embedded_empty_array) {
        result->initializer = shape->initializer;
        uint8_t *destination = (uint8_t *)bmx_embedded_array_data(result);
        if (left->length) memcpy(destination, bmx_embedded_array_data(left),
            (size_t)left->length * shape->element_size);
        if (right->length) memcpy(destination + (size_t)left->length * shape->element_size,
            bmx_embedded_array_data(right), (size_t)right->length * shape->element_size);
    }
    bmx_embedded_root_frame_leave(&frame);
    return result;
}

BMXEmbeddedArray *bmx_embedded_array_slice(BMXEmbeddedArray *array, int32_t begin, int32_t end,
    uint32_t element_size, uint16_t element_kind, BMXEmbeddedArrayInitializer initializer,
    const BMXEmbeddedValueDescriptor *element_descriptor) {
    if (!array || end <= begin) return &bmx_embedded_empty_array;
    if (array->length && (array->element_size != element_size || array->element_kind != element_kind ||
            array->initializer != initializer || array->element_descriptor != element_descriptor)) {
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_array;
    }
    int64_t length64 = (int64_t)end - begin;
    if (length64 > INT32_MAX) {
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_array;
    }
    BMXEmbeddedArray *array_root = array;
    BMXEmbeddedRootSlot slot = {(void *)&array_root, BMX_EMBEDDED_ROOT_ARRAY, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1);
    BMXEmbeddedArray *result = bmx_embedded_array_new_1d((int32_t)length64, element_size,
        element_kind, initializer, element_descriptor);
    if (result != &bmx_embedded_empty_array) {
        int64_t copy_begin = begin;
        int64_t copy_end = end;
        if (copy_begin < 0) copy_begin = 0;
        if (copy_end > array->length) copy_end = array->length;
        if (copy_end > copy_begin) {
            uint32_t copied = (uint32_t)(copy_end - copy_begin);
            uint32_t destination = (uint32_t)(copy_begin - begin);
            memcpy((uint8_t *)bmx_embedded_array_data(result) + (size_t)destination * element_size,
                (uint8_t *)bmx_embedded_array_data(array) + (size_t)copy_begin * element_size,
                (size_t)copied * element_size);
        }
    }
    bmx_embedded_root_frame_leave(&frame);
    return result;
}

void bbArrayCopy(BBARRAY src, int src_pos, BBARRAY dst, int dst_pos, int length) {
    if (!src || !dst || src_pos < 0 || dst_pos < 0 || length < 0 ||
        src_pos > src->length - length || dst_pos > dst->length - length ||
        src->element_size != dst->element_size || src->element_kind != dst->element_kind ||
        src->element_descriptor != dst->element_descriptor) {
        bmx_embedded_record_array_failure();
        BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core ArrayCopy range or element type mismatch");
    }
    if (!length) return;
    memmove((uint8_t *)bmx_embedded_array_data(dst) + (uint32_t)dst_pos * dst->element_size,
        (uint8_t *)bmx_embedded_array_data(src) + (uint32_t)src_pos * src->element_size,
        (size_t)length * src->element_size);
}

void *bmx_embedded_array_element(BMXEmbeddedArray *array, int32_t index, uint32_t element_size) {
    if (!array || index < 0 || index >= array->length || element_size != array->element_size) {
        bmx_embedded_record_array_failure();
        BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core Array index or element type mismatch");
    }
    const uint32_t header_size = bmx_embedded_align_size((uint32_t)sizeof(BMXEmbeddedArray));
    return (uint8_t *)array + header_size + (uint32_t)index * element_size;
}

void *bmx_embedded_array_data(BMXEmbeddedArray *array) {
    if (!array) return NULL;
    return (uint8_t *)array + bmx_embedded_align_size((uint32_t)sizeof(BMXEmbeddedArray));
}

static BMXEmbeddedHeapBlock *bmx_embedded_raw_block(void *memory) {
    if (!memory) return NULL;
    for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first; block; block = block->state.next) {
        if (!(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE) &&
            (block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_RAW) &&
            (void *)(block + 1) == memory) return block;
    }
    return NULL;
}

void *bbMemAlloc(size_t size) {
    if (!size || size > UINT32_MAX || !BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_arena_failure();
        return NULL;
    }
    void *result = bmx_embedded_heap_allocate_with_collection((uint32_t)size, BMX_EMBEDDED_HEAP_BLOCK_RAW);
    if (!result) bmx_embedded_record_arena_failure();
    return result;
}

void bbMemFree(void *memory) {
    if (!memory) return;
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_arena_failure();
        return;
    }
    BMXEmbeddedHeapBlock *block = bmx_embedded_raw_block(memory);
    if (!block) BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core MemFree received an invalid pointer");
    bmx_embedded_heap_release(block);
}

void *bbMemExtend(void *memory, size_t size, size_t new_size) {
    if (!memory) return bbMemAlloc(new_size);
    if (!new_size) {
        bbMemFree(memory);
        return NULL;
    }
    BMXEmbeddedHeapBlock *block = bmx_embedded_raw_block(memory);
    if (!block) BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core MemExtend received an invalid pointer");
    void *extended = bbMemAlloc(new_size);
    if (!extended) return NULL;
    size_t copied = size;
    if (copied > block->state.requested_size) copied = block->state.requested_size;
    if (copied > new_size) copied = new_size;
    memcpy(extended, memory, copied);
    bbMemFree(memory);
    return extended;
}

void *bbMemAllocCollectable(size_t size) {
    (void)size;
    BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core collectable raw memory is not supported");
    return NULL;
}

void bbMemFreeCollectable(void *memory) {
    (void)memory;
    BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core collectable raw memory is not supported");
}

typedef struct BMXEmbeddedIncbinEntry {
    struct BMXEmbeddedIncbinEntry *next;
    const BMXEmbeddedString *path;
    const void *data;
    int32_t size;
} BMXEmbeddedIncbinEntry;

static BMXEmbeddedIncbinEntry *bmx_embedded_incbin_entries;

int32_t bbIncbinAdd(const BMXEmbeddedString *path, const void *data, int32_t size) {
    if (!path || !data || size < 0) return 0;
    for (BMXEmbeddedIncbinEntry *entry = bmx_embedded_incbin_entries; entry; entry = entry->next) {
        if (bmx_embedded_string_compare(entry->path, path) == 0) return 0;
    }
    BMXEmbeddedIncbinEntry *entry = (BMXEmbeddedIncbinEntry *)bbMemAlloc(sizeof(BMXEmbeddedIncbinEntry));
    if (!entry) return 0;
    entry->path = path;
    entry->data = data;
    entry->size = size;
    entry->next = bmx_embedded_incbin_entries;
    bmx_embedded_incbin_entries = entry;
    return 0;
}

void *bbIncbinPtr(const BMXEmbeddedString *path) {
    if (!path) return NULL;
    for (BMXEmbeddedIncbinEntry *entry = bmx_embedded_incbin_entries; entry; entry = entry->next) {
        if (bmx_embedded_string_compare(entry->path, path) == 0) return (void *)entry->data;
    }
    return NULL;
}

int32_t bbIncbinLen(const BMXEmbeddedString *path) {
    if (!path) return 0;
    for (BMXEmbeddedIncbinEntry *entry = bmx_embedded_incbin_entries; entry; entry = entry->next) {
        if (bmx_embedded_string_compare(entry->path, path) == 0) return entry->size;
    }
    return 0;
}

void *bbMemExtendCollectable(void *memory, size_t size, size_t new_size) {
    (void)memory;
    (void)size;
    (void)new_size;
    BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core collectable raw memory is not supported");
    return NULL;
}

void bbMemClear(void *memory, size_t size) {
    memset(memory, 0, size);
}

void bbMemCopy(void *destination, const void *source, size_t size) {
    memcpy(destination, source, size);
}

void bbMemMove(void *destination, const void *source, size_t size) {
    memmove(destination, source, size);
}

uint32_t bmx_embedded_array_failure_count(void) {
    return __atomic_load_n(&bmx_embedded_array_failures, __ATOMIC_RELAXED);
}

uint32_t bmx_embedded_array_allocation_count(void) {
    return bmx_embedded_array_allocations;
}

uint32_t bmx_embedded_array_allocated_bytes(void) {
    return bmx_embedded_array_bytes;
}

uint32_t bmx_embedded_array_live_count(void) {
    return bmx_embedded_live_arrays;
}

uint32_t bmx_embedded_array_live_bytes(void) {
    return bmx_embedded_live_array_bytes;
}

static void bmx_embedded_record_object_failure(void) {
    __atomic_fetch_add(&bmx_embedded_object_failures, 1u, __ATOMIC_RELAXED);
}

static int bmx_embedded_value_field_valid(const BMXEmbeddedValueField *field, uint32_t container_size) {
    if (!field || !field->count || field->offset >= container_size) return 0;
    if (field->kind < BMX_EMBEDDED_VALUE_OBJECT || field->kind > BMX_EMBEDDED_VALUE_STRUCT) return 0;
    if (field->kind == BMX_EMBEDDED_VALUE_STRUCT && !field->descriptor) return 0;
    if (field->kind != BMX_EMBEDDED_VALUE_STRUCT && field->descriptor) return 0;
    uint32_t referenced_size = field->kind == BMX_EMBEDDED_VALUE_STRUCT ?
        field->descriptor->size : (uint32_t)sizeof(void *);
    if (!referenced_size || referenced_size > container_size) return 0;
    if (field->count == 1u) return field->offset <= container_size - referenced_size;
    if (!field->stride || field->stride > UINT32_MAX / (field->count - 1u)) return 0;
    uint32_t span = (field->count - 1u) * field->stride;
    return field->offset <= UINT32_MAX - span && field->offset + span <= container_size - referenced_size;
}

static int bmx_embedded_value_descriptor_valid(const BMXEmbeddedValueDescriptor *descriptor) {
    if (!descriptor || !descriptor->name || !descriptor->size ||
        (descriptor->field_count && !descriptor->fields)) return 0;
    for (uint32_t index = 0; index < descriptor->field_count; ++index) {
        if (!bmx_embedded_value_field_valid(&descriptor->fields[index], descriptor->size)) return 0;
    }
    return 1;
}

static int bmx_embedded_type_descriptor_valid(const BMXEmbeddedTypeDescriptor *type) {
    if (!type || !type->name || type->instance_size < sizeof(BMXEmbeddedObject)) return 0;
    if (type->method_count && !type->methods) return 0;
    if (type->interface_count && !type->interfaces) return 0;
    if (type->reference_count && !type->reference_offsets) return 0;
    if (type->array_count && !type->array_offsets) return 0;
    if (type->string_count && !type->string_offsets) return 0;
    if (type->value_field_count && !type->value_fields) return 0;
    if (type->flags & ~(BMX_EMBEDDED_TYPE_FLAG_CUSTOM_TRACE | BMX_EMBEDDED_TYPE_FLAG_HAS_FINALIZER)) return 0;
    if ((type->flags & BMX_EMBEDDED_TYPE_FLAG_CUSTOM_TRACE) && !type->trace) return 0;
    if ((type->flags & BMX_EMBEDDED_TYPE_FLAG_HAS_FINALIZER) && !type->finalizer) return 0;
    for (uint32_t index = 0; index < type->reference_count; ++index) {
        uint32_t offset = type->reference_offsets[index];
        if (offset < sizeof(BMXEmbeddedObject) || offset > type->instance_size - sizeof(void *) || offset % _Alignof(void *)) return 0;
    }
    for (uint32_t index = 0; index < type->array_count; ++index) {
        uint32_t offset = type->array_offsets[index];
        if (offset < sizeof(BMXEmbeddedObject) || offset > type->instance_size - sizeof(void *) || offset % _Alignof(void *)) return 0;
    }
    for (uint32_t index = 0; index < type->string_count; ++index) {
        uint32_t offset = type->string_offsets[index];
        if (offset < sizeof(BMXEmbeddedObject) || offset > type->instance_size - sizeof(void *) || offset % _Alignof(void *)) return 0;
    }
    for (uint32_t index = 0; index < type->value_field_count; ++index) {
        if (!bmx_embedded_value_field_valid(&type->value_fields[index], type->instance_size)) return 0;
    }
    return 1;
}

static BMXEmbeddedHeapBlock *bmx_embedded_object_allocation(void *object) {
    for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first; block; block = block->state.next) {
        if (!(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE) && (block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_OBJECT) && (void *)(block + 1) == object) return block;
    }
    return NULL;
}

static BMXEmbeddedHeapBlock *bmx_embedded_array_allocation(void *array) {
    for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first; block; block = block->state.next) {
        if (!(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE) && (block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_ARRAY) && (void *)(block + 1) == array) return block;
    }
    return NULL;
}

static BMXEmbeddedHeapBlock *bmx_embedded_string_allocation(const void *string) {
    for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first; block; block = block->state.next) {
        if (!(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE) && (block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_STRING) && (const void *)(block + 1) == string) return block;
    }
    return NULL;
}

int32_t bmx_embedded_object_is_string(BMXEmbeddedObject *value) {
    if (!value || value == &bmx_embedded_null_object) return 0;
    if ((const void *)value == (const void *)&bmx_embedded_empty_string ||
        bmx_embedded_string_allocation(value)) return 1;
    if (bmx_embedded_object_allocation(value) || bmx_embedded_array_allocation(value)) return 0;
    const BMXEmbeddedString *text = (const BMXEmbeddedString *)value;
    return text->length >= 0 && (text->length == 0 || text->buf);
}

const BMXEmbeddedString *bmx_embedded_stream_url_string(BMXEmbeddedObject *value) {
    if (!bmx_embedded_object_is_string(value)) return &bmx_embedded_empty_string;
    return (const BMXEmbeddedString *)value;
}

void *bmx_embedded_object_allocate(const BMXEmbeddedTypeDescriptor *type) {
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_arena_failure();
        bmx_embedded_record_object_failure();
        return &bmx_embedded_null_object;
    }
    if (!bmx_embedded_type_descriptor_valid(type)) {
        bmx_embedded_record_object_failure();
        return &bmx_embedded_null_object;
    }
    BMXEmbeddedObject *object = (BMXEmbeddedObject *)bmx_embedded_heap_allocate_with_collection(type->instance_size, BMX_EMBEDDED_HEAP_BLOCK_OBJECT);
    if (!object) {
        bmx_embedded_record_arena_failure();
        bmx_embedded_record_object_failure();
        return &bmx_embedded_null_object;
    }
    memset(object, 0, type->instance_size);
    object->type = type;
    bmx_embedded_object_allocations += 1u;
    bmx_embedded_object_bytes += type->instance_size;
    bmx_embedded_live_objects += 1u;
    bmx_embedded_live_object_bytes += type->instance_size;
    return object;
}

static const uint32_t bmx_embedded_closure_reference_offsets[] = {
    (uint32_t)offsetof(BMXEmbeddedClosure, environment)
};

static const BMXEmbeddedTypeDescriptor bmx_embedded_closure_type = {
    .name = "Closure",
    .abi_name = "",
    .instance_size = (uint32_t)sizeof(BMXEmbeddedClosure),
    .super = NULL,
    .methods = NULL,
    .method_count = 0,
    .interfaces = NULL,
    .interface_count = 0,
    .reference_offsets = bmx_embedded_closure_reference_offsets,
    .reference_count = 1,
    .array_offsets = NULL,
    .array_count = 0,
    .string_offsets = NULL,
    .string_count = 0,
    .value_fields = NULL,
    .value_field_count = 0,
    .flags = 0,
    .trace = NULL,
    .finalizer = NULL,
    .compare = NULL,
    .hash_code = NULL,
    .equals = NULL
};

BMXEmbeddedClosure *bmx_embedded_closure_allocate(BMXEmbeddedMethod invoke, BMXEmbeddedObject *environment) {
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_arena_failure();
        bmx_embedded_record_object_failure();
        return (BMXEmbeddedClosure *)&bmx_embedded_null_object;
    }
    if (!invoke) {
        bmx_embedded_record_object_failure();
        return (BMXEmbeddedClosure *)&bmx_embedded_null_object;
    }
    BMXEmbeddedObject *environment_root = environment ? environment : &bmx_embedded_null_object;
    BMXEmbeddedRootSlot slot = {(void *)&environment_root, BMX_EMBEDDED_ROOT_OBJECT, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1);
    BMXEmbeddedClosure *closure = (BMXEmbeddedClosure *)bmx_embedded_object_allocate(&bmx_embedded_closure_type);
    if ((void *)closure != (void *)&bmx_embedded_null_object) {
        closure->invoke = invoke;
        closure->environment = environment_root;
    }
    bmx_embedded_root_frame_leave(&frame);
    return closure;
}

BMXEmbeddedClosure *bmx_embedded_closure_assert(void *closure) {
    BMXEmbeddedClosure *value = (BMXEmbeddedClosure *)bmx_embedded_object_assert(closure);
    if (value->object.type != &bmx_embedded_closure_type || !value->invoke) {
        bmx_embedded_record_object_failure();
        BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core invalid Closure invocation");
    }
    return value;
}

void *bmx_embedded_object_assert(void *object) {
    if (!object || object == &bmx_embedded_null_object || !bmx_embedded_object_allocation(object) ||
        !bmx_embedded_type_descriptor_valid(((BMXEmbeddedObject *)object)->type)) {
        bmx_embedded_record_object_failure();
        BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core Null object access");
    }
    return object;
}

void *bmx_embedded_object_null_failure(void) {
    bmx_embedded_record_object_failure();
    BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core Null object access");
    return &bmx_embedded_null_object;
}

int32_t bmx_embedded_object_compare(void *object, void *other) {
    BMXEmbeddedObject *left = (BMXEmbeddedObject *)bmx_embedded_object_assert(object);
    if (left->type->compare) return left->type->compare(left, other);
    uintptr_t left_value = (uintptr_t)object;
    uintptr_t right_value = (uintptr_t)other;
    return (left_value > right_value) - (left_value < right_value);
}

static uint32_t bmx_embedded_mix32(uint32_t value) {
    value ^= value >> 16;
    value *= 0x85ebca6bu;
    value ^= value >> 13;
    value *= 0xc2b2ae35u;
    value ^= value >> 16;
    return value;
}

uint32_t bmx_embedded_object_hash_code(void *object) {
    BMXEmbeddedObject *value = (BMXEmbeddedObject *)bmx_embedded_object_assert(object);
    if (value->type->hash_code) return value->type->hash_code(value);
    return bmx_embedded_mix32((uint32_t)(uintptr_t)object);
}

int32_t bmx_embedded_object_equals(void *object, void *other) {
    BMXEmbeddedObject *left = (BMXEmbeddedObject *)bmx_embedded_object_assert(object);
    if (left->type->equals) return left->type->equals(left, other);
    return object == other;
}

void *bmx_embedded_object_cast(void *object, const BMXEmbeddedTypeDescriptor *target) {
    if (!object || object == &bmx_embedded_null_object) return &bmx_embedded_null_object;
    BMXEmbeddedHeapBlock *block = bmx_embedded_object_allocation(object);
    if (!block || !target || !bmx_embedded_type_descriptor_valid(((BMXEmbeddedObject *)object)->type)) {
        bmx_embedded_record_object_failure();
        return &bmx_embedded_null_object;
    }
    for (const BMXEmbeddedTypeDescriptor *type = ((BMXEmbeddedObject *)object)->type; type; type = type->super) {
        if (type == target) return object;
        if (type->abi_name && target->abi_name && type->abi_name[0] && target->abi_name[0] &&
                strcmp(type->abi_name, target->abi_name) == 0) return object;
    }
    return &bmx_embedded_null_object;
}

const BMXEmbeddedMethod *bmx_embedded_type_methods(void *object, const BMXEmbeddedTypeDescriptor *target, uint32_t method_count) {
    BMXEmbeddedObject *value = (BMXEmbeddedObject *)bmx_embedded_object_assert(object);
    const BMXEmbeddedTypeDescriptor *dynamic_type = value->type;
    int matched = target == NULL;
    for (const BMXEmbeddedTypeDescriptor *type = dynamic_type; target && type; type = type->super) {
        if (type == target || (type->abi_name && target->abi_name && type->abi_name[0] && target->abi_name[0] &&
                strcmp(type->abi_name, target->abi_name) == 0)) {
            matched = 1;
            break;
        }
    }
    if (!matched || dynamic_type->method_count < method_count || (method_count && !dynamic_type->methods)) {
        BMX_EMBEDDED_PLATFORM_PANIC("invalid BlitzMax core Type dispatch");
    }
    return dynamic_type->methods;
}

static const BMXEmbeddedInterfaceEntry *bmx_embedded_find_interface(void *object, const BMXEmbeddedInterfaceDescriptor *target) {
    if (!object || object == &bmx_embedded_null_object || !target) return NULL;
    BMXEmbeddedHeapBlock *block = bmx_embedded_object_allocation(object);
    if (!block || !bmx_embedded_type_descriptor_valid(((BMXEmbeddedObject *)object)->type)) return NULL;
    for (const BMXEmbeddedTypeDescriptor *type = ((BMXEmbeddedObject *)object)->type; type; type = type->super) {
        for (uint32_t index = 0; index < type->interface_count; ++index) {
            const BMXEmbeddedInterfaceDescriptor *candidate = type->interfaces[index].interface_type;
            if (candidate == target) return &type->interfaces[index];
            if (candidate && candidate->abi_name && target->abi_name &&
                    candidate->abi_name[0] && target->abi_name[0] &&
                    strcmp(candidate->abi_name, target->abi_name) == 0) {
                return &type->interfaces[index];
            }
        }
    }
    return NULL;
}

void *bmx_embedded_interface_cast(void *object, const BMXEmbeddedInterfaceDescriptor *target) {
    return bmx_embedded_find_interface(object, target) ? object : &bmx_embedded_null_object;
}

const BMXEmbeddedMethod *bmx_embedded_interface_methods(void *object, const BMXEmbeddedInterfaceDescriptor *target, uint32_t method_count) {
    BMXEmbeddedObject *value = (BMXEmbeddedObject *)bmx_embedded_object_assert(object);
    const BMXEmbeddedInterfaceEntry *entry = bmx_embedded_find_interface(value, target);
    if (!entry || entry->method_count < method_count || (method_count && !entry->methods)) {
        bmx_embedded_record_object_failure();
        BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core interface dispatch failure");
    }
    return entry->methods;
}

uint32_t bmx_embedded_object_failure_count(void) {
    return __atomic_load_n(&bmx_embedded_object_failures, __ATOMIC_RELAXED);
}

uint32_t bmx_embedded_object_allocation_count(void) {
    return bmx_embedded_object_allocations;
}

uint32_t bmx_embedded_object_allocated_bytes(void) {
    return bmx_embedded_object_bytes;
}

uint32_t bmx_embedded_object_live_count(void) {
    return bmx_embedded_live_objects;
}

uint32_t bmx_embedded_object_live_bytes(void) {
    return bmx_embedded_live_object_bytes;
}

uint32_t bmx_embedded_object_root_retain(BMXEmbeddedObject *object) {
    if (!object || object == &bmx_embedded_null_object) return 0;
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID() || !bmx_embedded_object_allocation(object)) {
        bmx_embedded_record_object_failure();
        return 0;
    }
    for (uint32_t index = 0; index < BMX_EMBEDDED_ROOT_CAPACITY; ++index) {
        if (!bmx_embedded_object_roots[index]) {
            bmx_embedded_object_roots[index] = object;
            bmx_embedded_object_root_total += 1u;
            return index + 1u;
        }
    }
    bmx_embedded_record_object_failure();
    return 0;
}

void bmx_embedded_object_root_release(uint32_t token) {
    if (!token) return;
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID() || token > BMX_EMBEDDED_ROOT_CAPACITY || !bmx_embedded_object_roots[token - 1u]) {
        bmx_embedded_record_object_failure();
        return;
    }
    bmx_embedded_object_roots[token - 1u] = NULL;
    bmx_embedded_object_root_total -= 1u;
}

uint32_t bmx_embedded_object_root_count(void) {
    return bmx_embedded_object_root_total;
}

void bmx_embedded_root_frame_enter(BMXEmbeddedRootFrame *frame, BMXEmbeddedRootSlot *slots, uint16_t slot_count) {
    if (!frame || (slot_count && !slots) || !BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_object_failure();
        return;
    }
    frame->previous = bmx_embedded_root_frames;
    frame->slots = slots;
    frame->slot_count = slot_count;
    bmx_embedded_root_frames = frame;
    bmx_embedded_root_frame_total += 1u;
    bmx_embedded_root_slot_total += slot_count;
}

void bmx_embedded_root_frame_leave(BMXEmbeddedRootFrame *frame) {
    if (!frame || frame != bmx_embedded_root_frames || !BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_object_failure();
        return;
    }
    bmx_embedded_root_frames = frame->previous;
    bmx_embedded_root_frame_total -= 1u;
    bmx_embedded_root_slot_total -= frame->slot_count;
    frame->previous = NULL;
    frame->slots = NULL;
    frame->slot_count = 0;
}

uint32_t bmx_embedded_root_frame_count(void) {
    return bmx_embedded_root_frame_total;
}

uint32_t bmx_embedded_root_slot_count(void) {
    return bmx_embedded_root_slot_total;
}

void bmx_embedded_exception_enter(BMXEmbeddedExceptionFrame *frame) {
    if (!frame || !BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_object_failure();
        BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core exception handlers require core 0 thread context");
    }
    frame->previous = bmx_embedded_exception_frames;
    frame->root_snapshot = bmx_embedded_root_frames;
    frame->root_frame_count = bmx_embedded_root_frame_total;
    frame->root_slot_count = bmx_embedded_root_slot_total;
    bmx_embedded_exception_frames = frame;
    bmx_embedded_exception_depth_total += 1u;
    if (bmx_embedded_exception_depth_total > bmx_embedded_exception_max_depth_total) {
        bmx_embedded_exception_max_depth_total = bmx_embedded_exception_depth_total;
    }
}

void bmx_embedded_exception_leave(void) {
    BMXEmbeddedExceptionFrame *frame = bmx_embedded_exception_frames;
    if (!frame || !BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_object_failure();
        BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core exception frame imbalance");
    }
    bmx_embedded_exception_frames = frame->previous;
    bmx_embedded_exception_depth_total -= 1u;
    frame->previous = NULL;
}

BMXEmbeddedException bmx_embedded_exception_object(BMXEmbeddedObject *value) {
    BMXEmbeddedException exception = {value, BMX_EMBEDDED_EXCEPTION_OBJECT, 0};
    return exception;
}

BMXEmbeddedException bmx_embedded_exception_array(BMXEmbeddedArray *value) {
    BMXEmbeddedException exception = {value, BMX_EMBEDDED_EXCEPTION_ARRAY, 0};
    return exception;
}

BMXEmbeddedException bmx_embedded_exception_string(const BMXEmbeddedString *value) {
    BMXEmbeddedException exception = {(void *)value, BMX_EMBEDDED_EXCEPTION_STRING, 0};
    return exception;
}

BMXEmbeddedException bmx_embedded_exception_catch(void) {
    BMXEmbeddedException exception = bmx_embedded_exception_value;
    bmx_embedded_exception_value.value = NULL;
    bmx_embedded_exception_value.kind = BMX_EMBEDDED_EXCEPTION_NONE;
    bmx_embedded_exception_catch_total += 1u;
    return exception;
}

void bmx_embedded_exception_throw(BMXEmbeddedException exception) {
    bmx_embedded_exception_throw_total += 1u;
    int valid = exception.value && BMX_EMBEDDED_PLATFORM_CONTEXT_VALID();
    if (valid && exception.kind == BMX_EMBEDDED_EXCEPTION_OBJECT) {
        valid = exception.value != &bmx_embedded_null_object && bmx_embedded_object_allocation(exception.value) != NULL;
    } else if (valid && exception.kind == BMX_EMBEDDED_EXCEPTION_ARRAY) {
        valid = exception.value == &bmx_embedded_empty_array || bmx_embedded_array_allocation(exception.value) != NULL;
    } else if (valid && exception.kind == BMX_EMBEDDED_EXCEPTION_STRING) {
        /* Compiler literals live in flash and are trusted, while dynamic
           Strings are validated when the collector marks the rooted carrier. */
    } else {
        valid = 0;
    }
    if (!valid) {
        bmx_embedded_record_object_failure();
        BMX_EMBEDDED_PLATFORM_PANIC("BlitzMax core invalid exception value or context");
    }
    BMXEmbeddedExceptionFrame *frame = bmx_embedded_exception_frames;
    if (!frame) {
        bmx_embedded_exception_unhandled_total += 1u;
        BMX_EMBEDDED_PLATFORM_PANIC("Unhandled BlitzMax core exception");
    }
    bmx_embedded_exception_value = exception;
    bmx_embedded_root_frames = frame->root_snapshot;
    bmx_embedded_root_frame_total = frame->root_frame_count;
    bmx_embedded_root_slot_total = frame->root_slot_count;
    bmx_embedded_exception_frames = frame->previous;
    bmx_embedded_exception_depth_total -= 1u;
    longjmp(frame->buffer, 1);
}

uint32_t bmx_embedded_exception_depth(void) { return bmx_embedded_exception_depth_total; }
uint32_t bmx_embedded_exception_throw_count(void) { return bmx_embedded_exception_throw_total; }
uint32_t bmx_embedded_exception_catch_count(void) { return bmx_embedded_exception_catch_total; }
uint32_t bmx_embedded_exception_max_depth(void) { return bmx_embedded_exception_max_depth_total; }
uint32_t bmx_embedded_exception_unhandled_count(void) { return bmx_embedded_exception_unhandled_total; }

typedef struct BMXEmbeddedReachabilityContext {
    uint32_t epoch;
    uint32_t reachable;
    uint32_t reachable_arrays;
    uint32_t reachable_strings;
    uint32_t invalid;
} BMXEmbeddedReachabilityContext;

static void bmx_embedded_mark_reference(void *reference, void *context_value) {
    if (!reference || reference == &bmx_embedded_null_object) return;
    BMXEmbeddedReachabilityContext *context = (BMXEmbeddedReachabilityContext *)context_value;
    BMXEmbeddedHeapBlock *block = bmx_embedded_object_allocation(reference);
    if (!block || !bmx_embedded_type_descriptor_valid(((BMXEmbeddedObject *)reference)->type)) {
        context->invalid += 1u;
        return;
    }
    if (block->state.mark_epoch != context->epoch) {
        block->state.mark_epoch = context->epoch;
        context->reachable += 1u;
    }
}

static void bmx_embedded_mark_array(void *reference, void *context_value) {
    if (!reference || reference == &bmx_embedded_empty_array) return;
    BMXEmbeddedReachabilityContext *context = (BMXEmbeddedReachabilityContext *)context_value;
    BMXEmbeddedHeapBlock *block = bmx_embedded_array_allocation(reference);
    BMXEmbeddedArray *array = (BMXEmbeddedArray *)reference;
    if (!block || array->element_kind > BMX_EMBEDDED_ARRAY_ELEMENT_OBJECT ||
        (array->element_kind != BMX_EMBEDDED_ARRAY_ELEMENT_VALUE && array->element_size != sizeof(void *))) {
        context->invalid += 1u;
        return;
    }
    if (block->state.mark_epoch != context->epoch) {
        block->state.mark_epoch = context->epoch;
        context->reachable_arrays += 1u;
    }
}

static void bmx_embedded_mark_string(const void *reference, void *context_value) {
    if (!reference || reference == &bmx_embedded_empty_string) return;
    BMXEmbeddedHeapBlock *block = bmx_embedded_string_allocation(reference);
    /* Compiler-emitted literals live in flash rather than the managed heap and
       are permanent. Only heap-backed Strings participate in marking. */
    if (!block) return;
    BMXEmbeddedReachabilityContext *context = (BMXEmbeddedReachabilityContext *)context_value;
    if (block->state.mark_epoch != context->epoch) {
        block->state.mark_epoch = context->epoch;
        context->reachable_strings += 1u;
    }
}

static void bmx_embedded_mark_value(const void *value, const BMXEmbeddedValueDescriptor *descriptor, BMXEmbeddedReachabilityContext *context) {
    if (!value || !bmx_embedded_value_descriptor_valid(descriptor)) {
        context->invalid += 1u;
        return;
    }
    for (uint32_t field_index = 0; field_index < descriptor->field_count; ++field_index) {
        const BMXEmbeddedValueField *field = &descriptor->fields[field_index];
        for (uint32_t item = 0; item < field->count; ++item) {
            const uint8_t *address = (const uint8_t *)value + field->offset + (uint32_t)item * field->stride;
            if (field->kind == BMX_EMBEDDED_VALUE_OBJECT) bmx_embedded_mark_reference(*(void *const *)address, context);
            else if (field->kind == BMX_EMBEDDED_VALUE_ARRAY) bmx_embedded_mark_array(*(void *const *)address, context);
            else if (field->kind == BMX_EMBEDDED_VALUE_STRING) bmx_embedded_mark_string(*(const void *const *)address, context);
            else if (field->kind == BMX_EMBEDDED_VALUE_STRUCT && field->descriptor) bmx_embedded_mark_value(address, field->descriptor, context);
            else context->invalid += 1u;
        }
    }
}

uint32_t bmx_embedded_reachability_audit(void) {
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_object_failure();
        return 0;
    }
    bmx_embedded_reachability_epoch += 1u;
    if (!bmx_embedded_reachability_epoch) {
        for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first; block; block = block->state.next) {
            block->state.mark_epoch = 0;
            block->state.scan_epoch = 0;
        }
        bmx_embedded_reachability_epoch = 1u;
    }

    BMXEmbeddedReachabilityContext context = {bmx_embedded_reachability_epoch, 0, 0, 0, 0};
    for (uint32_t index = 0; index < BMX_EMBEDDED_ROOT_CAPACITY; ++index) {
        if (bmx_embedded_object_roots[index]) bmx_embedded_mark_reference(bmx_embedded_object_roots[index], &context);
    }
    for (BMXEmbeddedRootFrame *frame = bmx_embedded_root_frames; frame; frame = frame->previous) {
        for (uint16_t index = 0; index < frame->slot_count; ++index) {
            BMXEmbeddedRootSlot *slot = &frame->slots[index];
            if (!slot->address) continue;
            if (slot->kind == BMX_EMBEDDED_ROOT_OBJECT) bmx_embedded_mark_reference(*(void **)slot->address, &context);
            else if (slot->kind == BMX_EMBEDDED_ROOT_ARRAY) bmx_embedded_mark_array(*(void **)slot->address, &context);
            else if (slot->kind == BMX_EMBEDDED_ROOT_STRING) bmx_embedded_mark_string(*(void **)slot->address, &context);
            else if (slot->kind == BMX_EMBEDDED_ROOT_STRUCT) bmx_embedded_mark_value(slot->address, slot->descriptor, &context);
            else if (slot->kind == BMX_EMBEDDED_ROOT_EXCEPTION) {
                BMXEmbeddedException *exception = (BMXEmbeddedException *)slot->address;
                if (exception->kind == BMX_EMBEDDED_EXCEPTION_OBJECT) bmx_embedded_mark_reference(exception->value, &context);
                else if (exception->kind == BMX_EMBEDDED_EXCEPTION_ARRAY) bmx_embedded_mark_array(exception->value, &context);
                else if (exception->kind == BMX_EMBEDDED_EXCEPTION_STRING) bmx_embedded_mark_string(exception->value, &context);
                else if (exception->kind != BMX_EMBEDDED_EXCEPTION_NONE) context.invalid += 1u;
            }
            else context.invalid += 1u;
        }
    }

    int pending;
    do {
        pending = 0;
        for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first; block; block = block->state.next) {
            if ((block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE) || !(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_OBJECT)) continue;
            if (block->state.mark_epoch != context.epoch || block->state.scan_epoch == context.epoch) continue;
            block->state.scan_epoch = context.epoch;
            BMXEmbeddedObject *object = (BMXEmbeddedObject *)(block + 1);
            const BMXEmbeddedTypeDescriptor *type = object->type;
            for (uint32_t index = 0; index < type->reference_count; ++index) {
                void *reference = *(void **)((uint8_t *)object + type->reference_offsets[index]);
                bmx_embedded_mark_reference(reference, &context);
            }
            for (uint32_t index = 0; index < type->array_count; ++index) {
                void *reference = *(void **)((uint8_t *)object + type->array_offsets[index]);
                bmx_embedded_mark_array(reference, &context);
            }
            for (uint32_t index = 0; index < type->string_count; ++index) {
                const void *reference = *(const void **)((uint8_t *)object + type->string_offsets[index]);
                bmx_embedded_mark_string(reference, &context);
            }
            for (uint32_t index = 0; index < type->value_field_count; ++index) {
                const BMXEmbeddedValueField *field = &type->value_fields[index];
                for (uint32_t item = 0; item < field->count; ++item) {
                    const uint8_t *address = (const uint8_t *)object + field->offset + (uint32_t)item * field->stride;
                    bmx_embedded_mark_value(address, field->descriptor, &context);
                }
            }
            if (type->flags & BMX_EMBEDDED_TYPE_FLAG_CUSTOM_TRACE) type->trace(object, bmx_embedded_mark_reference, &context);
            pending = 1;
        }
        for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first; block; block = block->state.next) {
            if ((block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE) || !(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_ARRAY)) continue;
            if (block->state.mark_epoch != context.epoch || block->state.scan_epoch == context.epoch) continue;
            block->state.scan_epoch = context.epoch;
            BMXEmbeddedArray *array = (BMXEmbeddedArray *)(block + 1);
            if (array->element_kind == BMX_EMBEDDED_ARRAY_ELEMENT_OBJECT) {
                const uint32_t header_size = bmx_embedded_align_size((uint32_t)sizeof(BMXEmbeddedArray));
                void **elements = (void **)((uint8_t *)array + header_size);
                for (int32_t index = 0; index < array->length; ++index) bmx_embedded_mark_reference(elements[index], &context);
            } else if (array->element_kind == BMX_EMBEDDED_ARRAY_ELEMENT_STRING) {
                const uint32_t header_size = bmx_embedded_align_size((uint32_t)sizeof(BMXEmbeddedArray));
                const void **elements = (const void **)((uint8_t *)array + header_size);
                for (int32_t index = 0; index < array->length; ++index) bmx_embedded_mark_string(elements[index], &context);
            } else if (array->element_descriptor) {
                const uint32_t header_size = bmx_embedded_align_size((uint32_t)sizeof(BMXEmbeddedArray));
                const uint8_t *elements = (const uint8_t *)array + header_size;
                for (int32_t index = 0; index < array->length; ++index) {
                    bmx_embedded_mark_value(elements + (uint32_t)index * array->element_size, array->element_descriptor, &context);
                }
            }
            pending = 1;
        }
    } while (pending);

    bmx_embedded_reachable_objects = context.reachable;
    bmx_embedded_unreachable_objects = bmx_embedded_live_objects - context.reachable;
    bmx_embedded_invalid_references = context.invalid;
    bmx_embedded_reachable_arrays = context.reachable_arrays;
    bmx_embedded_unreachable_arrays = bmx_embedded_live_arrays - context.reachable_arrays;
    bmx_embedded_reachable_strings = context.reachable_strings;
    bmx_embedded_unreachable_strings = bmx_embedded_live_strings - context.reachable_strings;
    return context.reachable;
}

uint32_t bmx_embedded_reachable_object_count(void) {
    return bmx_embedded_reachable_objects;
}

uint32_t bmx_embedded_unreachable_object_count(void) {
    return bmx_embedded_unreachable_objects;
}

uint32_t bmx_embedded_invalid_reference_count(void) {
    return bmx_embedded_invalid_references;
}

uint32_t bmx_embedded_reachable_array_count(void) {
    return bmx_embedded_reachable_arrays;
}

uint32_t bmx_embedded_unreachable_array_count(void) {
    return bmx_embedded_unreachable_arrays;
}

uint32_t bmx_embedded_reachable_string_count(void) {
    return bmx_embedded_reachable_strings;
}

uint32_t bmx_embedded_unreachable_string_count(void) {
    return bmx_embedded_unreachable_strings;
}

uint32_t bmx_embedded_collect_objects(void) {
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID() || bmx_embedded_collection_active) {
        bmx_embedded_record_object_failure();
        return 0;
    }

    bmx_embedded_collection_active = 1u;
    bmx_embedded_collection_total += 1u;
    bmx_embedded_last_reclaimed_objects = 0;
    bmx_embedded_last_reclaimed_byte_total = 0;
    bmx_embedded_last_reclaimed_arrays = 0;
    bmx_embedded_last_reclaimed_array_byte_total = 0;
    bmx_embedded_last_reclaimed_strings = 0;
    bmx_embedded_last_reclaimed_string_byte_total = 0;
    bmx_embedded_finalizer_pending_objects = 0;
    bmx_embedded_last_finalized_objects = 0;
    bmx_embedded_reachability_audit();
    if (bmx_embedded_invalid_references) {
        bmx_embedded_collection_active = 0;
        bmx_embedded_record_object_failure();
        return 0;
    }

    /* Queue every newly unreachable finalizable Object before invoking any
       user code. Heap order is intentionally the only ordering guarantee. */
    for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first; block; block = block->state.next) {
        if ((block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE) || !(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_OBJECT)) continue;
        if (block->state.mark_epoch == bmx_embedded_reachability_epoch) continue;
        const BMXEmbeddedObject *object = (const BMXEmbeddedObject *)(block + 1);
        if ((object->type->flags & BMX_EMBEDDED_TYPE_FLAG_HAS_FINALIZER) && !(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FINALIZED)) {
            block->state.flags |= BMX_EMBEDDED_HEAP_BLOCK_FINALIZER_PENDING;
            bmx_embedded_finalizer_pending_objects += 1u;
        }
    }
    if (bmx_embedded_finalizer_pending_objects) {
        for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first; block; block = block->state.next) {
            if (!(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FINALIZER_PENDING)) continue;
            BMXEmbeddedObject *object = (BMXEmbeddedObject *)(block + 1);
            block->state.flags &= ~BMX_EMBEDDED_HEAP_BLOCK_FINALIZER_PENDING;
            block->state.flags |= BMX_EMBEDDED_HEAP_BLOCK_FINALIZED;
            bmx_embedded_finalizer_pending_objects -= 1u;
            bmx_embedded_finalizer_invocation_total += 1u;
            bmx_embedded_last_finalized_objects += 1u;
            object->type->finalizer(object);
        }
        /* Do not sweep during a finalizer cycle. A later collection starts a
           fresh reachability epoch, observes resurrection and field changes,
           and can reclaim only Objects whose finalizer has already run. */
        bmx_embedded_collection_active = 0;
        return 0;
    }

    BMXEmbeddedHeapBlock *block = bmx_embedded_heap_first;
    while (block) {
        if (!(block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_FREE) &&
            block->state.mark_epoch != bmx_embedded_reachability_epoch &&
            (block->state.flags & (BMX_EMBEDDED_HEAP_BLOCK_OBJECT | BMX_EMBEDDED_HEAP_BLOCK_ARRAY | BMX_EMBEDDED_HEAP_BLOCK_STRING))) {
            const uint32_t reclaimed_bytes = block->state.requested_size;
            if (block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_OBJECT) {
                bmx_embedded_last_reclaimed_objects += 1u;
                bmx_embedded_last_reclaimed_byte_total += reclaimed_bytes;
                bmx_embedded_live_objects -= 1u;
                bmx_embedded_live_object_bytes -= reclaimed_bytes;
            } else if (block->state.flags & BMX_EMBEDDED_HEAP_BLOCK_ARRAY) {
                bmx_embedded_last_reclaimed_arrays += 1u;
                bmx_embedded_last_reclaimed_array_byte_total += reclaimed_bytes;
                bmx_embedded_live_arrays -= 1u;
                bmx_embedded_live_array_bytes -= reclaimed_bytes;
            } else {
                bmx_embedded_last_reclaimed_strings += 1u;
                bmx_embedded_last_reclaimed_string_byte_total += reclaimed_bytes;
                bmx_embedded_live_strings -= 1u;
                bmx_embedded_live_string_bytes -= reclaimed_bytes;
            }
            block = bmx_embedded_heap_release(block)->state.next;
        } else {
            block = block->state.next;
        }
    }

    bmx_embedded_reachable_objects = bmx_embedded_live_objects;
    bmx_embedded_unreachable_objects = 0;
    bmx_embedded_reachable_arrays = bmx_embedded_live_arrays;
    bmx_embedded_unreachable_arrays = 0;
    bmx_embedded_reachable_strings = bmx_embedded_live_strings;
    bmx_embedded_unreachable_strings = 0;
    bmx_embedded_collection_active = 0;
    return bmx_embedded_last_reclaimed_objects;
}

uint32_t bmx_embedded_collection_count(void) {
    return bmx_embedded_collection_total;
}

uint32_t bmx_embedded_automatic_collection_count(void) {
    return bmx_embedded_automatic_collection_total;
}

uint32_t bmx_embedded_last_reclaimed_object_count(void) {
    return bmx_embedded_last_reclaimed_objects;
}

uint32_t bmx_embedded_last_reclaimed_bytes(void) {
    return bmx_embedded_last_reclaimed_byte_total;
}

uint32_t bmx_embedded_last_reclaimed_array_count(void) {
    return bmx_embedded_last_reclaimed_arrays;
}

uint32_t bmx_embedded_last_reclaimed_array_bytes(void) {
    return bmx_embedded_last_reclaimed_array_byte_total;
}

uint32_t bmx_embedded_last_reclaimed_string_count(void) {
    return bmx_embedded_last_reclaimed_strings;
}

uint32_t bmx_embedded_last_reclaimed_string_bytes(void) {
    return bmx_embedded_last_reclaimed_string_byte_total;
}

uint32_t bmx_embedded_finalizer_pending_count(void) {
    return bmx_embedded_finalizer_pending_objects;
}

uint32_t bmx_embedded_finalizer_invocation_count(void) {
    return bmx_embedded_finalizer_invocation_total;
}

uint32_t bmx_embedded_last_finalized_object_count(void) {
    return bmx_embedded_last_finalized_objects;
}

uint32_t bmx_embedded_heap_reusable_bytes(void) {
    uint32_t bytes = 0;
    for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_free; block; block = block->state.free_next) bytes += block->state.capacity;
    return bytes;
}

uint32_t bmx_embedded_heap_largest_free_block(void) {
    uint32_t largest = 0;
    for (BMXEmbeddedHeapBlock *block = bmx_embedded_heap_free; block; block = block->state.free_next) {
        if (block->state.capacity > largest) largest = block->state.capacity;
    }
    return largest;
}

static void bmx_embedded_record_string_failure(void) {
    __atomic_fetch_add(&bmx_embedded_string_failures, 1u, __ATOMIC_RELAXED);
}

static BMXEmbeddedString *bmx_embedded_string_new(int32_t length) {
    if (length <= 0) return (BMXEmbeddedString *)&bmx_embedded_empty_string;
    const uint32_t header_size = bmx_embedded_align_size((uint32_t)sizeof(BMXEmbeddedString));
    const uint32_t count = (uint32_t)length;
    if (count > (UINT32_MAX - header_size) / sizeof(uint16_t) || !BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_arena_failure();
        bmx_embedded_record_string_failure();
        return (BMXEmbeddedString *)&bmx_embedded_empty_string;
    }
    const uint32_t total_size = header_size + count * (uint32_t)sizeof(uint16_t);
    BMXEmbeddedString *text = (BMXEmbeddedString *)bmx_embedded_heap_allocate_with_collection(total_size, BMX_EMBEDDED_HEAP_BLOCK_STRING);
    if (!text) {
        bmx_embedded_record_arena_failure();
        bmx_embedded_record_string_failure();
        return (BMXEmbeddedString *)&bmx_embedded_empty_string;
    }
    text->length = length;
    text->buf = (const uint16_t *)((uint8_t *)text + header_size);
    bmx_embedded_string_allocations += 1u;
    bmx_embedded_string_bytes += total_size;
    bmx_embedded_live_strings += 1u;
    bmx_embedded_live_string_bytes += total_size;
    return text;
}

BMXEmbeddedString *bmx_embedded_string_allocate(int32_t length) {
    return bmx_embedded_string_new(length);
}

uint32_t bmx_embedded_string_failure_count(void) {
    return __atomic_load_n(&bmx_embedded_string_failures, __ATOMIC_RELAXED);
}

uint32_t bmx_embedded_string_allocation_count(void) {
    return bmx_embedded_string_allocations;
}

uint32_t bmx_embedded_string_allocated_bytes(void) {
    return bmx_embedded_string_bytes;
}

uint32_t bmx_embedded_string_live_count(void) {
    return bmx_embedded_live_strings;
}

uint32_t bmx_embedded_string_live_bytes(void) {
    return bmx_embedded_live_string_bytes;
}

int32_t bmx_embedded_string_compare(const BMXEmbeddedString *left, const BMXEmbeddedString *right) {
    int32_t common = left->length < right->length ? left->length : right->length;
    for (int32_t index = 0; index < common; ++index) {
        if (left->buf[index] < right->buf[index]) return -1;
        if (left->buf[index] > right->buf[index]) return 1;
    }
    return (left->length > right->length) - (left->length < right->length);
}

int32_t bmx_embedded_string_equals(const BMXEmbeddedString *left, const BMXEmbeddedString *right) {
    return bmx_embedded_string_compare(left, right) == 0;
}

uint32_t bmx_embedded_string_hash(const BMXEmbeddedString *text) {
    uint32_t hash = 2166136261u;
    for (int32_t index = 0; index < text->length; ++index) {
        hash ^= text->buf[index];
        hash *= 16777619u;
    }
    return hash;
}

static BMXEmbeddedStringCaseTransform bmx_embedded_unicode_lower;
static BMXEmbeddedStringCaseTransform bmx_embedded_unicode_upper;
static BMXEmbeddedCharacterCaseFold bmx_embedded_unicode_fold;

static uint16_t bmx_embedded_ascii_case_fold(uint16_t character) {
    return character >= (uint16_t)'A' && character <= (uint16_t)'Z' ?
        character + ((uint16_t)'a' - (uint16_t)'A') : character;
}

void bmx_embedded_string_install_unicode_case(BMXEmbeddedStringCaseTransform lower,
    BMXEmbeddedStringCaseTransform upper, BMXEmbeddedCharacterCaseFold fold) {
    bmx_embedded_unicode_lower = lower;
    bmx_embedded_unicode_upper = upper;
    bmx_embedded_unicode_fold = fold;
}

uint16_t bmx_embedded_string_fold_character(uint16_t character) {
    return bmx_embedded_unicode_fold ? bmx_embedded_unicode_fold(character) :
        bmx_embedded_ascii_case_fold(character);
}

int32_t bmx_embedded_string_compare_case(const BMXEmbeddedString *left, const BMXEmbeddedString *right,
    int32_t case_sensitive) {
    if (case_sensitive) return bmx_embedded_string_compare(left, right);
    int32_t common = left->length < right->length ? left->length : right->length;
    for (int32_t index = 0; index < common; ++index) {
        uint16_t left_character = left->buf[index];
        uint16_t right_character = right->buf[index];
        if (left_character == right_character) continue;
        left_character = bmx_embedded_unicode_fold ? bmx_embedded_unicode_fold(left_character) :
            bmx_embedded_ascii_case_fold(left_character);
        right_character = bmx_embedded_unicode_fold ? bmx_embedded_unicode_fold(right_character) :
            bmx_embedded_ascii_case_fold(right_character);
        if (left_character != right_character) return (int32_t)left_character - right_character;
    }
    return left->length - right->length;
}

int32_t bmx_embedded_string_equals_case(const BMXEmbeddedString *left, const BMXEmbeddedString *right,
    int32_t case_sensitive) {
    if (left->length != right->length) return 0;
    return bmx_embedded_string_compare_case(left, right, case_sensitive) == 0;
}

uint32_t bmx_embedded_string_hash_case(const BMXEmbeddedString *text, int32_t case_sensitive) {
    if (case_sensitive) return bmx_embedded_string_hash(text);
    uint32_t hash = 2166136261u;
    for (int32_t index = 0; index < text->length; ++index) {
        uint16_t character = bmx_embedded_unicode_fold ? bmx_embedded_unicode_fold(text->buf[index]) :
            bmx_embedded_ascii_case_fold(text->buf[index]);
        hash ^= character;
        hash *= 16777619u;
    }
    return hash;
}

const BMXEmbeddedString *bmx_embedded_string_to_string(const BMXEmbeddedString *text) {
    return text;
}

int32_t bmx_embedded_string_find(const BMXEmbeddedString *text, const BMXEmbeddedString *substring, int32_t start) {
    if (!text || !substring) return -1;
    if (start < 0) start = 0;
    if (substring->length == 0) return start <= text->length ? start : -1;
    if (start > text->length - substring->length) return -1;
    for (int32_t index = start; index <= text->length - substring->length; ++index) {
        if (!memcmp(text->buf + index, substring->buf, (size_t)substring->length * sizeof(uint16_t))) return index;
    }
    return -1;
}

int32_t bmx_embedded_string_find_last(const BMXEmbeddedString *text, const BMXEmbeddedString *substring, int32_t start) {
    if (!text || !substring || start < 0) return -1;
    int32_t index = text->length - start;
    if (index > text->length - substring->length) index = text->length - substring->length;
    while (index >= 0) {
        if (!memcmp(text->buf + index, substring->buf, (size_t)substring->length * sizeof(uint16_t))) return index;
        --index;
    }
    return -1;
}

const BMXEmbeddedString *bmx_embedded_string_trim(const BMXEmbeddedString *text) {
    if (!text || !text->length) return &bmx_embedded_empty_string;
    int32_t begin = 0;
    int32_t end = text->length;
    while (begin < end && text->buf[begin] <= (uint16_t)' ') ++begin;
    if (begin == end) return &bmx_embedded_empty_string;
    while (text->buf[end - 1] <= (uint16_t)' ') --end;
    if (begin == 0 && end == text->length) return text;
    BMXEmbeddedString *result = bmx_embedded_string_new(end - begin);
    if (result != &bmx_embedded_empty_string) {
        memcpy((void *)(uintptr_t)result->buf, text->buf + begin, (size_t)(end - begin) * sizeof(uint16_t));
    }
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_replace(const BMXEmbeddedString *text, const BMXEmbeddedString *substring, const BMXEmbeddedString *replacement) {
    if (!text || !substring || !replacement || !substring->length) return text ? text : &bmx_embedded_empty_string;
    int32_t index = 0;
    int32_t match_count = 0;
    while ((index = bmx_embedded_string_find(text, substring, index)) != -1) {
        index += substring->length;
        ++match_count;
    }
    if (!match_count) return text;
    int64_t result_length = (int64_t)text->length + (int64_t)(replacement->length - substring->length) * match_count;
    if (result_length < 0 || result_length > INT32_MAX) {
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    BMXEmbeddedString *result = bmx_embedded_string_new((int32_t)result_length);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *output = (uint16_t *)(uintptr_t)result->buf;
    int32_t source = 0;
    int32_t destination = 0;
    int32_t match;
    while ((match = bmx_embedded_string_find(text, substring, source)) != -1) {
        int32_t prefix_length = match - source;
        if (prefix_length) {
            memcpy(output + destination, text->buf + source, (size_t)prefix_length * sizeof(uint16_t));
            destination += prefix_length;
        }
        if (replacement->length) {
            memcpy(output + destination, replacement->buf, (size_t)replacement->length * sizeof(uint16_t));
            destination += replacement->length;
        }
        source = match + substring->length;
    }
    if (source < text->length) {
        memcpy(output + destination, text->buf + source, (size_t)(text->length - source) * sizeof(uint16_t));
    }
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_to_lower(const BMXEmbeddedString *text) {
    if (bmx_embedded_unicode_lower) return bmx_embedded_unicode_lower(text);
    if (!text || !text->length) return &bmx_embedded_empty_string;
    int changed = 0;
    for (int32_t index = 0; index < text->length; ++index) {
        if (text->buf[index] >= (uint16_t)'A' && text->buf[index] <= (uint16_t)'Z') {
            changed = 1;
            break;
        }
    }
    if (!changed) return text;
    BMXEmbeddedString *result = bmx_embedded_string_new(text->length);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *buffer = (uint16_t *)(uintptr_t)result->buf;
    for (int32_t index = 0; index < text->length; ++index) {
        uint16_t character = text->buf[index];
        if (character >= (uint16_t)'A' && character <= (uint16_t)'Z') character += (uint16_t)'a' - (uint16_t)'A';
        buffer[index] = character;
    }
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_to_upper(const BMXEmbeddedString *text) {
    if (bmx_embedded_unicode_upper) return bmx_embedded_unicode_upper(text);
    if (!text || !text->length) return &bmx_embedded_empty_string;
    int changed = 0;
    for (int32_t index = 0; index < text->length; ++index) {
        if (text->buf[index] >= (uint16_t)'a' && text->buf[index] <= (uint16_t)'z') {
            changed = 1;
            break;
        }
    }
    if (!changed) return text;
    BMXEmbeddedString *result = bmx_embedded_string_new(text->length);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *buffer = (uint16_t *)(uintptr_t)result->buf;
    for (int32_t index = 0; index < text->length; ++index) {
        uint16_t character = text->buf[index];
        if (character >= (uint16_t)'a' && character <= (uint16_t)'z') character -= (uint16_t)'a' - (uint16_t)'A';
        buffer[index] = character;
    }
    return result;
}

int32_t bmx_embedded_string_starts_with(const BMXEmbeddedString *text, const BMXEmbeddedString *substring) {
    if (!text || !substring || text->length < substring->length) return 0;
    return !memcmp(text->buf, substring->buf, (size_t)substring->length * sizeof(uint16_t));
}

int32_t bmx_embedded_string_ends_with(const BMXEmbeddedString *text, const BMXEmbeddedString *substring) {
    if (!text || !substring || text->length < substring->length) return 0;
    return !memcmp(text->buf + text->length - substring->length, substring->buf,
        (size_t)substring->length * sizeof(uint16_t));
}

int32_t bmx_embedded_string_contains(const BMXEmbeddedString *text, const BMXEmbeddedString *substring) {
    return bmx_embedded_string_find(text, substring, 0) != -1;
}

const BMXEmbeddedString *bmx_embedded_string_replicate(const BMXEmbeddedString *text, int32_t count) {
    if (!text || !text->length || count <= 0) return &bmx_embedded_empty_string;
    if (text->length > INT32_MAX / count) {
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    BMXEmbeddedString *result = bmx_embedded_string_new(text->length * count);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *output = (uint16_t *)(uintptr_t)result->buf;
    for (int32_t index = 0; index < count; ++index) {
        memcpy(output + index * text->length, text->buf, (size_t)text->length * sizeof(uint16_t));
    }
    return result;
}

BMXEmbeddedArray *bmx_embedded_string_split(const BMXEmbeddedString *text, const BMXEmbeddedString *separator) {
    if (!text) text = &bmx_embedded_empty_string;
    if (!separator) separator = &bmx_embedded_empty_string;
    int32_t part_count = 0;
    if (separator->length) {
        part_count = 1;
        int32_t index = 0;
        while ((index = bmx_embedded_string_find(text, separator, index)) != -1) {
            if (part_count == INT32_MAX) {
                bmx_embedded_record_array_failure();
                return &bmx_embedded_empty_array;
            }
            ++part_count;
            index += separator->length;
        }
    } else {
        int32_t index = 0;
        while (index < text->length) {
            while (index < text->length && text->buf[index] < 33u) ++index;
            if (index == text->length) break;
            ++part_count;
            while (index < text->length && text->buf[index] > 32u) ++index;
        }
        if (!part_count) return &bmx_embedded_empty_array;
    }

    BMXEmbeddedArray *parts = bmx_embedded_array_new_1d(part_count, (uint32_t)sizeof(const BMXEmbeddedString *),
        BMX_EMBEDDED_ARRAY_ELEMENT_STRING, NULL, NULL);
    if (parts == &bmx_embedded_empty_array) return parts;
    BMXEmbeddedArray *parts_root = parts;
    BMXEmbeddedRootSlot slot = {(void *)&parts_root, BMX_EMBEDDED_ROOT_ARRAY, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1);
    const BMXEmbeddedString **output = (const BMXEmbeddedString **)bmx_embedded_array_data(parts);

    if (separator->length) {
        int32_t begin = 0;
        for (int32_t part = 0; part < part_count; ++part) {
            int32_t end = bmx_embedded_string_find(text, separator, begin);
            if (end == -1) end = text->length;
            output[part] = bmx_embedded_string_slice(text, begin, end);
            begin = end + separator->length;
        }
    } else {
        int32_t index = 0;
        for (int32_t part = 0; part < part_count; ++part) {
            while (text->buf[index] < 33u) ++index;
            int32_t begin = index;
            while (index < text->length && text->buf[index] > 32u) ++index;
            output[part] = bmx_embedded_string_slice(text, begin, index);
        }
    }
    bmx_embedded_root_frame_leave(&frame);
    return parts;
}

const BMXEmbeddedString *bmx_embedded_string_join(const BMXEmbeddedString *separator, BMXEmbeddedArray *parts) {
    if (!separator) separator = &bmx_embedded_empty_string;
    if (!parts || parts == &bmx_embedded_empty_array || !parts->length) return &bmx_embedded_empty_string;
    if (parts->element_kind != BMX_EMBEDDED_ARRAY_ELEMENT_STRING || parts->element_size != sizeof(const BMXEmbeddedString *)) {
        bmx_embedded_record_array_failure();
        return &bmx_embedded_empty_string;
    }
    const BMXEmbeddedString *const *values = (const BMXEmbeddedString *const *)bmx_embedded_array_data(parts);
    int64_t length = (int64_t)(parts->length - 1) * separator->length;
    for (int32_t index = 0; index < parts->length; ++index) {
        const BMXEmbeddedString *part = values[index] ? values[index] : &bmx_embedded_empty_string;
        length += part->length;
        if (length > INT32_MAX) {
            bmx_embedded_record_string_failure();
            return &bmx_embedded_empty_string;
        }
    }
    BMXEmbeddedString *result = bmx_embedded_string_new((int32_t)length);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *output = (uint16_t *)(uintptr_t)result->buf;
    for (int32_t index = 0; index < parts->length; ++index) {
        if (index && separator->length) {
            memcpy(output, separator->buf, (size_t)separator->length * sizeof(uint16_t));
            output += separator->length;
        }
        const BMXEmbeddedString *part = values[index] ? values[index] : &bmx_embedded_empty_string;
        if (part->length) {
            memcpy(output, part->buf, (size_t)part->length * sizeof(uint16_t));
            output += part->length;
        }
    }
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_from_bytes(const uint8_t *bytes, int32_t count) {
    if (!bytes || count <= 0) return &bmx_embedded_empty_string;
    BMXEmbeddedString *result = bmx_embedded_string_new(count);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *buffer = (uint16_t *)(uintptr_t)result->buf;
    for (int32_t index = 0; index < count; ++index) buffer[index] = bytes[index];
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_from_shorts(const uint16_t *characters, int32_t count) {
    if (!characters || count <= 0) return &bmx_embedded_empty_string;
    BMXEmbeddedString *result = bmx_embedded_string_new(count);
    if (result != &bmx_embedded_empty_string) {
        memcpy((void *)(uintptr_t)result->buf, characters, (size_t)count * sizeof(uint16_t));
    }
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_from_c_string(const uint8_t *bytes) {
    if (!bytes) return &bmx_embedded_empty_string;
    size_t count = strlen((const char *)bytes);
    if (count > INT32_MAX) {
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    return bmx_embedded_string_from_bytes(bytes, (int32_t)count);
}

const BMXEmbeddedString *bmx_embedded_string_from_w_string(const uint16_t *characters) {
    if (!characters) return &bmx_embedded_empty_string;
    size_t count = 0;
    while (characters[count]) {
        if (count == INT32_MAX) {
            bmx_embedded_record_string_failure();
            return &bmx_embedded_empty_string;
        }
        ++count;
    }
    return bmx_embedded_string_from_shorts(characters, (int32_t)count);
}

const BMXEmbeddedString *bmx_embedded_string_from_ascii(const char *bytes, int32_t count) {
    return bmx_embedded_string_from_bytes((const uint8_t *)bytes, count);
}

const BMXEmbeddedString *bmx_embedded_string_from_utf8_string(const uint8_t *bytes) {
    if (!bytes) return &bmx_embedded_empty_string;
    size_t count = strlen((const char *)bytes);
    if (count > INT32_MAX) {
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    return bmx_embedded_string_from_utf8_bytes(bytes, (int32_t)count);
}

static uint32_t bmx_embedded_decode_utf8(const uint8_t *bytes, int32_t count, int32_t *index) {
    uint32_t first = bytes[(*index)++];
    if (first < 0x80u) return first;
    int needed = first >= 0xf0u ? 3 : first >= 0xe0u ? 2 : first >= 0xc2u ? 1 : 0;
    if (!needed || *index + needed > count) return 0xfffdu;
    uint32_t value = first & (needed == 1 ? 0x1fu : needed == 2 ? 0x0fu : 0x07u);
    int32_t continuation = *index;
    for (int offset = 0; offset < needed; ++offset) {
        uint32_t next = bytes[continuation + offset];
        if ((next & 0xc0u) != 0x80u) return 0xfffdu;
        value = (value << 6) | (next & 0x3fu);
    }
    if ((needed == 2 && value < 0x800u) || (needed == 3 && value < 0x10000u) ||
        (value >= 0xd800u && value <= 0xdfffu) || value > 0x10ffffu) return 0xfffdu;
    *index += needed;
    return value;
}

const BMXEmbeddedString *bmx_embedded_string_from_utf8_bytes(const uint8_t *bytes, int32_t count) {
    if (!bytes || count <= 0) return &bmx_embedded_empty_string;
    int32_t units = 0;
    for (int32_t index = 0; index < count;) {
        uint32_t code_point = bmx_embedded_decode_utf8(bytes, count, &index);
        units += code_point > 0xffffu ? 2 : 1;
    }
    BMXEmbeddedString *result = bmx_embedded_string_new(units);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *buffer = (uint16_t *)(uintptr_t)result->buf;
    int32_t output = 0;
    for (int32_t index = 0; index < count;) {
        uint32_t code_point = bmx_embedded_decode_utf8(bytes, count, &index);
        if (code_point <= 0xffffu) {
            buffer[output++] = (uint16_t)code_point;
        } else {
            code_point -= 0x10000u;
            buffer[output++] = (uint16_t)(0xd800u | (code_point >> 10));
            buffer[output++] = (uint16_t)(0xdc00u | (code_point & 0x3ffu));
        }
    }
    return result;
}

uint8_t *bmx_embedded_string_to_c_string(const BMXEmbeddedString *text) {
    int32_t count = text ? text->length : 0;
    uint8_t *result = (uint8_t *)bbMemAlloc((size_t)count + 1u);
    if (!result) return NULL;
    for (int32_t index = 0; index < count; ++index) result[index] = (uint8_t)text->buf[index];
    result[count] = 0;
    return result;
}

uint16_t *bmx_embedded_string_to_w_string_buffer(const BMXEmbeddedString *text, uint16_t *buffer, size_t *length) {
    if (!buffer || !length) return buffer;
    size_t capacity = *length;
    if (!capacity) return buffer;
    size_t copied = text && text->length > 0 ? (size_t)text->length : 0u;
    if (copied >= capacity) copied = capacity - 1u;
    if (copied) memcpy(buffer, text->buf, copied * sizeof(uint16_t));
    buffer[copied] = 0;
    *length = copied;
    return buffer;
}

uint16_t *bmx_embedded_string_to_w_string(const BMXEmbeddedString *text) {
    size_t capacity = (size_t)(text && text->length > 0 ? text->length : 0) + 1u;
    if (capacity > SIZE_MAX / sizeof(uint16_t)) return NULL;
    uint16_t *result = (uint16_t *)bbMemAlloc(capacity * sizeof(uint16_t));
    if (!result) return NULL;
    return bmx_embedded_string_to_w_string_buffer(text, result, &capacity);
}

static size_t bmx_embedded_utf8_length(const BMXEmbeddedString *text) {
    size_t length = 0;
    for (int32_t index = 0; text && index < text->length; ++index) {
        uint32_t code_point = text->buf[index];
        if (code_point >= 0xd800u && code_point <= 0xdbffu && index + 1 < text->length) {
            uint32_t low = text->buf[index + 1];
            if (low >= 0xdc00u && low <= 0xdfffu) {
                code_point = 0x10000u + ((code_point - 0xd800u) << 10) + (low - 0xdc00u);
                ++index;
            } else code_point = 0xfffdu;
        } else if (code_point >= 0xdc00u && code_point <= 0xdfffu) code_point = 0xfffdu;
        length += code_point <= 0x7fu ? 1u : code_point <= 0x7ffu ? 2u : code_point <= 0xffffu ? 3u : 4u;
    }
    return length;
}

static uint8_t *bmx_embedded_encode_utf8(uint8_t *output, uint32_t code_point) {
    if (code_point <= 0x7fu) {
        *output++ = (uint8_t)code_point;
    } else if (code_point <= 0x7ffu) {
        *output++ = (uint8_t)(0xc0u | (code_point >> 6));
        *output++ = (uint8_t)(0x80u | (code_point & 0x3fu));
    } else if (code_point <= 0xffffu) {
        *output++ = (uint8_t)(0xe0u | (code_point >> 12));
        *output++ = (uint8_t)(0x80u | ((code_point >> 6) & 0x3fu));
        *output++ = (uint8_t)(0x80u | (code_point & 0x3fu));
    } else {
        *output++ = (uint8_t)(0xf0u | (code_point >> 18));
        *output++ = (uint8_t)(0x80u | ((code_point >> 12) & 0x3fu));
        *output++ = (uint8_t)(0x80u | ((code_point >> 6) & 0x3fu));
        *output++ = (uint8_t)(0x80u | (code_point & 0x3fu));
    }
    return output;
}

uint8_t *bmx_embedded_string_to_utf8_string_buffer(const BMXEmbeddedString *text, uint8_t *buffer, size_t *length) {
    if (!buffer || !length) return buffer;
    size_t capacity = *length;
    if (!capacity) return buffer;
    uint8_t *output = buffer;
    size_t remaining = capacity - 1u;
    for (int32_t index = 0; text && index < text->length; ++index) {
        uint32_t code_point = text->buf[index];
        if (code_point >= 0xd800u && code_point <= 0xdbffu && index + 1 < text->length) {
            uint32_t low = text->buf[index + 1];
            if (low >= 0xdc00u && low <= 0xdfffu) {
                code_point = 0x10000u + ((code_point - 0xd800u) << 10) + (low - 0xdc00u);
                ++index;
            } else code_point = 0xfffdu;
        } else if (code_point >= 0xdc00u && code_point <= 0xdfffu) code_point = 0xfffdu;
        size_t encoded = code_point <= 0x7fu ? 1u : code_point <= 0x7ffu ? 2u : code_point <= 0xffffu ? 3u : 4u;
        if (encoded > remaining) break;
        output = bmx_embedded_encode_utf8(output, code_point);
        remaining -= encoded;
    }
    *output = 0;
    *length = (size_t)(output - buffer);
    return buffer;
}

uint8_t *bmx_embedded_string_to_utf8_string_len(const BMXEmbeddedString *text, size_t *length) {
    size_t required = bmx_embedded_utf8_length(text);
    uint8_t *result = (uint8_t *)bbMemAlloc(required + 1u);
    if (!result) {
        if (length) *length = 0;
        return NULL;
    }
    uint8_t *output = result;
    for (int32_t index = 0; text && index < text->length; ++index) {
        uint32_t code_point = text->buf[index];
        if (code_point >= 0xd800u && code_point <= 0xdbffu && index + 1 < text->length) {
            uint32_t low = text->buf[index + 1];
            if (low >= 0xdc00u && low <= 0xdfffu) {
                code_point = 0x10000u + ((code_point - 0xd800u) << 10) + (low - 0xdc00u);
                ++index;
            } else code_point = 0xfffdu;
        } else if (code_point >= 0xdc00u && code_point <= 0xdfffu) code_point = 0xfffdu;
        output = bmx_embedded_encode_utf8(output, code_point);
    }
    *output = 0;
    if (length) *length = required;
    return result;
}

uint8_t *bmx_embedded_string_to_utf8_string(const BMXEmbeddedString *text) {
    return bmx_embedded_string_to_utf8_string_len(text, NULL);
}

uint32_t *bmx_embedded_string_to_utf32_string(const BMXEmbeddedString *text) {
    size_t capacity = (size_t)(text && text->length > 0 ? text->length : 0) + 1u;
    if (capacity > SIZE_MAX / sizeof(uint32_t)) return NULL;
    uint32_t *result = (uint32_t *)bbMemAlloc(capacity * sizeof(uint32_t));
    if (!result) return NULL;
    uint32_t *output = result;
    for (int32_t index = 0; text && index < text->length; ++index) {
        uint32_t code_point = text->buf[index];
        if (code_point >= 0xd800u && code_point <= 0xdbffu) {
            if (index + 1 >= text->length || text->buf[index + 1] < 0xdc00u || text->buf[index + 1] > 0xdfffu) {
                bbMemFree(result);
                bmx_embedded_exception_throw(bmx_embedded_exception_string(&bmx_embedded_invalid_utf16_string));
            }
            code_point = 0x10000u + ((code_point - 0xd800u) << 10) + (text->buf[++index] - 0xdc00u);
        } else if (code_point >= 0xdc00u && code_point <= 0xdfffu) {
            bbMemFree(result);
            bmx_embedded_exception_throw(bmx_embedded_exception_string(&bmx_embedded_invalid_utf16_string));
        }
        *output++ = code_point;
    }
    *output = 0;
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_from_utf32_bytes(const uint32_t *characters, size_t count) {
    if (!characters || !count) return &bmx_embedded_empty_string;
    if (count > (size_t)INT32_MAX / 2u) {
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    size_t units = 0;
    for (size_t index = 0; index < count; ++index) units += characters[index] > 0xffffu && characters[index] <= 0x10ffffu ? 2u : 1u;
    if (units > INT32_MAX) {
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    BMXEmbeddedString *result = bmx_embedded_string_new((int32_t)units);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *output = (uint16_t *)(uintptr_t)result->buf;
    for (size_t index = 0; index < count; ++index) {
        uint32_t code_point = characters[index];
        if (code_point >= 0xd800u && code_point <= 0xdfffu) code_point = 0xfffdu;
        else if (code_point > 0x10ffffu) code_point = 0xfffdu;
        if (code_point <= 0xffffu) *output++ = (uint16_t)code_point;
        else {
            code_point -= 0x10000u;
            *output++ = (uint16_t)(0xd800u + (code_point >> 10));
            *output++ = (uint16_t)(0xdc00u + (code_point & 0x3ffu));
        }
    }
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_from_utf32_string(const uint32_t *characters) {
    if (!characters) return &bmx_embedded_empty_string;
    size_t count = 0;
    while (characters[count]) {
        if (count == INT32_MAX) {
            bmx_embedded_record_string_failure();
            return &bmx_embedded_empty_string;
        }
        ++count;
    }
    return bmx_embedded_string_from_utf32_bytes(characters, count);
}

const BMXEmbeddedString *bmx_embedded_string_from_bytes_as_hex(const uint8_t *bytes, int32_t length, int32_t upper_case) {
    if (!bytes || length <= 0) return &bmx_embedded_empty_string;
    if (length > INT32_MAX / 2) {
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    static const char lower[] = "0123456789abcdef";
    static const char upper[] = "0123456789ABCDEF";
    const char *digits = upper_case ? upper : lower;
    BMXEmbeddedString *result = bmx_embedded_string_new(length * 2);
    if (result == &bmx_embedded_empty_string) return result;
    uint16_t *output = (uint16_t *)(uintptr_t)result->buf;
    for (int32_t index = 0; index < length; ++index) {
        output[index * 2] = (uint16_t)digits[bytes[index] >> 4];
        output[index * 2 + 1] = (uint16_t)digits[bytes[index] & 15u];
    }
    return result;
}

static int32_t bmx_embedded_hex_value(uint16_t character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    if (character >= 'A' && character <= 'F') return character - 'A' + 10;
    return -1;
}

int32_t bmx_embedded_string_to_bytes_from_hex_ex(const BMXEmbeddedString *text, int32_t offset, int32_t count,
        uint8_t *bytes, int32_t length) {
    if (!text || !text->length || offset < 0 || count < 0 || offset > text->length) return 0;
    if (!bytes || length <= 0) return -1;
    int32_t end = text->length;
    if (count < end - offset) end = offset + count;
    int32_t written = 0;
    for (int32_t index = offset; index + 1 < end; index += 2) {
        int32_t high = bmx_embedded_hex_value(text->buf[index]);
        int32_t low = bmx_embedded_hex_value(text->buf[index + 1]);
        if (high < 0 || low < 0) break;
        if (written >= length) return -1;
        bytes[written++] = (uint8_t)((high << 4) | low);
    }
    return written;
}

int32_t bmx_embedded_string_to_bytes_from_hex(const BMXEmbeddedString *text, uint8_t *bytes, int32_t length) {
    return bmx_embedded_string_to_bytes_from_hex_ex(text, 0, text ? text->length : 0, bytes, length);
}

const BMXEmbeddedString *bmx_embedded_string_concat(const BMXEmbeddedString *left, const BMXEmbeddedString *right) {
    if (!left || !right || left->length < 0 || right->length < 0 || left->length > INT32_MAX - right->length) {
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_arena_failure();
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    const BMXEmbeddedString *left_root = left;
    const BMXEmbeddedString *right_root = right;
    BMXEmbeddedRootSlot slots[2] = {
        {(void *)&left_root, BMX_EMBEDDED_ROOT_STRING, NULL},
        {(void *)&right_root, BMX_EMBEDDED_ROOT_STRING, NULL}
    };
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, slots, 2);
    BMXEmbeddedString *result = bmx_embedded_string_new(left->length + right->length);
    if (result != &bmx_embedded_empty_string) {
        uint16_t *buffer = (uint16_t *)(uintptr_t)result->buf;
        memcpy(buffer, left->buf, (size_t)left->length * sizeof(uint16_t));
        memcpy(buffer + left->length, right->buf, (size_t)right->length * sizeof(uint16_t));
    }
    bmx_embedded_root_frame_leave(&frame);
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_slice(const BMXEmbeddedString *text, int32_t begin, int32_t end) {
    if (!text || text->length < 0 || end <= begin) return &bmx_embedded_empty_string;
    int64_t length64 = (int64_t)end - begin;
    if (length64 > INT32_MAX) {
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    if (!BMX_EMBEDDED_PLATFORM_CONTEXT_VALID()) {
        bmx_embedded_record_arena_failure();
        bmx_embedded_record_string_failure();
        return &bmx_embedded_empty_string;
    }
    const BMXEmbeddedString *text_root = text;
    BMXEmbeddedRootSlot slot = {(void *)&text_root, BMX_EMBEDDED_ROOT_STRING, NULL};
    BMXEmbeddedRootFrame frame;
    bmx_embedded_root_frame_enter(&frame, &slot, 1);
    BMXEmbeddedString *result = bmx_embedded_string_new((int32_t)length64);
    if (result != &bmx_embedded_empty_string) {
        uint16_t *buffer = (uint16_t *)(uintptr_t)result->buf;
        for (int32_t index = 0; index < result->length; ++index) {
            int64_t source = (int64_t)begin + index;
            buffer[index] = source >= 0 && source < text->length ? text->buf[source] : (uint16_t)' ';
        }
    }
    bmx_embedded_root_frame_leave(&frame);
    return result;
}

const BMXEmbeddedString *bmx_embedded_string_from_char(int32_t character) {
    BMXEmbeddedString *result = bmx_embedded_string_new(1);
    if (result != &bmx_embedded_empty_string) ((uint16_t *)(uintptr_t)result->buf)[0] = (uint16_t)character;
    return result;
}

static int bmx_embedded_enum_descriptor_valid(const BMXEmbeddedEnumDescriptor *descriptor) {
    if (!descriptor || !descriptor->name || (descriptor->count && (!descriptor->values || !descriptor->names))) return 0;
    return descriptor->element_size == 1u || descriptor->element_size == 2u || descriptor->element_size == 4u || descriptor->element_size == 8u;
}

static void bmx_embedded_record_enum_failure(void) {
    __atomic_fetch_add(&bmx_embedded_enum_failures, 1u, __ATOMIC_RELAXED);
}

static void bmx_embedded_enum_store(void *result, uint16_t size, uint64_t value) {
    if (size == 1u) *(uint8_t *)result = (uint8_t)value;
    else if (size == 2u) *(uint16_t *)result = (uint16_t)value;
    else if (size == 4u) *(uint32_t *)result = (uint32_t)value;
    else *(uint64_t *)result = value;
}

static uint16_t bmx_embedded_ascii_fold(uint16_t character) {
    if (character >= (uint16_t)'A' && character <= (uint16_t)'Z') return character + ((uint16_t)'a' - (uint16_t)'A');
    return character;
}

static int bmx_embedded_enum_name_equals(const BMXEmbeddedString *candidate, const uint16_t *text, int32_t length) {
    if (!candidate || candidate->length != length) return 0;
    for (int32_t index = 0; index < length; ++index) {
        if (bmx_embedded_ascii_fold(candidate->buf[index]) != bmx_embedded_ascii_fold(text[index])) return 0;
    }
    return 1;
}

BMXEmbeddedArray *bmx_embedded_enum_values(const BMXEmbeddedEnumDescriptor *descriptor) {
    if (!bmx_embedded_enum_descriptor_valid(descriptor)) {
        bmx_embedded_record_enum_failure();
        return &bmx_embedded_empty_array;
    }
    BMXEmbeddedArray *result = bmx_embedded_array_new_1d(descriptor->count, descriptor->element_size, BMX_EMBEDDED_ARRAY_ELEMENT_VALUE, NULL, NULL);
    if (descriptor->count && result == &bmx_embedded_empty_array) {
        bmx_embedded_record_enum_failure();
        return result;
    }
    for (uint16_t index = 0; index < descriptor->count; ++index) {
        bmx_embedded_enum_store(bmx_embedded_array_element(result, index, descriptor->element_size), descriptor->element_size, descriptor->values[index]);
    }
    return result;
}

const BMXEmbeddedString *bmx_embedded_enum_to_string(const BMXEmbeddedEnumDescriptor *descriptor, uint64_t value) {
    if (!bmx_embedded_enum_descriptor_valid(descriptor)) {
        bmx_embedded_record_enum_failure();
        return &bmx_embedded_empty_string;
    }
    if (!(descriptor->flags & BMX_EMBEDDED_ENUM_FLAG_FLAGS)) {
        for (uint16_t index = 0; index < descriptor->count; ++index) {
            if (descriptor->values[index] == value) return descriptor->names[index];
        }
        return &bmx_embedded_empty_string;
    }

    uint64_t remaining = value;
    uint32_t length = 0;
    uint16_t part_count = 0;
    for (uint16_t index = 0; index < descriptor->count; ++index) {
        uint64_t item = descriptor->values[index];
        int selected = item ? (remaining & item) == item : value == 0 && !part_count;
        if (!selected) continue;
        if (part_count) length += 1u;
        length += (uint32_t)descriptor->names[index]->length;
        part_count += 1u;
        if (item) remaining &= ~item;
    }
    if (!part_count || length > INT32_MAX) return &bmx_embedded_empty_string;
    BMXEmbeddedString *result = bmx_embedded_string_new((int32_t)length);
    if (result == &bmx_embedded_empty_string) {
        bmx_embedded_record_enum_failure();
        return result;
    }
    uint16_t *buffer = (uint16_t *)(uintptr_t)result->buf;
    uint32_t offset = 0;
    remaining = value;
    part_count = 0;
    for (uint16_t index = 0; index < descriptor->count; ++index) {
        uint64_t item = descriptor->values[index];
        int selected = item ? (remaining & item) == item : value == 0 && !part_count;
        if (!selected) continue;
        if (part_count) buffer[offset++] = (uint16_t)'|';
        const BMXEmbeddedString *name = descriptor->names[index];
        memcpy(buffer + offset, name->buf, (size_t)name->length * sizeof(uint16_t));
        offset += (uint32_t)name->length;
        part_count += 1u;
        if (item) remaining &= ~item;
    }
    return result;
}

int32_t bmx_embedded_enum_try_convert(const BMXEmbeddedEnumDescriptor *descriptor, uint64_t value, void *result) {
    if (!bmx_embedded_enum_descriptor_valid(descriptor) || !result) {
        bmx_embedded_record_enum_failure();
        return 0;
    }
    if (!(descriptor->flags & BMX_EMBEDDED_ENUM_FLAG_FLAGS)) {
        for (uint16_t index = 0; index < descriptor->count; ++index) {
            if (descriptor->values[index] == value) {
                bmx_embedded_enum_store(result, descriptor->element_size, value);
                return 1;
            }
        }
        return 0;
    }
    uint64_t remaining = value;
    int zero_declared = 0;
    for (uint16_t index = 0; index < descriptor->count; ++index) {
        uint64_t item = descriptor->values[index];
        if (!item) zero_declared = 1;
        else if ((remaining & item) == item) remaining &= ~item;
    }
    if (remaining || (!value && !zero_declared)) return 0;
    bmx_embedded_enum_store(result, descriptor->element_size, value);
    return 1;
}

uint64_t bmx_embedded_enum_from_string(const BMXEmbeddedEnumDescriptor *descriptor, const BMXEmbeddedString *name) {
    if (!bmx_embedded_enum_descriptor_valid(descriptor) || !name || !name->length) {
        bmx_embedded_record_enum_failure();
        return 0;
    }
    if (!(descriptor->flags & BMX_EMBEDDED_ENUM_FLAG_FLAGS)) {
        for (uint16_t index = 0; index < descriptor->count; ++index) {
            if (bmx_embedded_enum_name_equals(descriptor->names[index], name->buf, name->length)) return descriptor->values[index];
        }
        bmx_embedded_record_enum_failure();
        return 0;
    }
    uint64_t result = 0;
    int32_t segment_start = 0;
    for (int32_t index = 0; index <= name->length; ++index) {
        if (index != name->length && name->buf[index] != (uint16_t)'|') continue;
        int32_t segment_length = index - segment_start;
        int matched = 0;
        if (segment_length > 0) {
            for (uint16_t candidate = 0; candidate < descriptor->count; ++candidate) {
                if (bmx_embedded_enum_name_equals(descriptor->names[candidate], name->buf + segment_start, segment_length)) {
                    result |= descriptor->values[candidate];
                    matched = 1;
                    break;
                }
            }
        }
        if (!matched) {
            bmx_embedded_record_enum_failure();
            return 0;
        }
        segment_start = index + 1;
    }
    return result;
}

uint32_t bmx_embedded_enum_failure_count(void) {
    return __atomic_load_n(&bmx_embedded_enum_failures, __ATOMIC_RELAXED);
}

int32_t bmx_embedded_string_asc(const BMXEmbeddedString *text) {
    return text->length ? text->buf[0] : -1;
}
