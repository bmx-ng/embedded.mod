/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib */
#include <stdint.h>
#include <string.h>
#include <openthread/coap_secure.h>
#include <openthread/instance.h>
#include <openthread/ip6.h>
#include <openthread/message.h>

extern int bmx_thread_initialize(void);
extern otInstance *bmx_thread_platform_instance(void);
extern void bmx_thread_platform_lock(void);
extern void bmx_thread_platform_unlock(void);

#define BMX_SECURE_PAYLOAD 1024
#define BMX_SECURE_PATH 64

static uint8_t bmx_secure_psk[32];
static uint8_t bmx_secure_identity[64];
static int bmx_secure_started;
static int bmx_secure_connection; /* 0 idle, 1 connecting, 2 connected, negative failure */
static otCoapResource bmx_secure_resource;
static char bmx_secure_path[BMX_SECURE_PATH];
static otMessage *bmx_secure_request;
static otMessageInfo bmx_secure_request_info;
static uint8_t bmx_secure_request_data[BMX_SECURE_PAYLOAD];
static int bmx_secure_request_length = -11;
static int bmx_secure_request_code;
static char bmx_secure_request_address[OT_IP6_ADDRESS_STRING_SIZE];
static uint8_t bmx_secure_response_data[BMX_SECURE_PAYLOAD];
static int bmx_secure_response_length;
static int bmx_secure_response_code;
static int bmx_secure_response_state = -61; /* 1 pending, 0 ready, negative error */

static void bmx_secure_reject(otMessage *request, const otMessageInfo *info,
                               otCoapCode code) {
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *response = otCoapNewMessage(instance, NULL);
    if (!response) return;
    otCoapType type = otCoapMessageGetType(request) == OT_COAP_TYPE_CONFIRMABLE ?
                      OT_COAP_TYPE_ACKNOWLEDGMENT : OT_COAP_TYPE_NON_CONFIRMABLE;
    otError error = otCoapMessageInitResponse(response, request, type, code);
    if (!error) error = otCoapSecureSendResponse(instance, response, info);
    if (error) otMessageFree(response);
}

static void bmx_secure_connect_event(otCoapSecureConnectEvent event, void *context) {
    (void)context;
    bmx_secure_connection = event == OT_COAP_SECURE_CONNECTED ? 2 : -(int)event - 1;
}

static void bmx_secure_handle_request(void *context, otMessage *message,
                                       const otMessageInfo *info) {
    (void)context;
    if (bmx_secure_request) {
        bmx_secure_reject(message, info, OT_COAP_CODE_SERVICE_UNAVAILABLE);
        return;
    }
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;
    if (length > BMX_SECURE_PAYLOAD) {
        bmx_secure_reject(message, info, OT_COAP_CODE_REQUEST_TOO_LARGE);
        return;
    }
    otMessage *copy = otMessageClone(message);
    if (!copy) return;
    if (length && otMessageRead(message, offset, bmx_secure_request_data, length) != length) {
        otMessageFree(copy);
        return;
    }
    bmx_secure_request = copy;
    bmx_secure_request_info = *info;
    bmx_secure_request_length = length;
    bmx_secure_request_code = otCoapMessageGetCode(message);
    otIp6AddressToString(&info->mPeerAddr, bmx_secure_request_address,
                         sizeof(bmx_secure_request_address));
}

static void bmx_secure_handle_response(void *context, otMessage *message,
                                        const otMessageInfo *info, otError error) {
    (void)context;
    (void)info;
    if (bmx_secure_response_state != 1) return;
    if (error || !message) {
        bmx_secure_response_state = error ? -(int)error : -61;
        return;
    }
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;
    if (length > BMX_SECURE_PAYLOAD ||
        (length && otMessageRead(message, offset, bmx_secure_response_data, length) != length)) {
        bmx_secure_response_state = -90;
        return;
    }
    bmx_secure_response_length = length;
    bmx_secure_response_code = otCoapMessageGetCode(message);
    bmx_secure_response_state = 0;
}

int bmx_thread_coap_secure_start(const uint8_t *psk, int psk_length,
                                  const uint8_t *identity, int identity_length,
                                  int port) {
    if (!psk || psk_length < 16 || psk_length > (int)sizeof(bmx_secure_psk) ||
        !identity || identity_length < 1 || identity_length > (int)sizeof(bmx_secure_identity) ||
        port < 1 || port > 65535) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_secure_started) {
        bmx_thread_platform_unlock();
        return -16;
    }
    memcpy(bmx_secure_psk, psk, psk_length);
    memcpy(bmx_secure_identity, identity, identity_length);
    otInstance *instance = bmx_thread_platform_instance();
    otCoapSecureSetPsk(instance, bmx_secure_psk, (uint16_t)psk_length,
                       bmx_secure_identity, (uint16_t)identity_length);
    otError error = otCoapSecureStart(instance, (uint16_t)port);
    if (!error) {
        bmx_secure_started = 1;
        bmx_secure_connection = 0;
    } else {
        memset(bmx_secure_psk, 0, sizeof(bmx_secure_psk));
        memset(bmx_secure_identity, 0, sizeof(bmx_secure_identity));
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_secure_resource(const char *path) {
    if (!path || !*path || strlen(path) >= BMX_SECURE_PATH) return -22;
    bmx_thread_platform_lock();
    if (!bmx_secure_started || bmx_secure_resource.mUriPath) {
        bmx_thread_platform_unlock();
        return -61;
    }
    strcpy(bmx_secure_path, path);
    bmx_secure_resource.mUriPath = bmx_secure_path;
    bmx_secure_resource.mHandler = bmx_secure_handle_request;
    otCoapSecureAddResource(bmx_thread_platform_instance(), &bmx_secure_resource);
    bmx_thread_platform_unlock();
    return 0;
}

int bmx_thread_coap_secure_receive(uint8_t *data, int capacity, int *method,
                                    char *address, int address_capacity) {
    if (!data || capacity < 0 || !method || !address ||
        address_capacity < OT_IP6_ADDRESS_STRING_SIZE) return -22;
    bmx_thread_platform_lock();
    int length = bmx_secure_request_length;
    if (length >= 0 && !bmx_secure_request) length = -11;
    if (length >= 0 && capacity < length) length = -90;
    if (length >= 0) {
        if (length) memcpy(data, bmx_secure_request_data, length);
        *method = bmx_secure_request_code;
        strcpy(address, bmx_secure_request_address);
        bmx_secure_request_length = -11;
    }
    bmx_thread_platform_unlock();
    return length;
}

int bmx_thread_coap_secure_respond(int code, const uint8_t *data, int length) {
    if (code < 64 || code > 191 || length < 0 || length > BMX_SECURE_PAYLOAD ||
        (length && !data)) return -22;
    bmx_thread_platform_lock();
    if (!bmx_secure_started || !bmx_secure_request) {
        bmx_thread_platform_unlock();
        return -61;
    }
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *response = otCoapNewMessage(instance, NULL);
    otError error = response ? OT_ERROR_NONE : OT_ERROR_NO_BUFS;
    if (!error) error = otCoapMessageInitResponse(response, bmx_secure_request,
        otCoapMessageGetType(bmx_secure_request) == OT_COAP_TYPE_CONFIRMABLE ?
        OT_COAP_TYPE_ACKNOWLEDGMENT : OT_COAP_TYPE_NON_CONFIRMABLE, (otCoapCode)code);
    if (!error && length) error = otCoapMessageSetPayloadMarker(response);
    if (!error && length) error = otMessageAppend(response, data, (uint16_t)length);
    if (!error) error = otCoapSecureSendResponse(instance, response, &bmx_secure_request_info);
    if (error && response) otMessageFree(response);
    if (!error) {
        otMessageFree(bmx_secure_request);
        bmx_secure_request = NULL;
        bmx_secure_request_length = -11;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_secure_connect(const char *address, int port) {
    if (!address || port < 1 || port > 65535) return -22;
    bmx_thread_platform_lock();
    if (!bmx_secure_started || bmx_secure_connection == 1 || bmx_secure_connection == 2) {
        bmx_thread_platform_unlock();
        return -16;
    }
    otSockAddr peer = {0};
    otError error = otIp6AddressFromString(address, &peer.mAddress);
    peer.mPort = (uint16_t)port;
    if (!error) {
        bmx_secure_connection = 1;
        error = otCoapSecureConnect(bmx_thread_platform_instance(), &peer,
                                    bmx_secure_connect_event, NULL);
    }
    if (error) bmx_secure_connection = -(int)error;
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_secure_connection(void) {
    bmx_thread_platform_lock();
    int state = bmx_secure_connection;
    if (bmx_secure_started && otCoapSecureIsConnected(bmx_thread_platform_instance())) state = 2;
    bmx_thread_platform_unlock();
    return state;
}

int bmx_thread_coap_secure_send(const char *path, int code,
                                 const uint8_t *data, int length) {
    if (!path || !*path || (code != OT_COAP_CODE_GET && code != OT_COAP_CODE_POST &&
        code != OT_COAP_CODE_PUT && code != OT_COAP_CODE_DELETE) ||
        length < 0 || length > BMX_SECURE_PAYLOAD || (length && !data)) return -22;
    bmx_thread_platform_lock();
    otInstance *instance = bmx_thread_platform_instance();
    if (!bmx_secure_started || !otCoapSecureIsConnected(instance) ||
        bmx_secure_response_state == 1) {
        bmx_thread_platform_unlock();
        return -61;
    }
    otMessage *message = otCoapNewMessage(instance, NULL);
    otError error = message ? OT_ERROR_NONE : OT_ERROR_NO_BUFS;
    if (!error) error = otCoapMessageInit(message, OT_COAP_TYPE_CONFIRMABLE, (otCoapCode)code);
    if (!error) otCoapMessageGenerateToken(message, 4);
    if (!error) error = otCoapMessageAppendUriPathOptions(message, path);
    if (!error && length) error = otCoapMessageSetPayloadMarker(message);
    if (!error && length) error = otMessageAppend(message, data, (uint16_t)length);
    if (!error) {
        bmx_secure_response_state = 1;
        error = otCoapSecureSendRequest(instance, message, bmx_secure_handle_response, NULL);
    }
    if (error) {
        if (message) otMessageFree(message);
        bmx_secure_response_state = -61;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_secure_response(uint8_t *data, int capacity, int *code) {
    if (!data || capacity < 0 || !code) return -22;
    bmx_thread_platform_lock();
    int length = bmx_secure_response_state == 1 ? -11 : bmx_secure_response_state;
    if (length == 0) {
        length = bmx_secure_response_length;
        if (capacity < length) length = -90;
        if (length >= 0) {
            if (length) memcpy(data, bmx_secure_response_data, length);
            *code = bmx_secure_response_code;
            bmx_secure_response_state = -61;
        }
    }
    bmx_thread_platform_unlock();
    return length;
}

int bmx_thread_coap_secure_stop(void) {
    bmx_thread_platform_lock();
    if (!bmx_secure_started) {
        bmx_thread_platform_unlock();
        return -61;
    }
    otInstance *instance = bmx_thread_platform_instance();
    if (bmx_secure_resource.mUriPath) {
        otCoapSecureRemoveResource(instance, &bmx_secure_resource);
        memset(&bmx_secure_resource, 0, sizeof(bmx_secure_resource));
    }
    otCoapSecureStop(instance);
    if (bmx_secure_request) otMessageFree(bmx_secure_request);
    bmx_secure_request = NULL;
    bmx_secure_request_length = -11;
    bmx_secure_response_state = -61;
    bmx_secure_connection = 0;
    bmx_secure_started = 0;
    memset(bmx_secure_psk, 0, sizeof(bmx_secure_psk));
    memset(bmx_secure_identity, 0, sizeof(bmx_secure_identity));
    bmx_thread_platform_unlock();
    return 0;
}
