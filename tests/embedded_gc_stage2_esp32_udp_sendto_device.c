#include <stdatomic.h>
#include <stdint.h>

static atomic_int udp_sendto_target_port;
static const char udp_sendto_loopback_address[] = "127.0.0.1";

void bmx_stage2_sendto_set_port(int32_t port) {
    atomic_store_explicit(&udp_sendto_target_port, port, memory_order_release);
}

int32_t bmx_stage2_sendto_get_port(void) {
    return atomic_load_explicit(&udp_sendto_target_port, memory_order_acquire);
}

const char *bmx_stage2_sendto_loopback_address(void) {
    return udp_sendto_loopback_address;
}
