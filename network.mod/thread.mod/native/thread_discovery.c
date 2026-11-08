/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib */
#include <stdint.h>
#include <string.h>
#if defined(ESP_PLATFORM)
#include "sdkconfig.h"
#endif

#include <openthread/dns_client.h>
#include <openthread/instance.h>
#include <openthread/ip6.h>
#include <openthread/srp_client.h>
#include <openthread/srp_server.h>

extern int bmx_thread_initialize(void);
extern otInstance *bmx_thread_platform_instance(void);
extern void bmx_thread_platform_lock(void);
extern void bmx_thread_platform_unlock(void);

#define BMX_DISCOVERY_NAME 64
#define BMX_DISCOVERY_FULL_NAME 128
#define BMX_DISCOVERY_RESULTS 32
#define BMX_PUBLISHED_SERVICES 8
#define BMX_DISCOVERY_TXT 1024

typedef struct {
    otSrpClientService service;
    otDnsTxtEntry txt_entry;
    char instance_name[BMX_DISCOVERY_NAME];
    char service_type[BMX_DISCOVERY_NAME];
    uint8_t txt[BMX_DISCOVERY_TXT];
    unsigned generation;
    int used;
    int removing;
    int release_when_removed;
    int state;
} BMXPublishedService;

static BMXPublishedService bmx_services[BMX_PUBLISHED_SERVICES];
static char bmx_host_name[BMX_DISCOVERY_NAME];
static int bmx_host_set;
static int bmx_legacy_service;

static char bmx_browse_type[BMX_DISCOVERY_FULL_NAME];
static char bmx_resolve_type[BMX_DISCOVERY_FULL_NAME];
static char bmx_browse_labels[BMX_DISCOVERY_RESULTS][BMX_DISCOVERY_NAME];
static int bmx_browse_state = -61;
static int bmx_browse_count;
static int bmx_browse_truncated;
static int bmx_resolve_state = -61;
static char bmx_resolve_address[OT_IP6_ADDRESS_STRING_SIZE];
static char bmx_resolve_host[BMX_DISCOVERY_NAME * 2];
static int bmx_resolve_port;
static uint8_t bmx_resolve_txt[BMX_DISCOVERY_TXT];
static int bmx_resolve_txt_length;
static int bmx_resolve_txt_truncated;

static int bmx_full_service_name(char *target, const char *service_type) {
    static const char suffix[] = ".default.service.arpa";
    if (!service_type || !*service_type ||
        strlen(service_type) >= BMX_DISCOVERY_NAME ||
        strlen(service_type) + sizeof(suffix) > BMX_DISCOVERY_FULL_NAME) return -22;
    strcpy(target, service_type);
    strcat(target, suffix);
    return 0;
}

static BMXPublishedService *bmx_service_slot(int handle) {
    unsigned slot = (unsigned)handle & 0xffu;
    unsigned generation = (unsigned)handle >> 8;
    if (!slot || slot > BMX_PUBLISHED_SERVICES || !generation) return NULL;
    BMXPublishedService *item = &bmx_services[slot - 1];
    return item->used && item->generation == generation ? item : NULL;
}

static int bmx_service_handle(BMXPublishedService *item) {
    return (int)((item->generation << 8) | (unsigned)(item - bmx_services + 1));
}

static void bmx_service_changed(otError error, const otSrpClientHostInfo *host,
                                const otSrpClientService *services,
                                const otSrpClientService *removed, void *context) {
    (void)host;
    (void)context;
    for (unsigned i = 0; i < BMX_PUBLISHED_SERVICES; ++i) {
        BMXPublishedService *item = &bmx_services[i];
        if (!item->used) continue;
        int found_removed = 0;
        for (const otSrpClientService *entry = removed; entry; entry = entry->mNext) {
            if (entry == &item->service) found_removed = 1;
        }
        if (!error && found_removed) {
            item->state = 2;
            item->removing = 0;
            int was_legacy = bmx_legacy_service == bmx_service_handle(item);
            if (was_legacy) bmx_legacy_service = 0;
            if (item->release_when_removed || was_legacy) item->used = 0;
            continue;
        }
        for (const otSrpClientService *entry = services; entry; entry = entry->mNext) {
            if (entry == &item->service) {
                if (!error || item->state == 1) item->state = error ? -(int)error : 0;
                break;
            }
        }
    }
}

static int bmx_valid_txt(const uint8_t *txt, int length) {
    if (length < 0 || length > BMX_DISCOVERY_TXT || (length && !txt)) return 0;
    for (int offset = 0; offset < length;) {
        int size = txt[offset++];
        if (size > length - offset) return 0;
        offset += size;
    }
    return 1;
}

int bmx_thread_service_server_enable(int enabled) {
#if defined(CONFIG_BMX_THREAD_SRP_SERVER) && CONFIG_BMX_THREAD_SRP_SERVER
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otSrpServerSetEnabled(bmx_thread_platform_instance(), enabled != 0);
    bmx_thread_platform_unlock();
    return 0;
#else
    (void)enabled;
    return -95;
#endif
}

int bmx_thread_service_server_state(void) {
#if defined(CONFIG_BMX_THREAD_SRP_SERVER) && CONFIG_BMX_THREAD_SRP_SERVER
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int state = (int)otSrpServerGetState(bmx_thread_platform_instance());
    bmx_thread_platform_unlock();
    return state;
#else
    return -95;
#endif
}

int bmx_thread_service_client_enable(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    otSrpClientEnableAutoStartMode(bmx_thread_platform_instance(), NULL, NULL);
    bmx_thread_platform_unlock();
    return 0;
}

int bmx_thread_service_client_running(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int running = otSrpClientIsRunning(bmx_thread_platform_instance());
    bmx_thread_platform_unlock();
    return running;
}

int bmx_thread_service_publish_ex(const char *host, const char *instance_name,
                                  const char *service_type, int port,
                                  const uint8_t *txt, int txt_length) {
    if (!host || !instance_name || !service_type || port < 1 || port > 65535 ||
        !*host || !*instance_name || !*service_type ||
        strlen(host) >= BMX_DISCOVERY_NAME || strlen(instance_name) >= BMX_DISCOVERY_NAME ||
        strlen(service_type) >= BMX_DISCOVERY_NAME || !bmx_valid_txt(txt, txt_length)) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    unsigned i;
    for (i = 0; i < BMX_PUBLISHED_SERVICES && bmx_services[i].used; ++i) {}
    if (i == BMX_PUBLISHED_SERVICES) {
        bmx_thread_platform_unlock();
        return -24;
    }
    otInstance *ot = bmx_thread_platform_instance();
    if (bmx_host_set && strcmp(host, bmx_host_name)) {
        int active = 0;
        for (unsigned j = 0; j < BMX_PUBLISHED_SERVICES; ++j) active |= bmx_services[j].used;
        if (active) {
            bmx_thread_platform_unlock();
            return -22;
        }
        otSrpClientClearHostAndServices(ot);
        bmx_host_set = 0;
    }
    otSrpClientSetCallback(ot, bmx_service_changed, NULL);
    otError error = OT_ERROR_NONE;
    if (!bmx_host_set) {
        strcpy(bmx_host_name, host);
        error = otSrpClientSetHostName(ot, bmx_host_name);
        if (!error) error = otSrpClientEnableAutoHostAddress(ot);
        if (!error) bmx_host_set = 1;
    }
    BMXPublishedService *item = &bmx_services[i];
    if (!error) {
        unsigned generation = (item->generation + 1) & 0x7fffff;
        memset(item, 0, sizeof(*item));
        item->generation = generation ? generation : 1;
        strcpy(item->instance_name, instance_name);
        strcpy(item->service_type, service_type);
        item->service.mName = item->service_type;
        item->service.mInstanceName = item->instance_name;
        item->service.mPort = (uint16_t)port;
        if (txt_length) {
            memcpy(item->txt, txt, (size_t)txt_length);
            item->txt_entry.mValue = item->txt;
            item->txt_entry.mValueLength = (uint16_t)txt_length;
            item->service.mTxtEntries = &item->txt_entry;
            item->service.mNumTxtEntries = 1;
        }
        error = otSrpClientAddService(ot, &item->service);
    }
    int handle = error ? -(int)error : bmx_service_handle(item);
    if (!error) {
        item->used = 1;
        item->state = 1;
        otSrpClientEnableAutoStartMode(ot, NULL, NULL);
    }
    bmx_thread_platform_unlock();
    return handle;
}

int bmx_thread_service_state(int handle) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    BMXPublishedService *item = bmx_service_slot(handle);
    int state = item ? item->state : -107;
    bmx_thread_platform_unlock();
    return state;
}

int bmx_thread_service_remove(int handle) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    BMXPublishedService *item = bmx_service_slot(handle);
    if (!item) {
        bmx_thread_platform_unlock();
        return -107;
    }
    if (item->state == 2 || item->removing) {
        bmx_thread_platform_unlock();
        return 0;
    }
    otError error = otSrpClientRemoveService(bmx_thread_platform_instance(), &item->service);
    if (!error) {
        item->removing = 1;
        item->state = 1;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_service_release(int handle) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    BMXPublishedService *item = bmx_service_slot(handle);
    if (!item) {
        bmx_thread_platform_unlock();
        return -107;
    }
    if (item->state == 2) {
        item->used = 0;
        bmx_thread_platform_unlock();
        return 0;
    }
    otError error = OT_ERROR_NONE;
    if (!item->removing) error = otSrpClientRemoveService(bmx_thread_platform_instance(), &item->service);
    if (!error) {
        item->removing = 1;
        item->release_when_removed = 1;
        item->state = 1;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_service_publish(const char *host, const char *instance_name,
                               const char *service_type, int port) {
    if (bmx_legacy_service) return -16;
    int handle = bmx_thread_service_publish_ex(host, instance_name, service_type, port, NULL, 0);
    if (handle < 0) return handle;
    bmx_legacy_service = handle;
    return 0;
}

int bmx_thread_service_publish_state(void) {
    return bmx_legacy_service ? bmx_thread_service_state(bmx_legacy_service) : 0;
}

int bmx_thread_service_unpublish(void) {
    return bmx_legacy_service ? bmx_thread_service_remove(bmx_legacy_service) : 0;
}

static void bmx_browse_finished(otError error, const otDnsBrowseResponse *response, void *context) {
    (void)context;
    bmx_browse_count = 0;
    bmx_browse_truncated = 0;
    if (!error) {
        while (bmx_browse_count < BMX_DISCOVERY_RESULTS) {
            otError next = otDnsBrowseResponseGetServiceInstance(response, (uint16_t)bmx_browse_count,
                          bmx_browse_labels[bmx_browse_count], BMX_DISCOVERY_NAME);
            if (next) break;
            ++bmx_browse_count;
        }
        if (bmx_browse_count == BMX_DISCOVERY_RESULTS) {
            char extra[BMX_DISCOVERY_NAME];
            bmx_browse_truncated =
                otDnsBrowseResponseGetServiceInstance(response, BMX_DISCOVERY_RESULTS,
                                                     extra, sizeof(extra)) == OT_ERROR_NONE;
        }
    }
    bmx_browse_state = error ? -(int)error : 0;
}

int bmx_thread_service_browse(const char *service_type) {
    if (!service_type || !*service_type || strlen(service_type) >= BMX_DISCOVERY_NAME) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_browse_state == 1) {
        bmx_thread_platform_unlock();
        return -16;
    }
    bmx_full_service_name(bmx_browse_type, service_type);
    bmx_browse_count = 0;
    bmx_browse_truncated = 0;
    otError error = otDnsClientBrowse(bmx_thread_platform_instance(), bmx_browse_type,
                                      bmx_browse_finished, NULL, NULL);
    bmx_browse_state = error ? -(int)error : 1;
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_service_browse_state(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int state = bmx_browse_state;
    bmx_thread_platform_unlock();
    return state;
}

int bmx_thread_service_browse_count(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int count = bmx_browse_state == 0 ? bmx_browse_count : bmx_browse_state;
    bmx_thread_platform_unlock();
    return count;
}

int bmx_thread_service_browse_truncated(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int truncated = bmx_browse_state == 0 ? bmx_browse_truncated : 0;
    bmx_thread_platform_unlock();
    return truncated;
}

int bmx_thread_service_browse_result(int index, char *label, int capacity) {
    if (!label || capacity < BMX_DISCOVERY_NAME || index < 0) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int length = 0;
    if (bmx_browse_state == 0 && index < bmx_browse_count) {
        strcpy(label, bmx_browse_labels[index]);
        length = (int)strlen(label);
    }
    bmx_thread_platform_unlock();
    return length;
}

static void bmx_resolve_finished(otError error, const otDnsServiceResponse *response, void *context) {
    (void)context;
    if (!error) {
        otDnsServiceInfo info = {0};
        info.mHostNameBuffer = bmx_resolve_host;
        info.mHostNameBufferSize = sizeof(bmx_resolve_host);
        info.mTxtData = bmx_resolve_txt;
        info.mTxtDataSize = sizeof(bmx_resolve_txt);
        error = otDnsServiceResponseGetServiceInfo(response, &info);
        if (!error) {
            bmx_resolve_port = info.mPort;
            bmx_resolve_txt_length = info.mTxtDataSize;
            bmx_resolve_txt_truncated = info.mTxtDataTruncated;
            otIp6AddressToString(&info.mHostAddress, bmx_resolve_address, sizeof(bmx_resolve_address));
        }
    }
    bmx_resolve_state = error ? -(int)error : 0;
}

int bmx_thread_service_resolve(const char *instance_name, const char *service_type) {
    if (!instance_name || !*instance_name || strlen(instance_name) >= BMX_DISCOVERY_NAME ||
        !service_type || !*service_type || strlen(service_type) >= BMX_DISCOVERY_NAME) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_resolve_state == 1) {
        bmx_thread_platform_unlock();
        return -16;
    }
    bmx_full_service_name(bmx_resolve_type, service_type);
    bmx_resolve_txt_length = 0;
    bmx_resolve_txt_truncated = 0;
    otError error = otDnsClientResolveServiceAndHostAddress(bmx_thread_platform_instance(),
                         instance_name, bmx_resolve_type, bmx_resolve_finished, NULL, NULL);
    bmx_resolve_state = error ? -(int)error : 1;
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_service_resolve_state(char *address, int capacity, int *port) {
    if (!address || capacity < OT_IP6_ADDRESS_STRING_SIZE || !port) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int state = bmx_resolve_state;
    if (!state) {
        strcpy(address, bmx_resolve_address);
        *port = bmx_resolve_port;
    }
    bmx_thread_platform_unlock();
    return state;
}

int bmx_thread_service_resolved_txt(uint8_t *txt, int capacity, int *truncated) {
    if (!txt || capacity < 0 || !truncated) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int length = bmx_resolve_state == 0 ? bmx_resolve_txt_length : bmx_resolve_state;
    if (length >= 0 && capacity < length) length = -90;
    if (length >= 0) {
        memcpy(txt, bmx_resolve_txt, (size_t)length);
        *truncated = bmx_resolve_txt_truncated;
    }
    bmx_thread_platform_unlock();
    return length;
}
