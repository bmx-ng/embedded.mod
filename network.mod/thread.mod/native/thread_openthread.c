/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#if defined(ESP_PLATFORM)
#include "sdkconfig.h"
#endif

#include <openthread/dataset.h>
#include <openthread/dataset_ftd.h>
#include <openthread/commissioner.h>
#include <openthread/instance.h>
#include <openthread/ip6.h>
#include <openthread/joiner.h>
#include <openthread/link.h>
#include <openthread/message.h>
#include <openthread/thread.h>
#include <openthread/udp.h>

extern int bmx_thread_platform_initialize(void);
extern otInstance *bmx_thread_platform_instance(void);
extern void bmx_thread_platform_lock(void);
extern void bmx_thread_platform_unlock(void);

#define BMX_THREAD_UDP_PAYLOAD 1280
#define BMX_THREAD_UDP_QUEUE 16
#define BMX_THREAD_UDP_SOCKETS 8
#define BMX_THREAD_UDP_LEGACY_QUEUE 8

typedef struct {
    uint8_t *data;
    uint16_t length;
    uint16_t port;
    otIp6Address address;
} BMXThreadDatagram;

static otUdpSocket bmx_udp_socket;
static int bmx_udp_open;
static BMXThreadDatagram bmx_udp_queue[BMX_THREAD_UDP_LEGACY_QUEUE];
static unsigned bmx_udp_head, bmx_udp_count, bmx_udp_dropped;
typedef struct {
    otUdpSocket socket;
    BMXThreadDatagram queue[BMX_THREAD_UDP_QUEUE];
    unsigned head, count, dropped;
    unsigned queue_depth;
    unsigned max_datagram;
    unsigned generation;
    int open;
} BMXThreadUdpEndpoint;
static BMXThreadUdpEndpoint bmx_udp_endpoints[BMX_THREAD_UDP_SOCKETS];

static void bmx_udp_clear_queue(BMXThreadDatagram *queue, unsigned *head,
                                unsigned *count, unsigned capacity) {
    while (*count) {
        BMXThreadDatagram *item = &queue[*head];
        free(item->data);
        item->data = NULL;
        *head = (*head + 1) % capacity;
        --*count;
    }
    *head = 0;
}

static int bmx_udp_store(BMXThreadDatagram *item, otMessage *message,
                         const otMessageInfo *info, int length) {
    uint8_t *bytes = NULL;
    if (length) {
        bytes = malloc((size_t)length);
        if (!bytes) return 0;
        if (otMessageRead(message, otMessageGetOffset(message), bytes,
                          (uint16_t)length) != length) {
            free(bytes);
            return 0;
        }
    }
    item->data = bytes;
    item->length = (uint16_t)length;
    item->port = info->mPeerPort;
    item->address = info->mPeerAddr;
    return 1;
}
#if defined(CONFIG_OPENTHREAD_JOINER) && CONFIG_OPENTHREAD_JOINER
static int bmx_joiner_status = -61;
static int bmx_joiner_completed;
#endif

static int bmx_hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

#if (defined(CONFIG_OPENTHREAD_JOINER) && CONFIG_OPENTHREAD_JOINER) || \
    (defined(CONFIG_OPENTHREAD_COMMISSIONER) && CONFIG_OPENTHREAD_COMMISSIONER)
static int bmx_valid_pskd(const char *pskd) {
    if (!pskd) return 0;
    size_t length = strlen(pskd);
    if (length < 6 || length > 32) return 0;
    for (size_t i = 0; i < length; ++i) {
        char c = pskd[i];
        if (c >= '0' && c <= '9') continue;
        if (c < 'A' || c > 'Z' || c == 'I' || c == 'O' || c == 'Q' || c == 'Z') return 0;
    }
    return 1;
}
#endif

#if defined(CONFIG_OPENTHREAD_JOINER) && CONFIG_OPENTHREAD_JOINER
static void bmx_joiner_finished(otError error, void *context) {
    (void)context;
    bmx_joiner_status = error ? -(int)error : 0;
    bmx_joiner_completed = 1;
}
#endif

static void bmx_udp_received(void *context, otMessage *message, const otMessageInfo *info) {
    (void)context;
    int length = otMessageGetLength(message) - otMessageGetOffset(message);
    if (length < 0 || length > BMX_THREAD_UDP_PAYLOAD ||
        bmx_udp_count == BMX_THREAD_UDP_LEGACY_QUEUE) {
        ++bmx_udp_dropped;
        return;
    }
    BMXThreadDatagram *item = &bmx_udp_queue[(bmx_udp_head + bmx_udp_count) % BMX_THREAD_UDP_LEGACY_QUEUE];
    if (!bmx_udp_store(item, message, info, length)) {
        ++bmx_udp_dropped;
        return;
    }
    ++bmx_udp_count;
}

static BMXThreadUdpEndpoint *bmx_udp_endpoint(int handle) {
    unsigned slot = (unsigned)handle & 0xffu;
    unsigned generation = (unsigned)handle >> 8;
    if (!slot || slot > BMX_THREAD_UDP_SOCKETS || !generation) return NULL;
    BMXThreadUdpEndpoint *endpoint = &bmx_udp_endpoints[slot - 1];
    return endpoint->open && endpoint->generation == generation ? endpoint : NULL;
}

static void bmx_udp_endpoint_received(void *context, otMessage *message, const otMessageInfo *info) {
    BMXThreadUdpEndpoint *endpoint = context;
    int length = otMessageGetLength(message) - otMessageGetOffset(message);
    if (length < 0 || length > (int)endpoint->max_datagram ||
        endpoint->count == endpoint->queue_depth) {
        ++endpoint->dropped;
        return;
    }
    BMXThreadDatagram *item = &endpoint->queue[(endpoint->head + endpoint->count) % endpoint->queue_depth];
    if (!bmx_udp_store(item, message, info, length)) {
        ++endpoint->dropped;
        return;
    }
    ++endpoint->count;
}

int bmx_thread_initialize(void) {
    return bmx_thread_platform_initialize();
}

int bmx_thread_start_saved(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otInstance *instance = bmx_thread_platform_instance();
    otOperationalDatasetTlvs dataset;
    otError error = otDatasetGetActiveTlvs(instance, &dataset);
    if (error == OT_ERROR_NOT_FOUND) {
        bmx_thread_platform_unlock();
        return -61;
    }
    if (!error) error = otIp6SetEnabled(instance, true);
    if (!error) error = otThreadSetEnabled(instance, true);
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_form(const char *name, int channel) {
    if (!name || strlen(name) == 0 || strlen(name) > OT_NETWORK_NAME_MAX_SIZE ||
            channel < 11 || channel > 26) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otInstance *instance = bmx_thread_platform_instance();
    otOperationalDataset dataset;
    otError error = otThreadSetEnabled(instance, false);
    if (!error) error = otIp6SetEnabled(instance, false);
    if (!error) error = otDatasetCreateNewNetwork(instance, &dataset);
    if (!error) error = otNetworkNameFromString(&dataset.mNetworkName, name);
    if (!error) {
        dataset.mChannel = (uint16_t)channel;
        dataset.mComponents.mIsChannelPresent = true;
        error = otDatasetSetActive(instance, &dataset);
    }
    if (!error) error = otIp6SetEnabled(instance, true);
    if (!error) error = otThreadSetEnabled(instance, true);
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_join(const char *hex) {
    if (!hex) return -22;
    size_t length = strlen(hex);
    if (!length || (length & 1) || length > OT_OPERATIONAL_DATASET_MAX_LENGTH * 2) return -22;
    otOperationalDatasetTlvs dataset = {0};
    dataset.mLength = length / 2;
    for (size_t i = 0; i < dataset.mLength; ++i) {
        int high = bmx_hex_digit(hex[i * 2]);
        int low = bmx_hex_digit(hex[i * 2 + 1]);
        if (high < 0 || low < 0) return -22;
        dataset.mTlvs[i] = (uint8_t)((high << 4) | low);
    }
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otInstance *instance = bmx_thread_platform_instance();
    otError error = otThreadSetEnabled(instance, false);
    if (!error) error = otIp6SetEnabled(instance, false);
    if (!error) error = otDatasetSetActiveTlvs(instance, &dataset);
    if (!error) error = otIp6SetEnabled(instance, true);
    if (!error) error = otThreadSetEnabled(instance, true);
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_leave(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otInstance *instance = bmx_thread_platform_instance();
    otError error = otThreadSetEnabled(instance, false);
    if (!error) error = otIp6SetEnabled(instance, false);
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_forget(void) {
    int result = bmx_thread_leave();
    if (result) return result;
    bmx_thread_platform_lock();
    otInstance *instance = bmx_thread_platform_instance();
#if defined(CONFIG_OPENTHREAD_JOINER) && CONFIG_OPENTHREAD_JOINER
    otJoinerStop(instance);
#endif
    otError error = otInstanceErasePersistentInfo(instance);
#if defined(CONFIG_OPENTHREAD_JOINER) && CONFIG_OPENTHREAD_JOINER
    bmx_joiner_status = -61;
    bmx_joiner_completed = 0;
#endif
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_factory_eui64(char *value, int capacity) {
    if (!value || capacity < 17) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otExtAddress eui;
    otLinkGetFactoryAssignedIeeeEui64(bmx_thread_platform_instance(), &eui);
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < 8; ++i) {
        value[i * 2] = hex[eui.m8[i] >> 4];
        value[i * 2 + 1] = hex[eui.m8[i] & 15];
    }
    value[16] = 0;
    bmx_thread_platform_unlock();
    return 16;
}

#if defined(CONFIG_OPENTHREAD_COMMISSIONER) && CONFIG_OPENTHREAD_COMMISSIONER
int bmx_thread_commissioner_start(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otError error = otCommissionerStart(bmx_thread_platform_instance(), NULL, NULL, NULL);
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_commissioner_state(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int state = (int)otCommissionerGetState(bmx_thread_platform_instance());
    bmx_thread_platform_unlock();
    return state;
}

int bmx_thread_commissioner_add_joiner(const char *eui64, const char *pskd, uint32_t timeout) {
    if (!eui64 || !bmx_valid_pskd(pskd) || !timeout) return -22;
    otExtAddress eui;
    const otExtAddress *selected = NULL;
    if (*eui64) {
        if (strlen(eui64) != 16) return -22;
        for (int i = 0; i < 8; ++i) {
            int high = bmx_hex_digit(eui64[i * 2]);
            int low = bmx_hex_digit(eui64[i * 2 + 1]);
            if (high < 0 || low < 0) return -22;
            eui.m8[i] = (uint8_t)((high << 4) | low);
        }
        selected = &eui;
    }
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otError error = otCommissionerAddJoiner(bmx_thread_platform_instance(), selected, pskd, timeout);
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_commissioner_stop(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otError error = otCommissionerStop(bmx_thread_platform_instance());
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}
#endif

#if defined(CONFIG_OPENTHREAD_JOINER) && CONFIG_OPENTHREAD_JOINER
int bmx_thread_joiner_start(const char *pskd) {
    if (!bmx_valid_pskd(pskd)) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otInstance *instance = bmx_thread_platform_instance();
    otError error = otThreadSetEnabled(instance, false);
    if (!error) error = otIp6SetEnabled(instance, true);
    if (!error) {
        bmx_joiner_status = 1;
        bmx_joiner_completed = 0;
        error = otJoinerStart(instance, pskd, NULL, NULL, NULL, NULL, NULL, bmx_joiner_finished, NULL);
        if (error) bmx_joiner_status = -(int)error;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_joiner_status(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_joiner_completed && bmx_joiner_status == 0) {
        otError error = otThreadSetEnabled(bmx_thread_platform_instance(), true);
        if (error) bmx_joiner_status = -(int)error;
        bmx_joiner_completed = 0;
    }
    int status = bmx_joiner_status;
    bmx_thread_platform_unlock();
    return status;
}

int bmx_thread_joiner_stop(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otJoinerStop(bmx_thread_platform_instance());
    bmx_joiner_status = -61;
    bmx_joiner_completed = 0;
    bmx_thread_platform_unlock();
    return 0;
}
#endif

int bmx_thread_role(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int role = (int)otThreadGetDeviceRole(bmx_thread_platform_instance());
    bmx_thread_platform_unlock();
    return role;
}

int bmx_thread_address(int index, char *value, int capacity) {
    if (index < 0 || !value || capacity < OT_IP6_ADDRESS_STRING_SIZE) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    const otNetifAddress *item = otIp6GetUnicastAddresses(bmx_thread_platform_instance());
    while (item && index--) item = item->mNext;
    if (!item) {
        bmx_thread_platform_unlock();
        return 0;
    }
    otIp6AddressToString(&item->mAddress, value, (uint16_t)capacity);
    int length = strlen(value);
    bmx_thread_platform_unlock();
    return length;
}

int bmx_thread_dataset(char *value, int capacity) {
    if (!value || capacity < OT_OPERATIONAL_DATASET_MAX_LENGTH * 2 + 1) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otOperationalDatasetTlvs dataset;
    otError error = otDatasetGetActiveTlvs(bmx_thread_platform_instance(), &dataset);
    if (!error) {
        static const char digits[] = "0123456789abcdef";
        for (unsigned i = 0; i < dataset.mLength; ++i) {
            value[i * 2] = digits[dataset.mTlvs[i] >> 4];
            value[i * 2 + 1] = digits[dataset.mTlvs[i] & 15];
        }
        value[dataset.mLength * 2] = 0;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : dataset.mLength * 2;
}

int bmx_thread_udp_open(int port) {
    if (port < 1 || port > 65535) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_udp_open) {
        bmx_thread_platform_unlock();
        return -16;
    }
    otInstance *instance = bmx_thread_platform_instance();
    memset(&bmx_udp_socket, 0, sizeof(bmx_udp_socket));
    otError error = otUdpOpen(instance, &bmx_udp_socket, bmx_udp_received, NULL);
    if (!error) {
        otSockAddr local = {0};
        local.mPort = (uint16_t)port;
        error = otUdpBind(instance, &bmx_udp_socket, &local, OT_NETIF_THREAD_INTERNAL);
        if (error) otUdpClose(instance, &bmx_udp_socket);
    }
    if (!error) {
        bmx_udp_open = 1;
        bmx_udp_head = bmx_udp_count = bmx_udp_dropped = 0;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_udp_close(void) {
    if (!bmx_udp_open) return 0;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otError error = otUdpClose(bmx_thread_platform_instance(), &bmx_udp_socket);
    if (!error) {
        bmx_udp_clear_queue(bmx_udp_queue, &bmx_udp_head, &bmx_udp_count,
                            BMX_THREAD_UDP_LEGACY_QUEUE);
        bmx_udp_open = 0;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_udp_send(const char *address, int port, const uint8_t *data, int length) {
    if (!address || !data || port < 1 || port > 65535 || length < 0 || length > BMX_THREAD_UDP_PAYLOAD) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (!bmx_udp_open) {
        bmx_thread_platform_unlock();
        return -107;
    }
    otInstance *instance = bmx_thread_platform_instance();
    otMessageInfo info = {0};
    info.mPeerPort = (uint16_t)port;
    otError error = otIp6AddressFromString(address, &info.mPeerAddr);
    otMessage *message = NULL;
    if (!error) {
        message = otUdpNewMessage(instance, NULL);
        if (!message) error = OT_ERROR_NO_BUFS;
    }
    if (!error) error = otMessageAppend(message, data, (uint16_t)length);
    if (!error) error = otUdpSend(instance, &bmx_udp_socket, message, &info);
    if (error && message) otMessageFree(message);
    bmx_thread_platform_unlock();
    return error ? -(int)error : length;
}

int bmx_thread_udp_receive(uint8_t *data, int capacity, char *address, int address_capacity, int *port) {
    if (!data || capacity < 0 || !address || address_capacity < OT_IP6_ADDRESS_STRING_SIZE || !port) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (!bmx_udp_count) {
        bmx_thread_platform_unlock();
        return -11;
    }
    BMXThreadDatagram *item = &bmx_udp_queue[bmx_udp_head];
    if (capacity < item->length) {
        bmx_thread_platform_unlock();
        return -90;
    }
    if (item->length) memcpy(data, item->data, item->length);
    otIp6AddressToString(&item->address, address, (uint16_t)address_capacity);
    *port = item->port;
    int length = item->length;
    free(item->data);
    item->data = NULL;
    bmx_udp_head = (bmx_udp_head + 1) % BMX_THREAD_UDP_LEGACY_QUEUE;
    --bmx_udp_count;
    bmx_thread_platform_unlock();
    return length;
}

uint32_t bmx_thread_udp_dropped(void) {
    if (bmx_thread_initialize()) return 0;
    bmx_thread_platform_lock();
    uint32_t count = bmx_udp_dropped;
    bmx_thread_platform_unlock();
    return count;
}

/* Handles encode a slot and generation, so a closed BlitzMax object cannot use
 * a subsequently opened socket in the same slot. */
int bmx_thread_udp_socket_open_ex(int port, int netif, int queue_depth, int max_datagram) {
    if (port < 0 || port > 65535 || netif < 0 || netif > 1 ||
        queue_depth < 1 || queue_depth > BMX_THREAD_UDP_QUEUE ||
        max_datagram < 1 || max_datagram > BMX_THREAD_UDP_PAYLOAD) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    unsigned i;
    for (i = 0; i < BMX_THREAD_UDP_SOCKETS && bmx_udp_endpoints[i].open; ++i) {}
    if (i == BMX_THREAD_UDP_SOCKETS) {
        bmx_thread_platform_unlock();
        return -24;
    }
    BMXThreadUdpEndpoint *endpoint = &bmx_udp_endpoints[i];
    endpoint->queue_depth = (unsigned)queue_depth;
    endpoint->max_datagram = (unsigned)max_datagram;
    memset(&endpoint->socket, 0, sizeof(endpoint->socket));
    otInstance *instance = bmx_thread_platform_instance();
    otError error = otUdpOpen(instance, &endpoint->socket, bmx_udp_endpoint_received, endpoint);
    if (!error) {
        otSockAddr local = {0};
        local.mPort = (uint16_t)port;
        error = otUdpBind(instance, &endpoint->socket, &local,
                          netif == 1 ? OT_NETIF_UNSPECIFIED : OT_NETIF_THREAD_INTERNAL);
        if (error) otUdpClose(instance, &endpoint->socket);
    }
    int handle = -(int)error;
    if (!error) {
        endpoint->head = endpoint->count = endpoint->dropped = 0;
        endpoint->generation = (endpoint->generation + 1) & 0x7fffff;
        if (!endpoint->generation) endpoint->generation = 1;
        endpoint->open = 1;
        handle = (int)((endpoint->generation << 8) | (i + 1));
    }
    bmx_thread_platform_unlock();
    return handle;
}

int bmx_thread_udp_socket_open(int port, int netif) {
    return bmx_thread_udp_socket_open_ex(port, netif, 8, BMX_THREAD_UDP_PAYLOAD);
}

int bmx_thread_udp_socket_close(int handle) {
    if (handle <= 0) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    BMXThreadUdpEndpoint *endpoint = bmx_udp_endpoint(handle);
    otError error = endpoint ? otUdpClose(bmx_thread_platform_instance(), &endpoint->socket) : OT_ERROR_INVALID_ARGS;
    if (!error) {
        bmx_udp_clear_queue(endpoint->queue, &endpoint->head, &endpoint->count,
                            endpoint->queue_depth);
        endpoint->open = 0;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_udp_socket_local_port(int handle) {
    if (handle <= 0 || bmx_thread_initialize()) return -22;
    bmx_thread_platform_lock();
    BMXThreadUdpEndpoint *endpoint = bmx_udp_endpoint(handle);
    int port = endpoint ? endpoint->socket.mSockName.mPort : -107;
    bmx_thread_platform_unlock();
    return port;
}

int bmx_thread_udp_socket_connect(int handle, const char *address, int port) {
    if (handle <= 0 || !address || port < 1 || port > 65535) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    BMXThreadUdpEndpoint *endpoint = bmx_udp_endpoint(handle);
    otError error = endpoint ? OT_ERROR_NONE : OT_ERROR_INVALID_STATE;
    otSockAddr peer = {0};
    if (!error) error = otIp6AddressFromString(address, &peer.mAddress);
    peer.mPort = (uint16_t)port;
    if (!error) error = otUdpConnect(bmx_thread_platform_instance(), &endpoint->socket, &peer);
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_udp_socket_disconnect(int handle) {
    if (handle <= 0) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    BMXThreadUdpEndpoint *endpoint = bmx_udp_endpoint(handle);
    otSockAddr peer = {0};
    otError error = endpoint ? otUdpConnect(bmx_thread_platform_instance(),
                                             &endpoint->socket, &peer) : OT_ERROR_INVALID_STATE;
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_udp_socket_send_connected(int handle, const uint8_t *data, int length) {
    if (handle <= 0 || !data || length < 0 || length > BMX_THREAD_UDP_PAYLOAD) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    BMXThreadUdpEndpoint *endpoint = bmx_udp_endpoint(handle);
    if (!endpoint || length > (int)endpoint->max_datagram) {
        bmx_thread_platform_unlock();
        return endpoint ? -90 : -107;
    }
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *message = otUdpNewMessage(instance, NULL);
    otError error = message ? OT_ERROR_NONE : OT_ERROR_NO_BUFS;
    if (!error) error = otMessageAppend(message, data, (uint16_t)length);
    otMessageInfo info = {0};
    if (!error) error = otUdpSend(instance, &endpoint->socket, message, &info);
    if (error && message) otMessageFree(message);
    bmx_thread_platform_unlock();
    return error ? -(int)error : length;
}

int bmx_thread_udp_socket_send(int handle, const char *address, int port, const uint8_t *data, int length) {
    if (handle <= 0 || !address || !data || port < 1 || port > 65535 ||
            length < 0 || length > BMX_THREAD_UDP_PAYLOAD) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    BMXThreadUdpEndpoint *endpoint = bmx_udp_endpoint(handle);
    if (!endpoint) {
        bmx_thread_platform_unlock();
        return -107;
    }
    if (length > (int)endpoint->max_datagram) {
        bmx_thread_platform_unlock();
        return -90;
    }
    otInstance *instance = bmx_thread_platform_instance();
    otMessageInfo info = {0};
    info.mPeerPort = (uint16_t)port;
    otError error = otIp6AddressFromString(address, &info.mPeerAddr);
    otMessage *message = NULL;
    if (!error) {
        message = otUdpNewMessage(instance, NULL);
        if (!message) error = OT_ERROR_NO_BUFS;
    }
    if (!error) error = otMessageAppend(message, data, (uint16_t)length);
    if (!error) error = otUdpSend(instance, &endpoint->socket, message, &info);
    if (error && message) otMessageFree(message);
    bmx_thread_platform_unlock();
    return error ? -(int)error : length;
}

int bmx_thread_udp_socket_receive(int handle, uint8_t *data, int capacity, char *address,
                                  int address_capacity, int *port) {
    if (handle <= 0 || !data || capacity < 0 || !address ||
            address_capacity < OT_IP6_ADDRESS_STRING_SIZE || !port) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    BMXThreadUdpEndpoint *endpoint = bmx_udp_endpoint(handle);
    if (!endpoint) {
        bmx_thread_platform_unlock();
        return -107;
    }
    if (!endpoint->count) {
        bmx_thread_platform_unlock();
        return -11;
    }
    BMXThreadDatagram *item = &endpoint->queue[endpoint->head];
    if (capacity < item->length) {
        bmx_thread_platform_unlock();
        return -90;
    }
    if (item->length) memcpy(data, item->data, item->length);
    otIp6AddressToString(&item->address, address, (uint16_t)address_capacity);
    *port = item->port;
    int length = item->length;
    free(item->data);
    item->data = NULL;
    endpoint->head = (endpoint->head + 1) % endpoint->queue_depth;
    --endpoint->count;
    bmx_thread_platform_unlock();
    return length;
}

uint32_t bmx_thread_udp_socket_dropped(int handle) {
    if (bmx_thread_initialize()) return 0;
    bmx_thread_platform_lock();
    BMXThreadUdpEndpoint *endpoint = bmx_udp_endpoint(handle);
    uint32_t dropped = endpoint ? endpoint->dropped : 0;
    bmx_thread_platform_unlock();
    return dropped;
}
