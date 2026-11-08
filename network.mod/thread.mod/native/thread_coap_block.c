/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib */
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <openthread/coap.h>
#include <openthread/instance.h>
#include <openthread/ip6.h>
#include <openthread/message.h>
#include <openthread/platform/alarm-milli.h>

extern int bmx_thread_initialize(void);
extern otInstance *bmx_thread_platform_instance(void);
extern void bmx_thread_platform_lock(void);
extern void bmx_thread_platform_unlock(void);

#define BMX_BLOCK_CAPACITY 4096
#define BMX_BLOCK_SIZE 256
#define BMX_BLOCK_PATH 64

static otCoapBlockwiseResource bmx_block_resource;
static char bmx_block_path[BMX_BLOCK_PATH];
static uint8_t bmx_block_request[BMX_BLOCK_CAPACITY];
static int bmx_block_request_length;
static int bmx_block_request_state; /* 0 empty, 1 queued, 2 delivered */
static int bmx_block_request_code;
static int bmx_block_request_wants_blocks;
static otMessage *bmx_block_request_message;
static otMessageInfo bmx_block_request_info;
static char bmx_block_request_address[OT_IP6_ADDRESS_STRING_SIZE];
static uint8_t bmx_block_response[BMX_BLOCK_CAPACITY];
static int bmx_block_response_length;
static int bmx_block_response_active;
static uint32_t bmx_block_response_activity;

static uint8_t bmx_block_client_tx[BMX_BLOCK_CAPACITY];
static int bmx_block_client_tx_length;
static uint8_t bmx_block_client_rx[BMX_BLOCK_CAPACITY];
static int bmx_block_client_rx_length;
static int bmx_block_client_state = -61; /* 1 pending, 0 ready, negative error */
static int bmx_block_client_code;

static otError bmx_block_receive_request(void *context, const uint8_t *block,
                                         uint32_t position, uint16_t length,
                                         bool more, uint32_t total_length) {
    (void)context;
    (void)total_length;
    if (bmx_block_request_state || position > BMX_BLOCK_CAPACITY ||
        length > BMX_BLOCK_CAPACITY - position) return OT_ERROR_NO_BUFS;
    if (position == 0) bmx_block_request_length = 0;
    if (position != (uint32_t)bmx_block_request_length) return OT_ERROR_NO_FRAME_RECEIVED;
    memcpy(bmx_block_request + position, block, length);
    bmx_block_request_length += length;
    (void)more;
    return OT_ERROR_NONE;
}

static otError bmx_block_transmit_response(void *context, uint8_t *block,
                                          uint32_t position, uint16_t *length,
                                          bool *more) {
    (void)context;
    if (position >= (uint32_t)bmx_block_response_length) return OT_ERROR_INVALID_ARGS;
    uint16_t remaining = (uint16_t)(bmx_block_response_length - position);
    if (*length > remaining) *length = remaining;
    memcpy(block, bmx_block_response + position, *length);
    *more = position + *length < (uint32_t)bmx_block_response_length;
    bmx_block_response_activity = otPlatAlarmMilliGetNow();
    if (!*more) bmx_block_response_active = 0;
    return OT_ERROR_NONE;
}

static void bmx_block_reject(otMessage *request, const otMessageInfo *info) {
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *response = otCoapNewMessage(instance, NULL);
    if (!response) return;
    otCoapType type = otCoapMessageGetType(request) == OT_COAP_TYPE_CONFIRMABLE ?
                      OT_COAP_TYPE_ACKNOWLEDGMENT : OT_COAP_TYPE_NON_CONFIRMABLE;
    otError error = otCoapMessageInitResponse(response, request, type,
                                              OT_COAP_CODE_SERVICE_UNAVAILABLE);
    if (!error) error = otCoapSendResponse(instance, response, info);
    if (error) otMessageFree(response);
}

static void bmx_block_handle_request(void *context, otMessage *message,
                                     const otMessageInfo *info) {
    (void)context;
    if (bmx_block_response_active &&
        (uint32_t)(otPlatAlarmMilliGetNow() - bmx_block_response_activity) >= 30000)
        bmx_block_response_active = 0;
    if (bmx_block_request_state || bmx_block_response_active) {
        bmx_block_reject(message, info);
        return;
    }
    otCoapOptionIterator iterator;
    int block1 = 0;
    int block2 = 0;
    if (otCoapOptionIteratorInit(&iterator, message) == OT_ERROR_NONE) {
        block1 = otCoapOptionIteratorGetFirstOptionMatching(&iterator, OT_COAP_OPTION_BLOCK1) != NULL;
        block2 = otCoapOptionIteratorGetFirstOptionMatching(&iterator, OT_COAP_OPTION_BLOCK2) != NULL;
    }
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;
    if (!block1) {
        if (length > BMX_BLOCK_CAPACITY ||
            otMessageRead(message, offset, bmx_block_request, length) != length) return;
        bmx_block_request_length = length;
    }
    otMessage *copy = otMessageClone(message);
    if (!copy) return;
    bmx_block_request_message = copy;
    bmx_block_request_info = *info;
    bmx_block_request_code = otCoapMessageGetCode(message);
    bmx_block_request_wants_blocks = block2;
    otIp6AddressToString(&info->mPeerAddr, bmx_block_request_address,
                         sizeof(bmx_block_request_address));
    bmx_block_request_state = 1;
}

static otError bmx_block_transmit_request(void *context, uint8_t *block,
                                         uint32_t position, uint16_t *length,
                                         bool *more) {
    (void)context;
    if (position >= (uint32_t)bmx_block_client_tx_length) return OT_ERROR_INVALID_ARGS;
    uint16_t remaining = (uint16_t)(bmx_block_client_tx_length - position);
    if (*length > remaining) *length = remaining;
    memcpy(block, bmx_block_client_tx + position, *length);
    *more = position + *length < (uint32_t)bmx_block_client_tx_length;
    return OT_ERROR_NONE;
}

static otError bmx_block_receive_response(void *context, const uint8_t *block,
                                          uint32_t position, uint16_t length,
                                          bool more, uint32_t total_length) {
    (void)context;
    (void)more;
    (void)total_length;
    if (position > BMX_BLOCK_CAPACITY || length > BMX_BLOCK_CAPACITY - position)
        return OT_ERROR_NO_BUFS;
    if (position != (uint32_t)bmx_block_client_rx_length)
        return OT_ERROR_NO_FRAME_RECEIVED;
    memcpy(bmx_block_client_rx + position, block, length);
    bmx_block_client_rx_length += length;
    return OT_ERROR_NONE;
}

static void bmx_block_handle_response(void *context, otMessage *message,
                                      const otMessageInfo *info, otError error) {
    (void)context;
    (void)info;
    if (bmx_block_client_state != 1) return;
    if (error || !message) {
        bmx_block_client_state = error ? -(int)error : -61;
        return;
    }
    bmx_block_client_code = otCoapMessageGetCode(message);
    if (bmx_block_client_rx_length == 0) {
        uint16_t offset = otMessageGetOffset(message);
        uint16_t length = otMessageGetLength(message) - offset;
        if (length > BMX_BLOCK_CAPACITY ||
            otMessageRead(message, offset, bmx_block_client_rx, length) != length) {
            bmx_block_client_state = -90;
            return;
        }
        bmx_block_client_rx_length = length;
    }
    bmx_block_client_state = 0;
}

int bmx_thread_coap_block_resource(const char *path) {
    if (!path || !*path || strlen(path) >= BMX_BLOCK_PATH) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_block_resource.mUriPath) {
        bmx_thread_platform_unlock();
        return -16;
    }
    strcpy(bmx_block_path, path);
    bmx_block_resource.mUriPath = bmx_block_path;
    bmx_block_resource.mHandler = bmx_block_handle_request;
    bmx_block_resource.mReceiveHook = bmx_block_receive_request;
    bmx_block_resource.mTransmitHook = bmx_block_transmit_response;
    otCoapAddBlockWiseResource(bmx_thread_platform_instance(), &bmx_block_resource);
    bmx_thread_platform_unlock();
    return 0;
}

int bmx_thread_coap_block_receive(uint8_t *data, int capacity, int *code,
                                  char *address, int address_capacity) {
    if (!data || capacity < 0 || !code || !address ||
        address_capacity < OT_IP6_ADDRESS_STRING_SIZE) return -22;
    bmx_thread_platform_lock();
    int length = -11;
    if (bmx_block_request_state == 1) {
        length = bmx_block_request_length;
        if (capacity < length) length = -90;
        if (length >= 0) {
            if (length) memcpy(data, bmx_block_request, length);
            *code = bmx_block_request_code;
            strcpy(address, bmx_block_request_address);
            bmx_block_request_state = 2;
        }
    }
    bmx_thread_platform_unlock();
    return length;
}

int bmx_thread_coap_block_respond(int code, const uint8_t *data, int length) {
    if (code < 64 || code > 191 || length < 0 || length > BMX_BLOCK_CAPACITY ||
        (length && !data)) return -22;
    bmx_thread_platform_lock();
    if (bmx_block_request_state != 2 || !bmx_block_request_message) {
        bmx_thread_platform_unlock();
        return -61;
    }
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *response = otCoapNewMessage(instance, NULL);
    otError error = response ? OT_ERROR_NONE : OT_ERROR_NO_BUFS;
    if (!error) error = otCoapMessageInitResponse(response, bmx_block_request_message,
        otCoapMessageGetType(bmx_block_request_message) == OT_COAP_TYPE_CONFIRMABLE ?
        OT_COAP_TYPE_ACKNOWLEDGMENT : OT_COAP_TYPE_NON_CONFIRMABLE, (otCoapCode)code);
    if (!error && bmx_block_request_wants_blocks && length) {
        memcpy(bmx_block_response, data, length);
        bmx_block_response_length = length;
        bmx_block_response_active = 1;
        bmx_block_response_activity = otPlatAlarmMilliGetNow();
        error = otCoapMessageAppendBlock2Option(response, 0, length > BMX_BLOCK_SIZE,
                                                 OT_COAP_OPTION_BLOCK_SZX_256);
        if (!error) error = otCoapSendResponseBlockWise(instance, response,
                            &bmx_block_request_info, NULL, bmx_block_transmit_response);
    } else if (!error && length <= 1024) {
        if (length) error = otCoapMessageSetPayloadMarker(response);
        if (!error && length) error = otMessageAppend(response, data, (uint16_t)length);
        if (!error) error = otCoapSendResponse(instance, response, &bmx_block_request_info);
    } else if (!error) {
        error = OT_ERROR_INVALID_ARGS;
    }
    if (error && response) otMessageFree(response);
    if (error) bmx_block_response_active = 0;
    if (!error) {
        otMessageFree(bmx_block_request_message);
        bmx_block_request_message = NULL;
        bmx_block_request_state = 0;
        bmx_block_request_length = 0;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_block_send(const char *address, int port, const char *path,
                               int code, const uint8_t *data, int length) {
    if (!address || !path || !*path || port < 1 || port > 65535 ||
        (code != OT_COAP_CODE_GET && code != OT_COAP_CODE_POST &&
         code != OT_COAP_CODE_PUT && code != OT_COAP_CODE_DELETE) ||
        length < 0 || length > BMX_BLOCK_CAPACITY || (length && !data)) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_block_client_state == 1) {
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
    if (!error) otCoapMessageGenerateToken(message, 4);
    if (!error) error = otCoapMessageAppendUriPathOptions(message, path);
    if (!error && !length) error = otCoapMessageAppendBlock2Option(message, 0, false,
                                                                   OT_COAP_OPTION_BLOCK_SZX_256);
    if (!error && length) error = otCoapMessageAppendBlock1Option(message, 0,
                           length > BMX_BLOCK_SIZE, OT_COAP_OPTION_BLOCK_SZX_256);
    if (!error && length) {
        memcpy(bmx_block_client_tx, data, length);
        bmx_block_client_tx_length = length;
    }
    if (!error) {
        bmx_block_client_rx_length = 0;
        bmx_block_client_state = 1;
        error = otCoapSendRequestBlockWise(bmx_thread_platform_instance(), message, &info,
                    bmx_block_handle_response, NULL,
                    length ? bmx_block_transmit_request : NULL,
                    bmx_block_receive_response);
    }
    if (error) {
        if (message) otMessageFree(message);
        bmx_block_client_state = -61;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_block_response(uint8_t *data, int capacity, int *code) {
    if (!data || capacity < 0 || !code) return -22;
    bmx_thread_platform_lock();
    int length = bmx_block_client_state == 1 ? -11 : bmx_block_client_state;
    if (length == 0) {
        length = bmx_block_client_rx_length;
        if (capacity < length) length = -90;
        if (length >= 0) {
            if (length) memcpy(data, bmx_block_client_rx, length);
            *code = bmx_block_client_code;
            bmx_block_client_state = -61;
        }
    }
    bmx_thread_platform_unlock();
    return length;
}
