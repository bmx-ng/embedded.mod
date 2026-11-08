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

#define BMX_OBSERVE_PAYLOAD 1024
#define BMX_OBSERVE_PATH 64
#define BMX_OBSERVE_QUEUE 4

typedef struct {
    uint8_t data[BMX_OBSERVE_PAYLOAD];
    uint16_t length;
    uint8_t code;
    uint32_t sequence;
} BmxObserveNotification;

static otCoapResource bmx_observe_resource;
static char bmx_observe_path[BMX_OBSERVE_PATH];
static int bmx_observe_subscriber;
static otMessageInfo bmx_observe_peer;
static otCoapToken bmx_observe_token;
static otMessage *bmx_observe_initial_request;
static uint32_t bmx_observe_sequence;

static int bmx_observe_client_active;
static int bmx_observe_client_error;
static otMessageInfo bmx_observe_client_peer;
static otCoapToken bmx_observe_client_token;
static char bmx_observe_client_path[BMX_OBSERVE_PATH];
static BmxObserveNotification bmx_observe_queue[BMX_OBSERVE_QUEUE];
static unsigned bmx_observe_head, bmx_observe_count, bmx_observe_dropped;

static void bmx_observe_simple_reply(otMessage *request, const otMessageInfo *info,
                                     otCoapCode code) {
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *response = otCoapNewMessage(instance, NULL);
    if (!response) return;
    otCoapType type = otCoapMessageGetType(request) == OT_COAP_TYPE_CONFIRMABLE ?
                      OT_COAP_TYPE_ACKNOWLEDGMENT : OT_COAP_TYPE_NON_CONFIRMABLE;
    otError error = otCoapMessageInitResponse(response, request, type, code);
    if (!error) error = otCoapSendResponse(instance, response, info);
    if (error) otMessageFree(response);
}

static int bmx_observe_option(const otMessage *message, uint64_t *value) {
    otCoapOptionIterator iterator;
    if (otCoapOptionIteratorInit(&iterator, message) != OT_ERROR_NONE) return -1;
    if (!otCoapOptionIteratorGetFirstOptionMatching(&iterator, OT_COAP_OPTION_OBSERVE)) return 0;
    return otCoapOptionIteratorGetOptionUintValue(&iterator, value) == OT_ERROR_NONE ? 1 : -1;
}

static void bmx_observe_handle_request(void *context, otMessage *message,
                                       const otMessageInfo *info) {
    (void)context;
    uint64_t option = 0;
    int has_option = bmx_observe_option(message, &option);
    if (otCoapMessageGetCode(message) != OT_COAP_CODE_GET || has_option < 0 ||
        !has_option || option > 1) {
        bmx_observe_simple_reply(message, info, OT_COAP_CODE_BAD_OPTION);
        return;
    }
    otCoapToken token;
    if (otCoapMessageReadToken(message, &token) != OT_ERROR_NONE) return;
    int same = bmx_observe_subscriber &&
               !memcmp(&info->mPeerAddr, &bmx_observe_peer.mPeerAddr, sizeof(otIp6Address)) &&
               info->mPeerPort == bmx_observe_peer.mPeerPort &&
               token.mLength == bmx_observe_token.mLength &&
               !memcmp(token.m8, bmx_observe_token.m8, token.mLength);
    if (option == 1) {
        if (same) {
            bmx_observe_subscriber = 0;
            if (bmx_observe_initial_request) {
                otMessageFree(bmx_observe_initial_request);
                bmx_observe_initial_request = NULL;
            }
        }
        bmx_observe_simple_reply(message, info, same ? OT_COAP_CODE_CONTENT : OT_COAP_CODE_NOT_FOUND);
        return;
    }
    if (bmx_observe_subscriber) {
        bmx_observe_simple_reply(message, info, OT_COAP_CODE_SERVICE_UNAVAILABLE);
        return;
    }
    otMessage *copy = otMessageClone(message);
    if (!copy) {
        bmx_observe_simple_reply(message, info, OT_COAP_CODE_SERVICE_UNAVAILABLE);
        return;
    }
    bmx_observe_peer = *info;
    bmx_observe_token = token;
    bmx_observe_initial_request = copy;
    bmx_observe_sequence = 0;
    bmx_observe_subscriber = 1;
}

static void bmx_observe_handle_notification(void *context, otMessage *message,
                                             const otMessageInfo *info, otError error) {
    (void)context;
    (void)info;
    if (!bmx_observe_client_active) return;
    if (error || !message) {
        bmx_observe_client_active = 0;
        bmx_observe_client_error = error ? -(int)error : -61;
        return;
    }
    uint64_t option = 0;
    int observed = bmx_observe_option(message, &option);
    if (observed <= 0) bmx_observe_client_active = 0;
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;
    if (length > BMX_OBSERVE_PAYLOAD) {
        ++bmx_observe_dropped;
        return;
    }
    if (bmx_observe_count == BMX_OBSERVE_QUEUE) {
        ++bmx_observe_dropped;
        return;
    }
    BmxObserveNotification *item = &bmx_observe_queue[(bmx_observe_head + bmx_observe_count) % BMX_OBSERVE_QUEUE];
    if (length && otMessageRead(message, offset, item->data, length) != length) {
        ++bmx_observe_dropped;
        return;
    }
    item->length = length;
    item->code = otCoapMessageGetCode(message);
    item->sequence = (uint32_t)option;
    ++bmx_observe_count;
}

int bmx_thread_coap_observe_resource(const char *path) {
    if (!path || !*path || strlen(path) >= BMX_OBSERVE_PATH) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_observe_resource.mUriPath) {
        bmx_thread_platform_unlock();
        return -16;
    }
    strcpy(bmx_observe_path, path);
    bmx_observe_resource.mUriPath = bmx_observe_path;
    bmx_observe_resource.mHandler = bmx_observe_handle_request;
    otCoapAddResource(bmx_thread_platform_instance(), &bmx_observe_resource);
    bmx_thread_platform_unlock();
    return 0;
}

int bmx_thread_coap_observe_has_subscriber(void) {
    bmx_thread_platform_lock();
    int result = bmx_observe_subscriber;
    bmx_thread_platform_unlock();
    return result;
}

int bmx_thread_coap_observe_publish(int code, const uint8_t *data, int length) {
    if (code < 64 || code > 95 || length < 0 || length > BMX_OBSERVE_PAYLOAD ||
        (length && !data)) return -22;
    bmx_thread_platform_lock();
    if (!bmx_observe_subscriber) {
        bmx_thread_platform_unlock();
        return -61;
    }
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *message = otCoapNewMessage(instance, NULL);
    otError error = message ? OT_ERROR_NONE : OT_ERROR_NO_BUFS;
    if (!error && bmx_observe_initial_request) {
        otCoapType type = otCoapMessageGetType(bmx_observe_initial_request) == OT_COAP_TYPE_CONFIRMABLE ?
                          OT_COAP_TYPE_ACKNOWLEDGMENT : OT_COAP_TYPE_NON_CONFIRMABLE;
        error = otCoapMessageInitResponse(message, bmx_observe_initial_request, type, (otCoapCode)code);
    } else if (!error) {
        error = otCoapMessageInit(message, OT_COAP_TYPE_NON_CONFIRMABLE, (otCoapCode)code);
        if (!error) error = otCoapMessageWriteToken(message, &bmx_observe_token);
    }
    if (!error) error = otCoapMessageAppendObserveOption(message, bmx_observe_sequence);
    if (!error && length) error = otCoapMessageSetPayloadMarker(message);
    if (!error && length) error = otMessageAppend(message, data, (uint16_t)length);
    if (!error) error = otCoapSendResponse(instance, message, &bmx_observe_peer);
    if (error && message) otMessageFree(message);
    if (!error) {
        if (bmx_observe_initial_request) {
            otMessageFree(bmx_observe_initial_request);
            bmx_observe_initial_request = NULL;
        }
        bmx_observe_sequence = (bmx_observe_sequence + 1) & 0xffffff;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_observe_subscribe(const char *address, int port, const char *path) {
    if (!address || !path || !*path || strlen(path) >= BMX_OBSERVE_PATH ||
        port < 1 || port > 65535) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_observe_client_active) {
        bmx_thread_platform_unlock();
        return -16;
    }
    otError error = otIp6AddressFromString(address, &bmx_observe_client_peer.mPeerAddr);
    bmx_observe_client_peer.mPeerPort = (uint16_t)port;
    otMessage *message = NULL;
    if (!error) message = otCoapNewMessage(bmx_thread_platform_instance(), NULL);
    if (!error && !message) error = OT_ERROR_NO_BUFS;
    if (!error) error = otCoapMessageInit(message, OT_COAP_TYPE_CONFIRMABLE, OT_COAP_CODE_GET);
    if (!error) otCoapMessageGenerateToken(message, 4);
    if (!error) error = otCoapMessageReadToken(message, &bmx_observe_client_token);
    if (!error) error = otCoapMessageAppendObserveOption(message, 0);
    if (!error) error = otCoapMessageAppendUriPathOptions(message, path);
    if (!error) {
        strcpy(bmx_observe_client_path, path);
        bmx_observe_client_error = 0;
        bmx_observe_head = bmx_observe_count = bmx_observe_dropped = 0;
        bmx_observe_client_active = 1;
        error = otCoapSendRequest(bmx_thread_platform_instance(), message,
                                   &bmx_observe_client_peer,
                                   bmx_observe_handle_notification, NULL);
    }
    if (error) {
        if (message) otMessageFree(message);
        bmx_observe_client_active = 0;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_coap_observe_read(uint8_t *data, int capacity, int *code, uint32_t *sequence) {
    if (!data || capacity < 0 || !code || !sequence) return -22;
    bmx_thread_platform_lock();
    int length = bmx_observe_client_error ? bmx_observe_client_error : -11;
    if (bmx_observe_count) {
        BmxObserveNotification *item = &bmx_observe_queue[bmx_observe_head];
        length = item->length;
        if (capacity < length) length = -90;
        if (length >= 0) {
            if (length) memcpy(data, item->data, length);
            *code = item->code;
            *sequence = item->sequence;
            bmx_observe_head = (bmx_observe_head + 1) % BMX_OBSERVE_QUEUE;
            --bmx_observe_count;
        }
    }
    bmx_thread_platform_unlock();
    return length;
}

uint32_t bmx_thread_coap_observe_dropped(void) {
    bmx_thread_platform_lock();
    uint32_t count = bmx_observe_dropped;
    bmx_thread_platform_unlock();
    return count;
}

int bmx_thread_coap_observe_cancel(void) {
    bmx_thread_platform_lock();
    if (!bmx_observe_client_active) {
        bmx_thread_platform_unlock();
        return -61;
    }
    otInstance *instance = bmx_thread_platform_instance();
    otMessage *message = otCoapNewMessage(instance, NULL);
    otError error = message ? OT_ERROR_NONE : OT_ERROR_NO_BUFS;
    if (!error) error = otCoapMessageInit(message, OT_COAP_TYPE_CONFIRMABLE, OT_COAP_CODE_GET);
    if (!error) error = otCoapMessageWriteToken(message, &bmx_observe_client_token);
    if (!error) error = otCoapMessageAppendObserveOption(message, 1);
    if (!error) error = otCoapMessageAppendUriPathOptions(message, bmx_observe_client_path);
    if (!error) error = otCoapSendRequest(instance, message, &bmx_observe_client_peer, NULL, NULL);
    if (error && message) otMessageFree(message);
    if (!error) bmx_observe_client_active = 0;
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}
