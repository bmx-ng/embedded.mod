/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib */
#include <stdint.h>
#include <string.h>
#include <openthread/coap.h>
#include <openthread/instance.h>
#include <openthread/ip6.h>
#include <openthread/message.h>

extern int bmx_thread_initialize(void);
extern otInstance *bmx_thread_platform_instance(void);
extern void bmx_thread_platform_lock(void);
extern void bmx_thread_platform_unlock(void);

#define BMX_COAP_PAYLOAD 512
#define BMX_COAP_PATH 64

static int bmx_coap_started;
static otCoapResource bmx_coap_resource;
static char bmx_coap_path[BMX_COAP_PATH];
static otMessage *bmx_coap_request_message;
static otMessageInfo bmx_coap_request_info;
static uint8_t bmx_coap_request_data[BMX_COAP_PAYLOAD];
static int bmx_coap_request_length = -11;
static int bmx_coap_request_code;
static char bmx_coap_request_address[OT_IP6_ADDRESS_STRING_SIZE];
static int bmx_coap_client_state = -61;
static int bmx_coap_client_code;
static int bmx_coap_client_length;
static uint8_t bmx_coap_client_data[BMX_COAP_PAYLOAD];

static void bmx_coap_reject(otMessage *request, const otMessageInfo *info, otCoapCode code) {
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *response = otCoapNewMessage(instance, NULL);
    if (!response) return;
    otCoapType type = otCoapMessageGetType(request) == OT_COAP_TYPE_CONFIRMABLE ?
                      OT_COAP_TYPE_ACKNOWLEDGMENT : OT_COAP_TYPE_NON_CONFIRMABLE;
    otError error = otCoapMessageInitResponse(response, request, type, code);
    if (!error) error = otCoapSendResponse(instance, response, info);
    if (error) otMessageFree(response);
}

static void bmx_coap_handle_request(void *context, otMessage *message, const otMessageInfo *info) {
    (void)context;
    if (bmx_coap_request_message) return;
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;
    if (length > BMX_COAP_PAYLOAD) {
        bmx_coap_reject(message, info, OT_COAP_CODE_REQUEST_TOO_LARGE);
        return;
    }
    otMessage *copy = otMessageClone(message);
    if (!copy) return;
    bmx_coap_request_message = copy;
    bmx_coap_request_info = *info;
    bmx_coap_request_code = otCoapMessageGetCode(message);
    bmx_coap_request_length = length;
    otMessageRead(message, offset, bmx_coap_request_data, length);
    otIp6AddressToString(&info->mPeerAddr, bmx_coap_request_address, sizeof(bmx_coap_request_address));
}

static void bmx_coap_handle_response(void *context, otMessage *message,
                                     const otMessageInfo *info, otError error) {
    (void)context;
    (void)info;
    bmx_coap_client_state = error ? -(int)error : 0;
    if (error || !message) return;
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;
    if (length > BMX_COAP_PAYLOAD) {
        bmx_coap_client_state = -90;
        return;
    }
    bmx_coap_client_code = otCoapMessageGetCode(message);
    bmx_coap_client_length = length;
    otMessageRead(message, offset, bmx_coap_client_data, length);
}

int bmx_thread_coap_start(int port) {
    if (port < 1 || port > 65535) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_coap_started) {
        bmx_thread_platform_unlock();
        return -16;
    }
    otError error = otCoapStart(bmx_thread_platform_instance(), (uint16_t)port);
    if (!error) bmx_coap_started = 1;
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_resource(const char *path) {
    if (!path || !*path || strlen(path) >= BMX_COAP_PATH) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (!bmx_coap_started || bmx_coap_resource.mUriPath) {
        bmx_thread_platform_unlock();
        return -16;
    }
    strcpy(bmx_coap_path, path);
    memset(&bmx_coap_resource, 0, sizeof(bmx_coap_resource));
    bmx_coap_resource.mUriPath = bmx_coap_path;
    bmx_coap_resource.mHandler = bmx_coap_handle_request;
    otCoapAddResource(bmx_thread_platform_instance(), &bmx_coap_resource);
    bmx_thread_platform_unlock();
    return 0;
}

int bmx_thread_coap_receive(uint8_t *data, int capacity, int *code, char *address, int address_capacity) {
    if (!data || capacity < 0 || !code || !address || address_capacity < OT_IP6_ADDRESS_STRING_SIZE) return -22;
    bmx_thread_platform_lock();
    int length = bmx_coap_request_length;
    if (length >= 0 && capacity < length) length = -90;
    if (length >= 0) {
        memcpy(data, bmx_coap_request_data, (size_t)length);
        *code = bmx_coap_request_code;
        strcpy(address, bmx_coap_request_address);
        bmx_coap_request_length = -11;
    }
    bmx_thread_platform_unlock();
    return length;
}

int bmx_thread_coap_respond(int code, const uint8_t *data, int length) {
    if (code < 64 || code > 191 || length < 0 || length > BMX_COAP_PAYLOAD || (length && !data)) return -22;
    bmx_thread_platform_lock();
    if (!bmx_coap_request_message) {
        bmx_thread_platform_unlock();
        return -61;
    }
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *response = otCoapNewMessage(instance, NULL);
    otError error = response ? OT_ERROR_NONE : OT_ERROR_NO_BUFS;
    if (!error) error = otCoapMessageInitResponse(response, bmx_coap_request_message,
        otCoapMessageGetType(bmx_coap_request_message) == OT_COAP_TYPE_CONFIRMABLE ?
        OT_COAP_TYPE_ACKNOWLEDGMENT : OT_COAP_TYPE_NON_CONFIRMABLE, (otCoapCode)code);
    if (!error && length) error = otCoapMessageSetPayloadMarker(response);
    if (!error && length) error = otMessageAppend(response, data, (uint16_t)length);
    if (!error) error = otCoapSendResponse(instance, response, &bmx_coap_request_info);
    if (error && response) otMessageFree(response);
    if (!error) {
        otMessageFree(bmx_coap_request_message);
        bmx_coap_request_message = NULL;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_send(const char *address, int port, const char *path, int code,
                         const uint8_t *data, int length) {
    if (!address || !path || !*path || port < 1 || port > 65535 ||
        (code != OT_COAP_CODE_GET && code != OT_COAP_CODE_POST) ||
        length < 0 || length > BMX_COAP_PAYLOAD || (length && !data)) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (!bmx_coap_started || bmx_coap_client_state == 1) {
        bmx_thread_platform_unlock();
        return -16;
    }
    otMessageInfo info = {0};
    otError error = otIp6AddressFromString(address, &info.mPeerAddr);
    info.mPeerPort = (uint16_t)port;
    otMessage *message = NULL;
    if (!error) message = otCoapNewMessage(bmx_thread_platform_instance(), NULL);
    if (!error && !message) error = OT_ERROR_NO_BUFS;
    if (!error) error = otCoapMessageInit(message, OT_COAP_TYPE_CONFIRMABLE, (otCoapCode)code);
    if (!error) otCoapMessageGenerateToken(message, 2);
    if (!error) error = otCoapMessageAppendUriPathOptions(message, path);
    if (!error && length) error = otCoapMessageSetPayloadMarker(message);
    if (!error && length) error = otMessageAppend(message, data, (uint16_t)length);
    if (!error) error = otCoapSendRequest(bmx_thread_platform_instance(), message, &info,
                                          bmx_coap_handle_response, NULL);
    if (error && message) otMessageFree(message);
    if (!error) {
        bmx_coap_client_state = 1;
        bmx_coap_client_length = 0;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_response(uint8_t *data, int capacity, int *code) {
    if (!data || capacity < 0 || !code) return -22;
    bmx_thread_platform_lock();
    int state = bmx_coap_client_state == 1 ? -11 : bmx_coap_client_state;
    if (state == 0) {
        state = bmx_coap_client_length;
        if (capacity < state) state = -90;
        if (state >= 0) {
            memcpy(data, bmx_coap_client_data, (size_t)state);
            *code = bmx_coap_client_code;
            bmx_coap_client_state = -61;
        }
    }
    bmx_thread_platform_unlock();
    return state;
}
