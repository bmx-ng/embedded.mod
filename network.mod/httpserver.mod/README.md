# Embedded.Network.HTTPServer

`Embedded.Network.HTTPServer` is a single-managed-context HTTP/1.0 and HTTP/1.1
server. The same route and response code builds for ESP32 and Pico W. Its
transport uses `BRL.Socket`; handlers run only inside the application's call to
`Service()`.

## Current capabilities

- GET, HEAD, POST and PUT; exact and `:parameter` routes; bounded query and header
  access; text, HTML, JSON, bytes, redirect and length-known stream responses.
- Responses include `Content-Length`; HEAD sends the corresponding headers and
  no body. Connections close by default. Set `keepAlive = True` to reuse an
  HTTP/1.1 connection for sequential requests, bounded by
  `maxRequestsPerConnection` and `keepAliveTimeoutMs`. HTTP/1.0 still closes.
- Static files use `BRL.FileSystem` metadata and `ReadStream`, so mounted
  `littlefs::` and `sd::` paths use the same transfer loop. Files are read in
  configured chunks. Directory URLs resolve to `index.html`.
- Strict CRLF framing, HTTP/1.1 Host requirement, numeric Content-Length,
  rejection of duplicate lengths and conflicting Content-Length/Transfer-Encoding,
  and rejection of unsupported encodings and Expect headers. Chunked request
  bodies are accepted with bounded size lines and trailers; trailer fields are
  validated and discarded. Requests already buffered after a completed request
  cause that connection to close; pipelining is not a supported API.
- `RouteStream()` receives large POST/PUT bodies in bounded chunks without
  buffering the whole upload. A separate total-body limit remains in force.
- Handler exceptions produce a 500 response when the connection is still
  writable. `LastError()` records the failed route and exception detail; the
  client receives only the generic status. An interrupted streaming request
  invokes its `Abort()` callback for partial-file cleanup.
- URL paths and query strings are ASCII in this milestone. Encoded path
  separators, backslashes, NUL, controls and `.`/`..` static-file segments are
  rejected. LittleFS and FAT mounts do not expose symbolic links. A backend
  with symbolic links needs an additional containment check before it is used
  as an untrusted document root.

## Basic use

```blitzmax
Local server:THTTPServer = THTTPServer.Create()
server.Route("GET", "/status", New TStatusHandler)
server.Static("/files/", "littlefs::/www/")
If Not server.Start() Then RuntimeError server.LastError()

While True
    PollSystem()
    server.Service(4)
    Delay 1
Wend
```

`Service(maxSteps)` performs at most `maxSteps` accepts and connection steps.
Call it frequently on the managed application task or Pico core 0. Network
reads and writes return immediately when the socket is not ready. A filesystem
operation or application handler can still take time; handlers should avoid
blocking and use streams for large files. `Stop()` closes all active sockets
and streams and permits `Start()` again. Routes are registered before `Start()`;
`ActiveConnections()` helps an application wait until responses complete before
a planned restart.

For an upload, implement `IHTTPBodyHandler` and register it with
`RouteStream("POST", "/upload", handler)`. `Begin()` runs after the headers,
`Chunk()` receives at most `ioBufferBytes` bytes per call, and `Complete()` runs
after the declared body length or final chunk has arrived. The request's
`context` field can hold per-upload state. `Abort()` runs if the peer
disconnects, the body times out, or a callback fails before completion. Close
and delete any partial file there. All callbacks run inside `Service()` and
should return promptly. The
default total limit for streamed bodies is 1 MiB; set
`maxStreamBodyBytes` for the application, up to 64 MiB. Ordinary `Route()`
handlers retain the separate 1 KiB default buffered-body limit.

## HTTPS on ESP32 and Pico W

Import `Embedded.Network.HTTPSTLS` to add the board SDK's mbedTLS server
library. Supply a PEM certificate and matching PEM private key as strings;
keep the key in a local ignored configuration file or load it from protected
device storage. Then pass the listener to the normal server constructor:

```blitzmax
Import Embedded.Network.HTTPSTLS

Local config:THTTPServerConfig = New THTTPServerConfig
config.port = 443
Local tls:THTTPSTLSListener = THTTPSTLSListener.Create(certPEM, keyPEM)
Local server:THTTPServer = THTTPServer.Create(config, tls)
server.Route("GET", "/status", New TStatusHandler)
If Not server.Start() Then RuntimeError server.LastError()
```

Use the same `Service()` loop as HTTP. Handshakes and encrypted reads and
writes progress without blocking; the header timeout also bounds incomplete
handshakes. `Stop()` releases active TLS connections before the shared TLS
configuration. Plain HTTP applications need no TLS import or library. The
Pico build links its SDK `pico_mbedtls` target with a TLS 1.2 configuration;
the ESP32 build links ESP-IDF's mbedTLS 4 component. The server presents the
configured certificate. Applications must arrange a trusted certificate and
key; this module does not provision them.

The supplied [device example](examples/device_api.bmx) has a status/JSON route,
a token-protected GPIO route, LittleFS static files on both targets and
optional SD static files on ESP32, plus a bounded POST echo used by device
tests. Fill in `examples/device_api.local.bmx` with the Wi-Fi name, password,
a random control token and a board-safe GPIO pin. This file is ignored by Git;
build it instead of the tracked example. A 128 KiB managed heap was used for
the sustained Pico 2 W and ESP32-S3 device runs. Pico LittleFS also needs a
reserved storage area. ESP32 LittleFS needs
the board's `storage` partition; SD requires a board with configured SDMMC.
The generic `esp32s3_n16r8_littlefs128` profile reserves 128 KiB for LittleFS
at flash offset `0x210000`, while keeping the NVS and application start
offsets of `esp32s3_n16r8`. This space holds static files; the HTTP server
does not need a storage partition for dynamic routes.
GPIO control starts disabled (`EnableGPIO = False`) so the HTTP routes can be
tested without switching a physical pin. Enable it only after checking the
specific board's pinout. Static routes are registered when their storage mounts.

## Resource defaults

| Resource | Default |
| --- | ---: |
| Active clients | 1 |
| Routes | 16 |
| Request line | 256 bytes |
| Header block / count | 1024 bytes / 16 |
| Buffered request body | 1024 bytes |
| Streamed request total | 1 MiB |
| Response body helper | 1024 bytes |
| Stream transfer buffer | 512 bytes |
| Header / body / write timeout | 5 s / 10 s / 10 s |
| Keep-alive | Off; 5 s idle, at most 16 requests when enabled |

Pico's native socket layer also allocates a 4 KiB receive ring per accepted
TCP socket and has eight socket slots in total. Increase connection limits only
after sizing the managed heap and testing memory pressure on the board. The
configuration currently permits up to four active clients. Handler-provided
response bodies above the configured limit receive a 500 response; large
payloads should use a length-known stream. On allocation or stream exceptions,
the affected connection is closed.

## Tests and remaining work

`tests/run_httpserver_host.sh` builds a host server and runs wire tests for
fragmented requests, method and framing errors, limits, slow clients,
concurrency, disconnects, streamed files, traversal and repeated start/stop.
Set `BMX_BMK` to the desired build tool if necessary. The device example builds
for Pico W and ESP32-S3. After flashing a locally configured example, run
`python3 tests/test_httpserver_device.py BOARD_IP` against each board. Pass
`--static-path /files/large.txt --static-sha256 HASH` to check a known file on
LittleFS, or `/sd/...` on an ESP32 SD mount. The device wire tests, including
a 16 KiB LittleFS transfer checked by SHA-256, pass on a Pico 2 W and ESP32-S3.
Mixed status, maximum-size echo and file-transfer runs passed 150 requests on
Pico 2 W and 300 requests on ESP32-S3 with 128 KiB heaps. A 64 KiB ESP32-S3
run dropped a connection during the same mix. For the largest configured limits
(four connections, 4 KiB headers, 8 KiB request and response bodies, and 2 KiB
transfer buffers), run `tests/test_httpserver_pressure.py BOARD_IP` with an
image built for those settings. Ten four-client rounds, interrupted bodies,
recovery and a static-file checksum passed on Pico 2 W with a 384 KiB managed
heap. The same test passed on ESP32-S3 with a 512 KiB managed heap in PSRAM
(`-heap-region psram -heap 512k`). Smaller Pico heaps and ESP32-S3 internal
SRAM heaps of 128 and 192 KiB dropped connections at those limits. A 256 KiB
ESP32-S3 internal SRAM heap could not start. The ordinary example still uses
the smaller resource defaults above and passed its device wire tests again
after restoration on both boards.

Chunked responses for unknown-length streams, range/cache responses, SSE,
WebSockets, multipart, authentication helpers, captive-portal workflows and
OTA are later layers. The HTTPS adapter builds for Pico 2 W and ESP32-S3. A
verified handshake, GET, fragmented POST, 404 response, and 30 repeated connections
passed on both Pico 2 W and ESP32-S31. After flashing an HTTPS variant of the
device example with a test certificate, run
`python3 tests/test_httpserver_tls_device.py BOARD_IP test-cert.pem`. The test
checks a trusted handshake, GET, a fragmented POST and a 404 response.

For the optional connection reuse and chunked-body image, run
`python3 tests/test_httpserver_next_device.py BOARD_IP`. It checks sequential
requests on one connection, a fragmented chunked echo, a 32 KiB streamed
chunked upload, and conflicting framing rejection. These checks passed on an
ESP32-S31.
