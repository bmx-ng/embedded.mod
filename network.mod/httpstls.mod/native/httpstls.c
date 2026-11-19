/* Copyright (c) 2026 Bruce A Henderson and contributors
 * SPDX-License-Identifier: Zlib */
#include <stdlib.h>
#include <string.h>
#include <mbedtls/build_info.h>
#if MBEDTLS_VERSION_MAJOR >= 4
#include <psa/crypto.h>
#else
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/entropy.h>
#endif
#include <mbedtls/pk.h>
#include <mbedtls/ssl.h>
#include <mbedtls/x509_crt.h>

extern int bmx_net_try_send(int socket, const void *buffer, size_t count);
extern int bmx_net_try_recv(int socket, void *buffer, size_t count);

typedef struct {
#if MBEDTLS_VERSION_MAJOR < 4
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context rng;
#endif
    mbedtls_ssl_config config;
    mbedtls_x509_crt certificate;
    mbedtls_pk_context key;
} BMXHTTPSTLS;

typedef struct {
    mbedtls_ssl_context ssl;
    int socket;
    int handshaken;
} BMXHTTPSTLSConnection;

static int tls_last_stage;
static int tls_last_error;

int bmx_httpstls_last_stage(void) { return tls_last_stage; }
int bmx_httpstls_last_error(void) { return tls_last_error; }

static int tls_send(void *context, const unsigned char *buffer, size_t count) {
    int result = bmx_net_try_send(((BMXHTTPSTLSConnection *)context)->socket, buffer, count);
    return result == -2 ? MBEDTLS_ERR_SSL_WANT_WRITE :
        result < 0 ? MBEDTLS_ERR_SSL_INTERNAL_ERROR : result;
}

static int tls_recv(void *context, unsigned char *buffer, size_t count) {
    int result = bmx_net_try_recv(((BMXHTTPSTLSConnection *)context)->socket, buffer, count);
    return result == -2 ? MBEDTLS_ERR_SSL_WANT_READ :
        result < 0 ? MBEDTLS_ERR_SSL_INTERNAL_ERROR : result;
}

void bmx_httpstls_free(BMXHTTPSTLS *server) {
    if (!server) return;
    mbedtls_ssl_config_free(&server->config);
    mbedtls_x509_crt_free(&server->certificate);
    mbedtls_pk_free(&server->key);
#if MBEDTLS_VERSION_MAJOR < 4
    mbedtls_ctr_drbg_free(&server->rng);
    mbedtls_entropy_free(&server->entropy);
#endif
    free(server);
}

BMXHTTPSTLS *bmx_httpstls_create(const unsigned char *certificate, size_t certificate_length,
    const unsigned char *key, size_t key_length) {
    tls_last_stage = 0;
    tls_last_error = 0;
    if (!certificate || !key || certificate_length < 2 || key_length < 2) return NULL;
    BMXHTTPSTLS *server = (BMXHTTPSTLS *)calloc(1, sizeof(*server));
    if (!server) return NULL;
#if MBEDTLS_VERSION_MAJOR < 4
    mbedtls_entropy_init(&server->entropy);
    mbedtls_ctr_drbg_init(&server->rng);
#endif
    mbedtls_ssl_config_init(&server->config);
    mbedtls_x509_crt_init(&server->certificate);
    mbedtls_pk_init(&server->key);
    int result;
#if MBEDTLS_VERSION_MAJOR >= 4
    result = psa_crypto_init() == PSA_SUCCESS ? 0 : -1;
#else
    static const unsigned char label[] = "BlitzMax HTTPS";
    result = mbedtls_ctr_drbg_seed(&server->rng, mbedtls_entropy_func,
        &server->entropy, label, sizeof(label) - 1);
#endif
    if (result) tls_last_stage = 1;
    if (!result) result = mbedtls_x509_crt_parse(&server->certificate,
        certificate, certificate_length);
    if (result && !tls_last_stage) tls_last_stage = 2;
#if MBEDTLS_VERSION_MAJOR >= 4
    if (!result) result = mbedtls_pk_parse_key(&server->key, key, key_length, NULL, 0);
#else
    if (!result) result = mbedtls_pk_parse_key(&server->key, key, key_length,
        NULL, 0, mbedtls_ctr_drbg_random, &server->rng);
#endif
    if (result && !tls_last_stage) tls_last_stage = 3;
    if (!result) result = mbedtls_ssl_config_defaults(&server->config,
        MBEDTLS_SSL_IS_SERVER, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
    if (result && !tls_last_stage) tls_last_stage = 4;
    if (!result) {
#if MBEDTLS_VERSION_MAJOR < 4
        mbedtls_ssl_conf_rng(&server->config, mbedtls_ctr_drbg_random, &server->rng);
#endif
        result = mbedtls_ssl_conf_own_cert(&server->config,
            &server->certificate, &server->key);
    }
    if (result && !tls_last_stage) tls_last_stage = 5;
    if (result) {
        tls_last_error = result;
        bmx_httpstls_free(server);
        return NULL;
    }
    return server;
}

BMXHTTPSTLSConnection *bmx_httpstls_accept(BMXHTTPSTLS *server, int socket) {
    if (!server) return NULL;
    BMXHTTPSTLSConnection *connection = (BMXHTTPSTLSConnection *)calloc(1, sizeof(*connection));
    if (!connection) return NULL;
    connection->socket = socket;
    mbedtls_ssl_init(&connection->ssl);
    if (mbedtls_ssl_setup(&connection->ssl, &server->config)) {
        mbedtls_ssl_free(&connection->ssl);
        free(connection);
        return NULL;
    }
    mbedtls_ssl_set_bio(&connection->ssl, connection, tls_send, tls_recv, NULL);
    return connection;
}

static int tls_ready(BMXHTTPSTLSConnection *connection) {
    if (connection->handshaken) return 1;
    int result = mbedtls_ssl_handshake(&connection->ssl);
    if (!result) {
        connection->handshaken = 1;
        return 1;
    }
    return result == MBEDTLS_ERR_SSL_WANT_READ || result == MBEDTLS_ERR_SSL_WANT_WRITE ? -2 : -1;
}

int bmx_httpstls_recv(BMXHTTPSTLSConnection *connection, unsigned char *buffer, size_t count) {
    if (!connection || !buffer) return -1;
    int ready = tls_ready(connection);
    if (ready != 1) return ready;
    int result = mbedtls_ssl_read(&connection->ssl, buffer, count);
    return result == MBEDTLS_ERR_SSL_WANT_READ || result == MBEDTLS_ERR_SSL_WANT_WRITE ? -2 :
        result < 0 ? -1 : result;
}

int bmx_httpstls_send(BMXHTTPSTLSConnection *connection, const unsigned char *buffer, size_t count) {
    if (!connection || !buffer) return -1;
    int ready = tls_ready(connection);
    if (ready != 1) return ready;
    int result = mbedtls_ssl_write(&connection->ssl, buffer, count);
    return result == MBEDTLS_ERR_SSL_WANT_READ || result == MBEDTLS_ERR_SSL_WANT_WRITE ? -2 :
        result < 0 ? -1 : result;
}

void bmx_httpstls_close(BMXHTTPSTLSConnection *connection) {
    if (!connection) return;
    if (connection->handshaken) (void)mbedtls_ssl_close_notify(&connection->ssl);
    mbedtls_ssl_free(&connection->ssl);
    free(connection);
}
