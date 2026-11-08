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
#define BMX_DISCOVERY_RESULTS 8

static otSrpClientService bmx_service;
static char bmx_host_name[BMX_DISCOVERY_NAME];
static char bmx_instance_name[BMX_DISCOVERY_NAME];
static char bmx_service_type[BMX_DISCOVERY_NAME];
static int bmx_service_state = -61;
static int bmx_service_active;
static int bmx_service_removing;

static char bmx_browse_type[BMX_DISCOVERY_FULL_NAME];
static char bmx_resolve_type[BMX_DISCOVERY_FULL_NAME];
static char bmx_browse_labels[BMX_DISCOVERY_RESULTS][BMX_DISCOVERY_NAME];
static int bmx_browse_state = -61;
static int bmx_browse_count;
static int bmx_resolve_state = -61;
static char bmx_resolve_address[OT_IP6_ADDRESS_STRING_SIZE];
static char bmx_resolve_host[BMX_DISCOVERY_NAME * 2];
static int bmx_resolve_port;

static int bmx_full_service_name(char *target, const char *service_type) {
    static const char suffix[] = ".default.service.arpa";
    if (!service_type || !*service_type ||
        strlen(service_type) >= BMX_DISCOVERY_NAME ||
        strlen(service_type) + sizeof(suffix) > BMX_DISCOVERY_FULL_NAME) return -22;
    strcpy(target, service_type);
    strcat(target, suffix);
    return 0;
}

static void bmx_service_changed(otError error, const otSrpClientHostInfo *host,
                                const otSrpClientService *services,
                                const otSrpClientService *removed, void *context) {
    (void)host;
    (void)services;
    (void)removed;
    (void)context;
    bmx_service_state = error ? -(int)error : 0;
    if (!error && bmx_service_removing) {
        bmx_service_active = 0;
        bmx_service_removing = 0;
    }
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

int bmx_thread_service_publish(const char *host, const char *instance_name,
                               const char *service_type, int port) {
    if (!host || !instance_name || !service_type || port < 1 || port > 65535 ||
        !*host || !*instance_name || !*service_type ||
        strlen(host) >= BMX_DISCOVERY_NAME || strlen(instance_name) >= BMX_DISCOVERY_NAME ||
        strlen(service_type) >= BMX_DISCOVERY_NAME) return -22;
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (bmx_service_active) {
        bmx_thread_platform_unlock();
        return -16;
    }
    otInstance *ot = bmx_thread_platform_instance();
    otSrpClientClearHostAndServices(ot);
    strcpy(bmx_host_name, host);
    strcpy(bmx_instance_name, instance_name);
    strcpy(bmx_service_type, service_type);
    otSrpClientSetCallback(ot, bmx_service_changed, NULL);
    otError error = otSrpClientSetHostName(ot, bmx_host_name);
    if (!error) error = otSrpClientEnableAutoHostAddress(ot);
    if (!error) {
        memset(&bmx_service, 0, sizeof(bmx_service));
        bmx_service.mName = bmx_service_type;
        bmx_service.mInstanceName = bmx_instance_name;
        bmx_service.mPort = (uint16_t)port;
        error = otSrpClientAddService(ot, &bmx_service);
    }
    if (!error) {
        bmx_service_active = 1;
        bmx_service_state = 1;
        otSrpClientEnableAutoStartMode(ot, NULL, NULL);
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

int bmx_thread_service_publish_state(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    int state = bmx_service_state;
    bmx_thread_platform_unlock();
    return state;
}

int bmx_thread_service_unpublish(void) {
    int result = bmx_thread_initialize();
    if (result) return result;
    bmx_thread_platform_lock();
    if (!bmx_service_active) {
        bmx_thread_platform_unlock();
        return 0;
    }
    otError error = otSrpClientRemoveService(bmx_thread_platform_instance(), &bmx_service);
    if (!error) {
        bmx_service_removing = 1;
        bmx_service_state = 1;
    }
    bmx_thread_platform_unlock();
    return error ? -(int)error : 0;
}

static void bmx_browse_finished(otError error, const otDnsBrowseResponse *response, void *context) {
    (void)context;
    bmx_browse_count = 0;
    if (!error) {
        while (bmx_browse_count < BMX_DISCOVERY_RESULTS) {
            otError next = otDnsBrowseResponseGetServiceInstance(response, (uint16_t)bmx_browse_count,
                          bmx_browse_labels[bmx_browse_count], BMX_DISCOVERY_NAME);
            if (next) break;
            ++bmx_browse_count;
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
        error = otDnsServiceResponseGetServiceInfo(response, &info);
        if (!error) {
            bmx_resolve_port = info.mPort;
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
