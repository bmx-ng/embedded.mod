/* Mbed TLS 4 no longer accepts an RNG callback in mbedtls_pk_parse_key().
 * Force-include this only for OpenThread builds that still pass the callback. */
#include <mbedtls/build_info.h>
#include <mbedtls/pk.h>
#if MBEDTLS_VERSION_MAJOR >= 4
#define mbedtls_pk_parse_key(ctx, key, key_len, pwd, pwd_len, ...) \
    mbedtls_pk_parse_key(ctx, key, key_len, pwd, pwd_len)
#endif
