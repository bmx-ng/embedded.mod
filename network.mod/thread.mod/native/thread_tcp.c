/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib */
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <openthread/instance.h>
#include <openthread/ip6.h>
#include <openthread/tcp.h>

extern int bmx_thread_initialize(void);
extern otInstance *bmx_thread_platform_instance(void);
extern void bmx_thread_platform_lock(void);
extern void bmx_thread_platform_unlock(void);

#define BMX_TCP_RECEIVE_BUFFER OT_TCP_RECEIVE_BUFFER_SIZE_FEW_HOPS
#define BMX_TCP_SEND_BUFFER 1024

static otTcpEndpoint bmx_tcp_endpoint;
static otTcpListener bmx_tcp_listener;
static uint8_t bmx_tcp_receive_buffer[BMX_TCP_RECEIVE_BUFFER];
static uint8_t bmx_tcp_send_buffer[BMX_TCP_SEND_BUFFER];
static otLinkedBuffer bmx_tcp_send_link;
static int bmx_tcp_initialized;
static int bmx_tcp_listening;
static int bmx_tcp_state; /* 0 idle, 1 connecting/listening, 2 connected, negative failure */
static int bmx_tcp_send_busy;
static int bmx_tcp_end_of_stream;

static void bmx_tcp_established(otTcpEndpoint *endpoint) {
    (void)endpoint;
    bmx_tcp_state = 2;
}

static void bmx_tcp_send_done(otTcpEndpoint *endpoint, otLinkedBuffer *data) {
    (void)endpoint;
    if (data == &bmx_tcp_send_link) bmx_tcp_send_busy = 0;
}

static void bmx_tcp_receive_available(otTcpEndpoint *endpoint, size_t available,
                                      bool end_of_stream, size_t remaining) {
    (void)endpoint;
    (void)available;
    (void)remaining;
    if (end_of_stream) bmx_tcp_end_of_stream = 1;
}

static void bmx_tcp_disconnected(otTcpEndpoint *endpoint, otTcpDisconnectedReason reason) {
    (void)endpoint;
    bmx_tcp_state = -(int)reason - 1;
    bmx_tcp_send_busy = 0;
    bmx_tcp_end_of_stream = 1;
}

static otTcpIncomingConnectionAction bmx_tcp_accept_ready(otTcpListener *listener,
                                                            const otSockAddr *peer,
                                                            otTcpEndpoint **accept_into) {
    (void)listener;
    (void)peer;
    if (bmx_tcp_state != 1) return OT_TCP_INCOMING_CONNECTION_ACTION_REFUSE;
    *accept_into = &bmx_tcp_endpoint;
    return OT_TCP_INCOMING_CONNECTION_ACTION_ACCEPT;
}

static void bmx_tcp_accept_done(otTcpListener *listener, otTcpEndpoint *endpoint,
                                 const otSockAddr *peer) {
    (void)listener;
    (void)endpoint;
    (void)peer;
    bmx_tcp_state = 2;
}

int bmx_thread_tcp_open(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_tcp_initialized) {
        bmx_thread_platform_unlock();
        return -16;
    }
    memset(&bmx_tcp_endpoint, 0, sizeof(bmx_tcp_endpoint));
    otTcpEndpointInitializeArgs args = {0};
    args.mEstablishedCallback = bmx_tcp_established;
    args.mSendDoneCallback = bmx_tcp_send_done;
    args.mReceiveAvailableCallback = bmx_tcp_receive_available;
    args.mDisconnectedCallback = bmx_tcp_disconnected;
    args.mReceiveBuffer = bmx_tcp_receive_buffer;
    args.mReceiveBufferSize = sizeof(bmx_tcp_receive_buffer);
    otError error = otTcpEndpointInitialize(bmx_thread_platform_instance(),
                                             &bmx_tcp_endpoint, &args);
    if (!error) {
        bmx_tcp_initialized = 1;
        bmx_tcp_state = 0;
        bmx_tcp_send_busy = 0;
        bmx_tcp_end_of_stream = 0;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_tcp_connect(const char *address, int port) {
    if (!address || port < 1 || port > 65535) return -22;
    bmx_thread_platform_lock();
    if (!bmx_tcp_initialized || bmx_tcp_state != 0) {
        bmx_thread_platform_unlock();
        return -61;
    }
    otSockAddr peer = {0};
    otError error = otIp6AddressFromString(address, &peer.mAddress);
    peer.mPort = (uint16_t)port;
    if (!error) error = otTcpConnect(&bmx_tcp_endpoint, &peer, OT_TCP_CONNECT_NO_FAST_OPEN);
    if (!error) bmx_tcp_state = 1;
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_tcp_listen(int port) {
    if (port < 1 || port > 65535) return -22;
    bmx_thread_platform_lock();
    if (!bmx_tcp_initialized || bmx_tcp_listening || bmx_tcp_state != 0) {
        bmx_thread_platform_unlock();
        return -61;
    }
    memset(&bmx_tcp_listener, 0, sizeof(bmx_tcp_listener));
    otTcpListenerInitializeArgs args = {0};
    args.mAcceptReadyCallback = bmx_tcp_accept_ready;
    args.mAcceptDoneCallback = bmx_tcp_accept_done;
    otInstance *instance = bmx_thread_platform_instance();
    otError error = otTcpListenerInitialize(instance, &bmx_tcp_listener, &args);
    if (!error) {
        otSockAddr local = {0};
        local.mPort = (uint16_t)port;
        error = otTcpListen(&bmx_tcp_listener, &local);
        if (error) otTcpListenerDeinitialize(&bmx_tcp_listener);
    }
    if (!error) {
        bmx_tcp_listening = 1;
        bmx_tcp_state = 1;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_tcp_state(void) {
    bmx_thread_platform_lock();
    int state = bmx_tcp_initialized ? bmx_tcp_state : -61;
    bmx_thread_platform_unlock();
    return state;
}

int bmx_thread_tcp_send(const uint8_t *data, int length) {
    if (!data || length < 1 || length > BMX_TCP_SEND_BUFFER) return -22;
    bmx_thread_platform_lock();
    if (!bmx_tcp_initialized || bmx_tcp_state != 2) {
        bmx_thread_platform_unlock();
        return -107;
    }
    if (bmx_tcp_send_busy) {
        bmx_thread_platform_unlock();
        return -16;
    }
    memcpy(bmx_tcp_send_buffer, data, length);
    bmx_tcp_send_link.mNext = NULL;
    bmx_tcp_send_link.mData = bmx_tcp_send_buffer;
    bmx_tcp_send_link.mLength = (size_t)length;
    bmx_tcp_send_busy = 1;
    otError error = otTcpSendByReference(&bmx_tcp_endpoint, &bmx_tcp_send_link, 0);
    if (error) bmx_tcp_send_busy = 0;
    bmx_thread_platform_unlock();
    return error ? -(int)error : length;
}

int bmx_thread_tcp_send_ready(void) {
    bmx_thread_platform_lock();
    int ready = bmx_tcp_initialized && bmx_tcp_state == 2 && !bmx_tcp_send_busy;
    bmx_thread_platform_unlock();
    return ready;
}

int bmx_thread_tcp_receive(uint8_t *data, int capacity) {
    if (!data || capacity < 1) return -22;
    bmx_thread_platform_lock();
    if (!bmx_tcp_initialized) {
        bmx_thread_platform_unlock();
        return -107;
    }
    const otLinkedBuffer *buffer = NULL;
    otError error = otTcpReceiveByReference(&bmx_tcp_endpoint, &buffer);
    int length = 0;
    if (!error) {
        for (const otLinkedBuffer *item = buffer; item && length < capacity; item = item->mNext) {
            int take = (int)item->mLength;
            if (take > capacity - length) take = capacity - length;
            if (take) memcpy(data + length, item->mData, take);
            length += take;
        }
        if (length) error = otTcpCommitReceive(&bmx_tcp_endpoint, (size_t)length, 0);
    }
    if (error) length = -(int)error;
    else if (!length) length = bmx_tcp_end_of_stream ? 0 : -11;
    bmx_thread_platform_unlock();
    return length;
}

int bmx_thread_tcp_end_send(void) {
    bmx_thread_platform_lock();
    otError error = bmx_tcp_initialized && bmx_tcp_state == 2 ?
                    otTcpSendEndOfStream(&bmx_tcp_endpoint) : OT_ERROR_INVALID_STATE;
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_tcp_close(void) {
    bmx_thread_platform_lock();
    if (!bmx_tcp_initialized) {
        bmx_thread_platform_unlock();
        return 0;
    }
    otError error = OT_ERROR_NONE;
    if (bmx_tcp_listening) {
        error = otTcpListenerDeinitialize(&bmx_tcp_listener);
        if (!error) bmx_tcp_listening = 0;
    }
    if (!error) error = otTcpEndpointDeinitialize(&bmx_tcp_endpoint);
    if (!error) {
        bmx_tcp_initialized = 0;
        bmx_tcp_state = 0;
        bmx_tcp_send_busy = 0;
        bmx_tcp_end_of_stream = 0;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}
