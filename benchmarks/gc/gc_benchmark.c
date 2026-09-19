#include <stdint.h>

#ifndef BMX_EMBEDDED_MULTICORE
#define BMX_EMBEDDED_MULTICORE 0
#endif

int32_t bmx_embedded_benchmark_multicore(void) { return BMX_EMBEDDED_MULTICORE; }
