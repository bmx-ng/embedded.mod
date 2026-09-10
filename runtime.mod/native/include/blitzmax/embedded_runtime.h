#ifndef BLITZMAX_EMBEDDED_RUNTIME_H
#define BLITZMAX_EMBEDDED_RUNTIME_H

#include <stddef.h>
#include <stdint.h>
#include <setjmp.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Abstract method thunks emitted by bcc2 call the BRL.Blitz trap directly. */
void brl_blitz_NullMethodError(void);

/* Scalar BRL.Blitz intrinsics. Functions, rather than macros, preserve the
   BlitzMax rule that each argument expression is evaluated exactly once. */
#define BMX_EMBEDDED_MINMAX(type, suffix) \
    static inline type bmx_embedded_min_##suffix(type a, type b) { return a > b ? b : a; } \
    static inline type bmx_embedded_max_##suffix(type a, type b) { return a < b ? b : a; }

BMX_EMBEDDED_MINMAX(int32_t, i32)
BMX_EMBEDDED_MINMAX(int64_t, i64)
BMX_EMBEDDED_MINMAX(float, f32)
BMX_EMBEDDED_MINMAX(double, f64)
BMX_EMBEDDED_MINMAX(uint8_t, u8)
BMX_EMBEDDED_MINMAX(uint16_t, u16)
BMX_EMBEDDED_MINMAX(uint32_t, u32)
BMX_EMBEDDED_MINMAX(uint64_t, u64)
BMX_EMBEDDED_MINMAX(size_t, size)
BMX_EMBEDDED_MINMAX(long, long)
BMX_EMBEDDED_MINMAX(unsigned long, ulong)

#undef BMX_EMBEDDED_MINMAX

static inline int32_t bmx_embedded_abs_i32(int32_t value) { return value >= 0 ? value : -value; }
static inline int64_t bmx_embedded_abs_i64(int64_t value) { return value >= 0 ? value : -value; }
static inline float bmx_embedded_abs_f32(float value) { return __builtin_fabsf(value); }
static inline double bmx_embedded_abs_f64(double value) { return __builtin_fabs(value); }
static inline int32_t bmx_embedded_sgn_i32(int32_t value) { return value == 0 ? 0 : (value > 0 ? 1 : -1); }
static inline int64_t bmx_embedded_sgn_i64(int64_t value) { return value == 0 ? 0 : (value > 0 ? 1 : -1); }
static inline float bmx_embedded_sgn_f32(float value) { return value == 0 ? 0.0f : (value > 0 ? 1.0f : -1.0f); }
static inline double bmx_embedded_sgn_f64(double value) { return value == 0 ? 0.0 : (value > 0 ? 1.0 : -1.0); }

typedef struct BMXEmbeddedString {
    int32_t length;
    const uint16_t *buf;
} BMXEmbeddedString;

typedef struct BMXEmbeddedValueDescriptor BMXEmbeddedValueDescriptor;
typedef void (*BMXEmbeddedArrayInitializer)(void *element);

typedef struct BMXEmbeddedArray {
    int32_t length;
    uint32_t element_size;
    uint16_t element_kind;
    uint16_t reserved;
    BMXEmbeddedArrayInitializer initializer;
    const BMXEmbeddedValueDescriptor *element_descriptor;
} BMXEmbeddedArray;

/* Standard BlitzMax native ABI spelling retained for shared BRL code. */
typedef BMXEmbeddedArray *BBARRAY;

typedef struct BMXEmbeddedEnumDescriptor {
    const char *name;
    const uint64_t *values;
    const BMXEmbeddedString *const *names;
    uint16_t count;
    uint16_t element_size;
    uint16_t flags;
} BMXEmbeddedEnumDescriptor;

#define BMX_EMBEDDED_ENUM_FLAG_FLAGS 0x0001u

#define BMX_EMBEDDED_ARRAY_ELEMENT_VALUE 0u
#define BMX_EMBEDDED_ARRAY_ELEMENT_STRING 1u
#define BMX_EMBEDDED_ARRAY_ELEMENT_OBJECT 2u

typedef struct BMXEmbeddedValueField {
    uint32_t offset;
    uint32_t stride;
    uint32_t count;
    uint16_t kind;
    const BMXEmbeddedValueDescriptor *descriptor;
} BMXEmbeddedValueField;

struct BMXEmbeddedValueDescriptor {
    const char *name;
    uint32_t size;
    const BMXEmbeddedValueField *fields;
    uint32_t field_count;
};

#define BMX_EMBEDDED_VALUE_OBJECT 1u
#define BMX_EMBEDDED_VALUE_ARRAY 2u
#define BMX_EMBEDDED_VALUE_STRING 3u
#define BMX_EMBEDDED_VALUE_STRUCT 4u

typedef void (*BMXEmbeddedTraceVisitor)(void *reference, void *context);
typedef void (*BMXEmbeddedTraceFunction)(void *object, BMXEmbeddedTraceVisitor visitor, void *context);
typedef void (*BMXEmbeddedFinalizer)(void *object);
typedef void (*BMXEmbeddedMethod)(void);
typedef struct BMXEmbeddedInterfaceDescriptor {
    const char *name;
    const char *abi_name;
} BMXEmbeddedInterfaceDescriptor;

typedef struct BMXEmbeddedInterfaceEntry {
    const BMXEmbeddedInterfaceDescriptor *interface_type;
    const BMXEmbeddedMethod *methods;
    uint32_t method_count;
} BMXEmbeddedInterfaceEntry;
typedef int32_t (*BMXEmbeddedObjectCompare)(void *object, void *other);
typedef uint32_t (*BMXEmbeddedObjectHashCode)(void *object);
typedef int32_t (*BMXEmbeddedObjectEquals)(void *object, void *other);

typedef struct BMXEmbeddedTypeDescriptor {
    const char *name;
    const char *abi_name;
    uint32_t instance_size;
    const struct BMXEmbeddedTypeDescriptor *super;
    const BMXEmbeddedMethod *methods;
    uint32_t method_count;
    const BMXEmbeddedInterfaceEntry *interfaces;
    uint32_t interface_count;
    const uint32_t *reference_offsets;
    uint32_t reference_count;
    const uint32_t *array_offsets;
    uint32_t array_count;
    const uint32_t *string_offsets;
    uint32_t string_count;
    const BMXEmbeddedValueField *value_fields;
    uint32_t value_field_count;
    uint16_t flags;
    BMXEmbeddedTraceFunction trace;
    BMXEmbeddedFinalizer finalizer;
    BMXEmbeddedObjectCompare compare;
    BMXEmbeddedObjectHashCode hash_code;
    BMXEmbeddedObjectEquals equals;
} BMXEmbeddedTypeDescriptor;

typedef struct BMXEmbeddedObject {
    const BMXEmbeddedTypeDescriptor *type;
} BMXEmbeddedObject;

typedef struct BMXEmbeddedClosure {
    BMXEmbeddedObject object;
    BMXEmbeddedMethod invoke;
    BMXEmbeddedObject *environment;
} BMXEmbeddedClosure;

#define BMX_EMBEDDED_EXCEPTION_NONE 0u
#define BMX_EMBEDDED_EXCEPTION_OBJECT 1u
#define BMX_EMBEDDED_EXCEPTION_ARRAY 2u
#define BMX_EMBEDDED_EXCEPTION_STRING 3u

typedef struct BMXEmbeddedException {
    void *value;
    uint16_t kind;
    uint16_t reserved;
} BMXEmbeddedException;

typedef struct BMXEmbeddedRootSlot {
    void *address;
    uint16_t kind;
    const BMXEmbeddedValueDescriptor *descriptor;
} BMXEmbeddedRootSlot;

#define BMX_EMBEDDED_ROOT_OBJECT 1u
#define BMX_EMBEDDED_ROOT_ARRAY 2u
#define BMX_EMBEDDED_ROOT_STRING 3u
#define BMX_EMBEDDED_ROOT_STRUCT 4u
#define BMX_EMBEDDED_ROOT_EXCEPTION 5u

typedef struct BMXEmbeddedRootFrame {
    struct BMXEmbeddedRootFrame *previous;
    BMXEmbeddedRootSlot *slots;
    uint16_t slot_count;
} BMXEmbeddedRootFrame;

typedef struct BMXEmbeddedExceptionFrame {
    struct BMXEmbeddedExceptionFrame *previous;
    BMXEmbeddedRootFrame *root_snapshot;
    uint32_t root_frame_count;
    uint32_t root_slot_count;
    jmp_buf buffer;
} BMXEmbeddedExceptionFrame;

#define BMX_EMBEDDED_TYPE_FLAG_CUSTOM_TRACE 0x0001u
#define BMX_EMBEDDED_TYPE_FLAG_HAS_FINALIZER 0x0002u

extern const BMXEmbeddedString bmx_embedded_empty_string;
extern BMXEmbeddedArray bmx_embedded_empty_array;
extern BMXEmbeddedObject bmx_embedded_null_object;

int32_t bmx_embedded_object_is_string(BMXEmbeddedObject *value);

int32_t bmx_embedded_string_compare(const BMXEmbeddedString *left, const BMXEmbeddedString *right);
int32_t bmx_embedded_string_equals(const BMXEmbeddedString *left, const BMXEmbeddedString *right);
uint32_t bmx_embedded_string_hash(const BMXEmbeddedString *text);
int32_t bmx_embedded_string_compare_case(const BMXEmbeddedString *left, const BMXEmbeddedString *right, int32_t case_sensitive);
int32_t bmx_embedded_string_equals_case(const BMXEmbeddedString *left, const BMXEmbeddedString *right, int32_t case_sensitive);
uint32_t bmx_embedded_string_hash_case(const BMXEmbeddedString *text, int32_t case_sensitive);
typedef const BMXEmbeddedString *(*BMXEmbeddedStringCaseTransform)(const BMXEmbeddedString *text);
typedef uint16_t (*BMXEmbeddedCharacterCaseFold)(uint16_t character);
void bmx_embedded_string_install_unicode_case(BMXEmbeddedStringCaseTransform lower,
    BMXEmbeddedStringCaseTransform upper, BMXEmbeddedCharacterCaseFold fold);
uint16_t bmx_embedded_string_fold_character(uint16_t character);
const BMXEmbeddedString *bmx_embedded_string_to_string(const BMXEmbeddedString *text);
int32_t bmx_embedded_string_find(const BMXEmbeddedString *text, const BMXEmbeddedString *substring, int32_t start);
int32_t bmx_embedded_string_find_last(const BMXEmbeddedString *text, const BMXEmbeddedString *substring, int32_t start);
const BMXEmbeddedString *bmx_embedded_string_trim(const BMXEmbeddedString *text);
const BMXEmbeddedString *bmx_embedded_string_replace(const BMXEmbeddedString *text, const BMXEmbeddedString *substring, const BMXEmbeddedString *replacement);
const BMXEmbeddedString *bmx_embedded_string_to_lower(const BMXEmbeddedString *text);
const BMXEmbeddedString *bmx_embedded_string_to_upper(const BMXEmbeddedString *text);
int32_t bmx_embedded_string_starts_with(const BMXEmbeddedString *text, const BMXEmbeddedString *substring);
int32_t bmx_embedded_string_ends_with(const BMXEmbeddedString *text, const BMXEmbeddedString *substring);
int32_t bmx_embedded_string_contains(const BMXEmbeddedString *text, const BMXEmbeddedString *substring);
const BMXEmbeddedString *bmx_embedded_string_replicate(const BMXEmbeddedString *text, int32_t count);
BMXEmbeddedArray *bmx_embedded_string_split(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
const BMXEmbeddedString *bmx_embedded_string_join(const BMXEmbeddedString *separator, BMXEmbeddedArray *parts);
const BMXEmbeddedString *bmx_embedded_string_from_bytes(const uint8_t *bytes, int32_t count);
const BMXEmbeddedString *bmx_embedded_string_from_shorts(const uint16_t *characters, int32_t count);
const BMXEmbeddedString *bmx_embedded_string_from_c_string(const uint8_t *bytes);
const BMXEmbeddedString *bmx_embedded_string_from_w_string(const uint16_t *characters);
const BMXEmbeddedString *bmx_embedded_string_from_ascii(const char *bytes, int32_t count);
const BMXEmbeddedString *bmx_embedded_string_from_utf8_string(const uint8_t *bytes);
const BMXEmbeddedString *bmx_embedded_string_from_utf8_bytes(const uint8_t *bytes, int32_t count);
uint8_t *bmx_embedded_string_to_c_string(const BMXEmbeddedString *text);
uint16_t *bmx_embedded_string_to_w_string(const BMXEmbeddedString *text);
uint16_t *bmx_embedded_string_to_w_string_buffer(const BMXEmbeddedString *text, uint16_t *buffer, size_t *length);
uint8_t *bmx_embedded_string_to_utf8_string(const BMXEmbeddedString *text);
uint8_t *bmx_embedded_string_to_utf8_string_len(const BMXEmbeddedString *text, size_t *length);
uint8_t *bmx_embedded_string_to_utf8_string_buffer(const BMXEmbeddedString *text, uint8_t *buffer, size_t *length);
uint32_t *bmx_embedded_string_to_utf32_string(const BMXEmbeddedString *text);
const BMXEmbeddedString *bmx_embedded_string_from_utf32_string(const uint32_t *characters);
const BMXEmbeddedString *bmx_embedded_string_from_utf32_bytes(const uint32_t *characters, size_t count);
const BMXEmbeddedString *bmx_embedded_string_from_bytes_as_hex(const uint8_t *bytes, int32_t length, int32_t upper_case);
int32_t bmx_embedded_string_to_bytes_from_hex(const BMXEmbeddedString *text, uint8_t *bytes, int32_t length);
int32_t bmx_embedded_string_to_bytes_from_hex_ex(const BMXEmbeddedString *text, int32_t offset, int32_t count, uint8_t *bytes, int32_t length);
const BMXEmbeddedString *bmx_embedded_stream_url_string(BMXEmbeddedObject *value);
const BMXEmbeddedString *bmx_embedded_string_concat(const BMXEmbeddedString *left, const BMXEmbeddedString *right);
const BMXEmbeddedString *bmx_embedded_string_slice(const BMXEmbeddedString *text, int32_t begin, int32_t end);
const BMXEmbeddedString *bmx_embedded_string_from_char(int32_t character);
int32_t bmx_embedded_string_asc(const BMXEmbeddedString *text);
void bmx_embedded_debug_stop(void);
void bmx_embedded_delay(int32_t milliseconds);
void bmx_embedded_udelay(int32_t microseconds);
uint32_t bmx_embedded_string_failure_count(void);
uint32_t bmx_embedded_string_allocation_count(void);
uint32_t bmx_embedded_string_allocated_bytes(void);
uint32_t bmx_embedded_string_live_count(void);
uint32_t bmx_embedded_string_live_bytes(void);
uint32_t bmx_embedded_reachable_string_count(void);
uint32_t bmx_embedded_unreachable_string_count(void);

const BMXEmbeddedString *bmx_embedded_string_from_int32(int32_t value);
const BMXEmbeddedString *bmx_embedded_string_from_uint32(uint32_t value);
const BMXEmbeddedString *bmx_embedded_string_from_int64(int64_t value);
const BMXEmbeddedString *bmx_embedded_string_from_uint64(uint64_t value);
const BMXEmbeddedString *bmx_embedded_string_from_size(size_t value);
const BMXEmbeddedString *bmx_embedded_string_from_long(long value);
const BMXEmbeddedString *bmx_embedded_string_from_ulong(unsigned long value);
BMXEmbeddedString *bmx_embedded_string_allocate(int32_t length);
int32_t bmx_embedded_string_to_int32(const BMXEmbeddedString *text);
uint32_t bmx_embedded_string_to_uint32(const BMXEmbeddedString *text);
int64_t bmx_embedded_string_to_int64(const BMXEmbeddedString *text);
uint64_t bmx_embedded_string_to_uint64(const BMXEmbeddedString *text);
size_t bmx_embedded_string_to_size(const BMXEmbeddedString *text);
long bmx_embedded_string_to_long(const BMXEmbeddedString *text);
unsigned long bmx_embedded_string_to_ulong(const BMXEmbeddedString *text);
BMXEmbeddedArray *bmx_embedded_string_split_ints(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
BMXEmbeddedArray *bmx_embedded_string_split_bytes(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
BMXEmbeddedArray *bmx_embedded_string_split_shorts(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
BMXEmbeddedArray *bmx_embedded_string_split_uints(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
BMXEmbeddedArray *bmx_embedded_string_split_longs(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
BMXEmbeddedArray *bmx_embedded_string_split_ulongs(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
BMXEmbeddedArray *bmx_embedded_string_split_sizes(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
BMXEmbeddedArray *bmx_embedded_string_split_long_ints(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
BMXEmbeddedArray *bmx_embedded_string_split_ulong_ints(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
const BMXEmbeddedString *bmx_embedded_string_join_ints(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_bytes(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_shorts(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_uints(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_longs(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_ulongs(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_sizes(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_long_ints(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_ulong_ints(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
BMXEmbeddedArray *bmx_embedded_string_split_floats(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
BMXEmbeddedArray *bmx_embedded_string_split_doubles(const BMXEmbeddedString *text, const BMXEmbeddedString *separator);
const BMXEmbeddedString *bmx_embedded_string_join_floats_default(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_floats_fixed(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_doubles_default(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
const BMXEmbeddedString *bmx_embedded_string_join_doubles_fixed(const BMXEmbeddedString *separator, BMXEmbeddedArray *values);
static inline const BMXEmbeddedString *bmx_embedded_string_join_floats(const BMXEmbeddedString *separator,
    BMXEmbeddedArray *values, int32_t fixed) {
    return fixed ? bmx_embedded_string_join_floats_fixed(separator, values) :
        bmx_embedded_string_join_floats_default(separator, values);
}
static inline const BMXEmbeddedString *bmx_embedded_string_join_doubles(const BMXEmbeddedString *separator,
    BMXEmbeddedArray *values, int32_t fixed) {
    return fixed ? bmx_embedded_string_join_doubles_fixed(separator, values) :
        bmx_embedded_string_join_doubles_default(separator, values);
}
const BMXEmbeddedString *bmx_embedded_string_from_float_default(float value);
const BMXEmbeddedString *bmx_embedded_string_from_double_default(double value);
const BMXEmbeddedString *bmx_embedded_string_from_float_fixed(float value);
const BMXEmbeddedString *bmx_embedded_string_from_double_fixed(double value);
static inline const BMXEmbeddedString *bmx_embedded_string_from_float(float value, int32_t fixed) {
    return fixed ? bmx_embedded_string_from_float_fixed(value) : bmx_embedded_string_from_float_default(value);
}
static inline const BMXEmbeddedString *bmx_embedded_string_from_double(double value, int32_t fixed) {
    return fixed ? bmx_embedded_string_from_double_fixed(value) : bmx_embedded_string_from_double_default(value);
}
float bmx_embedded_string_to_float(const BMXEmbeddedString *text);
double bmx_embedded_string_to_double(const BMXEmbeddedString *text);

BMXEmbeddedArray *bmx_embedded_enum_values(const BMXEmbeddedEnumDescriptor *descriptor);
const BMXEmbeddedString *bmx_embedded_enum_to_string(const BMXEmbeddedEnumDescriptor *descriptor, uint64_t value);
int32_t bmx_embedded_enum_try_convert(const BMXEmbeddedEnumDescriptor *descriptor, uint64_t value, void *result);
uint64_t bmx_embedded_enum_from_string(const BMXEmbeddedEnumDescriptor *descriptor, const BMXEmbeddedString *name);
uint32_t bmx_embedded_enum_failure_count(void);

BMXEmbeddedArray *bmx_embedded_array_new_1d(int32_t length, uint32_t element_size, uint16_t element_kind, BMXEmbeddedArrayInitializer initializer, const BMXEmbeddedValueDescriptor *element_descriptor);
BMXEmbeddedArray *bmx_embedded_array_from_data(int32_t length, uint32_t element_size, uint16_t element_kind, BMXEmbeddedArrayInitializer initializer, const BMXEmbeddedValueDescriptor *element_descriptor, const void *data);
BMXEmbeddedArray *bmx_embedded_array_concat(BMXEmbeddedArray *left, BMXEmbeddedArray *right);
void bbArrayCopy(BBARRAY src, int src_pos, BBARRAY dst, int dst_pos, int length);
BMXEmbeddedArray *bmx_embedded_array_slice(BMXEmbeddedArray *array, int32_t begin, int32_t end,
    uint32_t element_size, uint16_t element_kind, BMXEmbeddedArrayInitializer initializer,
    const BMXEmbeddedValueDescriptor *element_descriptor);
void *bmx_embedded_array_element(BMXEmbeddedArray *array, int32_t index, uint32_t element_size);
void *bmx_embedded_array_data(BMXEmbeddedArray *array);

void *bbMemAlloc(size_t size);
void bbMemFree(void *memory);
void *bbMemExtend(void *memory, size_t size, size_t new_size);
void *bbMemAllocCollectable(size_t size);
void bbMemFreeCollectable(void *memory);
void *bbMemExtendCollectable(void *memory, size_t size, size_t new_size);
void bbMemClear(void *memory, size_t size);
void bbMemCopy(void *destination, const void *source, size_t size);
void bbMemMove(void *destination, const void *source, size_t size);

int32_t bbIncbinAdd(const BMXEmbeddedString *path, const void *data, int32_t size);
void *bbIncbinPtr(const BMXEmbeddedString *path);
int32_t bbIncbinLen(const BMXEmbeddedString *path);

void *brl_blitz_MemAlloc__Bsize_t__Bint(size_t size, int32_t collectable);
void brl_blitz_MemFree__PBbyte__Bint(void *memory, int32_t collectable);
void *brl_blitz_MemExtend__PBbyte__Bsize_t__Bsize_t__Bint(void *memory, size_t size, size_t new_size, int32_t collectable);
uint32_t bmx_embedded_array_failure_count(void);
uint32_t bmx_embedded_array_allocation_count(void);
uint32_t bmx_embedded_array_allocated_bytes(void);
uint32_t bmx_embedded_array_live_count(void);
uint32_t bmx_embedded_array_live_bytes(void);
uint32_t bmx_embedded_reachable_array_count(void);
uint32_t bmx_embedded_unreachable_array_count(void);

void *bmx_embedded_object_allocate(const BMXEmbeddedTypeDescriptor *type);
void *bmx_embedded_object_assert(void *object);
void *bmx_embedded_object_null_failure(void);
static inline void *bmx_embedded_object_not_null(void *object) {
    if (!object || object == &bmx_embedded_null_object) return bmx_embedded_object_null_failure();
    return object;
}
int32_t bmx_embedded_object_compare(void *object, void *other);
uint32_t bmx_embedded_object_hash_code(void *object);
int32_t bmx_embedded_object_equals(void *object, void *other);
void *bmx_embedded_object_cast(void *object, const BMXEmbeddedTypeDescriptor *target);
const BMXEmbeddedMethod *bmx_embedded_type_methods(void *object, const BMXEmbeddedTypeDescriptor *target, uint32_t method_count);
void *bmx_embedded_interface_cast(void *object, const BMXEmbeddedInterfaceDescriptor *target);
const BMXEmbeddedMethod *bmx_embedded_interface_methods(void *object, const BMXEmbeddedInterfaceDescriptor *target, uint32_t method_count);
BMXEmbeddedClosure *bmx_embedded_closure_allocate(BMXEmbeddedMethod invoke, BMXEmbeddedObject *environment);
BMXEmbeddedClosure *bmx_embedded_closure_assert(void *closure);
uint32_t bmx_embedded_object_failure_count(void);
uint32_t bmx_embedded_object_allocation_count(void);
uint32_t bmx_embedded_object_allocated_bytes(void);
uint32_t bmx_embedded_object_live_count(void);
uint32_t bmx_embedded_object_live_bytes(void);
uint32_t bmx_embedded_object_root_retain(BMXEmbeddedObject *object);
void bmx_embedded_object_root_release(uint32_t token);
uint32_t bmx_embedded_object_root_count(void);
uint32_t bmx_embedded_reachability_audit(void);
uint32_t bmx_embedded_reachable_object_count(void);
uint32_t bmx_embedded_unreachable_object_count(void);
uint32_t bmx_embedded_invalid_reference_count(void);
uint32_t bmx_embedded_collect_objects(void);
uint32_t bmx_embedded_collection_count(void);
uint32_t bmx_embedded_automatic_collection_count(void);
uint32_t bmx_embedded_last_reclaimed_object_count(void);
uint32_t bmx_embedded_last_reclaimed_bytes(void);
uint32_t bmx_embedded_last_reclaimed_array_count(void);
uint32_t bmx_embedded_last_reclaimed_array_bytes(void);
uint32_t bmx_embedded_last_reclaimed_string_count(void);
uint32_t bmx_embedded_last_reclaimed_string_bytes(void);
uint32_t bmx_embedded_finalizer_pending_count(void);
uint32_t bmx_embedded_finalizer_invocation_count(void);
uint32_t bmx_embedded_last_finalized_object_count(void);
uint32_t bmx_embedded_heap_reusable_bytes(void);
uint32_t bmx_embedded_heap_largest_free_block(void);
void bmx_embedded_root_frame_enter(BMXEmbeddedRootFrame *frame, BMXEmbeddedRootSlot *slots, uint16_t slot_count);
void bmx_embedded_root_frame_leave(BMXEmbeddedRootFrame *frame);
uint32_t bmx_embedded_root_frame_count(void);
uint32_t bmx_embedded_root_slot_count(void);
void bmx_embedded_exception_enter(BMXEmbeddedExceptionFrame *frame);
void bmx_embedded_exception_leave(void);
BMXEmbeddedException bmx_embedded_exception_object(BMXEmbeddedObject *value);
BMXEmbeddedException bmx_embedded_exception_array(BMXEmbeddedArray *value);
BMXEmbeddedException bmx_embedded_exception_string(const BMXEmbeddedString *value);
BMXEmbeddedException bmx_embedded_exception_catch(void);
void bmx_embedded_exception_throw(BMXEmbeddedException exception);
uint32_t bmx_embedded_exception_depth(void);
uint32_t bmx_embedded_exception_throw_count(void);
uint32_t bmx_embedded_exception_catch_count(void);
uint32_t bmx_embedded_exception_max_depth(void);
uint32_t bmx_embedded_exception_unhandled_count(void);

void *bmx_embedded_arena_allocate(uint32_t bytes);
uint32_t bmx_embedded_arena_capacity(void);
uint32_t bmx_embedded_arena_used(void);
uint32_t bmx_embedded_arena_remaining(void);
uint32_t bmx_embedded_arena_high_water(void);
uint32_t bmx_embedded_arena_allocation_count(void);
uint32_t bmx_embedded_arena_failure_count(void);
#ifdef __cplusplus
}
#endif

#endif
