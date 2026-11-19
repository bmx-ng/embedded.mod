# Embedded.Network.HTTPServer

`Embedded.Network.HTTPServer` is a single-managed-context HTTP/1.0 and HTTP/1.1
server. The same route and response code builds for ESP32 and Pico W. Its
transport uses `BRL.Socket`; handlers run only inside the application's call to
`Service()`.

## Current capabilities

- GET, HEAD, POST and PUT; exact and `:parameter` routes; bounded query and header
  access; text, HTML, JSON, bytes, redirect and streamed responses.
- `StreamUnknown()` sends a stream until EOF. `Produce()` accepts a nonblocking
  source that can wait for data. HTTP/1.1 uses chunked transfer encoding;
  HTTP/1.0 closes the connection after the response. Both paths hold at most
  one configured transfer buffer and one framed chunk per connection.
- `Events()` sends server-sent events from a bounded queue. It supports named
  events, IDs, retry hints, comments, and idle heartbeats.
- Responses include `Content-Length`; HEAD sends the corresponding headers and
  no body. Connections close by default. Set `keepAlive = True` to reuse an
  HTTP/1.1 connection for sequential requests, bounded by
  `maxRequestsPerConnection` and `keepAliveTimeoutMs`. HTTP/1.0 still closes.
- Static files use `BRL.FileSystem` metadata and `ReadStream`, so mounted
  `littlefs::` and `sd::` paths use the same transfer loop. Files are read in
  configured chunks. Directory URLs resolve to `index.html`. Static routes
  support one byte range, `If-None-Match`, and optional cache lifetimes.
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

For versioned static assets, `server.Static("/assets/", "littlefs::/www/", 3600)`
adds `Cache-Control: public, max-age=3600`. The default omits a cache lifetime.
Static files up to 64 KiB get a content-derived weak `ETag`; the server checks
`If-None-Match` and returns 304 when it matches. Calculating this tag reads
the file once before serving it, so larger files omit the tag to keep a
request's synchronous work bounded. A single `Range: bytes=...` request returns
206 or 416 with `Content-Range`; unsupported or malformed range forms receive
the full response. `If-Range` receives the full response because this server
does not issue a strong validator. HEAD returns the corresponding headers
without a body.

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

For a response whose size is unknown, call
`response.StreamUnknown(stream, mime)` in a route handler. A live source can
instead implement `IHTTPResponseProducer` and call
`response.Produce(producer, mime)`. Its `TryRead(buffer, capacity)` returns a
positive byte count, `HTTPWouldBlock` when data is not ready, zero when done,
or a negative error value. `Close()` runs when the response completes or the
connection ends. Callbacks must return promptly. The server does not impose a
total response-size limit on these streams; producers should enforce their own
limits and send data within `writeTimeoutMs` (10 seconds by default). Once
headers have been sent, a producer failure closes the connection. HEAD sends
the same framing headers but no body; 204, 205 and 304 responses send no chunks.

## Server-sent events

Create one `THTTPEventStream` per client, then attach it in a GET route:

```blitzmax
Local events:THTTPEventStream = THTTPEventStream.Create(4096, 5000)
If Not events Or Not response.Events(events) Then RuntimeError "SSE setup failed"
If Not events.Send("connected", "status", "1") Then RuntimeError "SSE queue full"
```

Keep the stream reference to queue later messages with `Send(data, eventName,
id)` during the application's managed loop. Newlines in `data` become separate
SSE `data:` fields. `Comment(text)` sends a comment, and `Retry(milliseconds)`
sets the browser's reconnect delay. These methods return `False` if the queue
is full or the client has closed; the application decides whether to retry or
drop that message. The queue defaults to 4 KiB and can be set from 64 bytes to
64 KiB. `PendingBytes()` reports queued bytes, and `IsClosed()` reports a
disconnected or completed stream. `Finish()` drains queued events and ends the
response; the server then calls `Close()`.

The response sets `Content-Type: text/event-stream; charset=utf-8` and
`Cache-Control: no-cache`. HTTP/1.1 uses chunked framing. Idle streams send a
`:\n\n` heartbeat every 5 seconds by default; set a shorter interval than
`writeTimeoutMs` so a quiet stream stays open. A zero interval disables
heartbeats. Each live client occupies one `maxConnections` slot. The route can
read `request.Header("Last-Event-ID")` on reconnection; the application must
retain and replay any events it wants the client to receive again. Queue and
stream access belong in the same managed context as `Service()`.

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

For credentials held in LittleFS, mount storage first and create the listener
from two PEM files. The same paths work on both boards:

```blitzmax
Local tls:THTTPSTLSListener = THTTPSTLSListener.CreateFromFiles( ..
    "littlefs::/tls/server.crt", "littlefs::/tls/server.key")
Local server:THTTPServer = THTTPServer.Create(config, tls)
If Not server.Start() Then RuntimeError server.LastError()
```

Each PEM file may contain at most 16 KiB. The listener checks file size and
reads both files fully, then mbedTLS validates the certificate and matching
key before binding the socket. To replace them, stop the server, call
`tls.ReplaceFromFiles(newCertPath, newKeyPath)`, and start it again. The
replacement is validated before the old credentials are discarded. If it
fails, `tls.LastError()` explains the failure and `server.Start()` can resume
with the previous credentials. `tls.ReplaceCredentials(certPEM, keyPEM)` does
the same for PEM text loaded from another source, such as ESP32 NVS. Both
replacement calls require the server to be stopped; `Stop()` closes active
connections. Existing file credentials remain in memory across a Stop/Start;
call `ReplaceFromFiles` explicitly to read changed files.

LittleFS is persistent storage, not protected key storage by itself. A product
using file-based private keys must arrange appropriate flash protection and
access control. On ESP32, an application can instead read PEM strings from
NVS and pass them to `ReplaceCredentials`:

```blitzmax
Import ESP32.Storage.NVS

Local store:TNVSNamespace = OpenNVS("https", True)
If Not store Then RuntimeError "HTTPS credential namespace unavailable"
Local certPEM:String
Local keyPEM:String
If Not store.TryGetString("cert", certPEM) Or ..
    Not store.TryGetString("key", keyPEM) Then RuntimeError "HTTPS credentials unavailable"
store.Close()
If Not tls.ReplaceCredentials(certPEM, keyPEM) Then RuntimeError tls.LastError()
```

Do this before starting the server, or after stopping it for replacement.
NVS encryption and key provisioning are application setup; ordinary NVS does
not itself guarantee encrypted private-key storage. On Pico W, this module
has no hardware protected key store. Certificate issuance, renewal, and
selection of an active credential pair after reboot remain application
responsibilities.

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

WebSockets, multipart, authentication helpers,
captive-portal workflows and OTA are later layers. The HTTPS adapter builds
for Pico 2 W and ESP32-S3. A
verified handshake, GET, fragmented POST, 404 response, and 30 repeated connections
passed on both Pico 2 W and ESP32-S31. After flashing an HTTPS variant of the
device example with a test certificate, run
`python3 tests/test_httpserver_tls_device.py BOARD_IP test-cert.pem`. The test
checks a trusted handshake, GET, a fragmented POST and a 404 response.

For the optional connection reuse and chunked-body image, run
`python3 tests/test_httpserver_next_device.py BOARD_IP`, or add
`--tls-cert test-cert.pem` for an HTTPS image. It checks sequential requests on
one connection, a fragmented chunked echo, a 32 KiB streamed chunked upload,
and conflicting framing rejection. These checks passed on an ESP32-S31 over
both HTTP and verified HTTPS, including 20 repeated HTTP rounds and 10 HTTPS
rounds. They also passed on a Pico 2 W over verified HTTPS, including 10
repeated rounds. The original HTTPS handshake, GET, fragmented POST, and 404
checks passed again on both boards with the connection-reuse image.

Credential loading and replacement were also exercised on device: the Pico 2 W
loaded a test PEM pair from LittleFS, rejected an invalid replacement, resumed
with the previous pair, and started with a valid replacement. The ESP32-S31
performed the same validation and restart sequence with a PEM pair read from
NVS. The temporary test entries were removed after each run.

The ESP32-S31 Function CoreBoard's dedicated LittleFS partition was explicitly
formatted after its old contents failed to mount. A second on-device run
verified file persistence across unmount/remount, rejected replacement while
running and with an invalid key, restarted with the original pair, then served
an HTTPS request with the replacement certificate loaded from LittleFS.

`tests/httpserver_chunked_device.bmx` is a portable HTTPS test image; fill a
local copy with Wi-Fi and a temporary test certificate. Run
`python3 tests/test_httpserver_chunked_device.py BOARD_IP test-cert.pem` after
flashing. The host wire tests and verified HTTPS device tests pass on Pico 2 W
and ESP32-S31 for chunked output, connection reuse, HEAD, no-body responses and
HTTP/1.0 close-delimited output.
The same image writes a 4 KiB LittleFS fixture under `/www` and checks trusted
HTTPS static responses, byte ranges, `If-None-Match`, explicit cache lifetime,
and a 416 response. These checks pass on Pico 2 W and ESP32-S31. For the Pico 2 W
HTTPS fixture, use at least `-heap 256k` with `-storage 128k`: 128 KiB and
192 KiB heaps showed intermittent allocation failures during repeated static
requests. Twelve consecutive full wire suites passed at 256 KiB. A separate
eight-suite heap check collected between suites and found stable live strings,
arrays, objects, and reusable heap space.

`tests/httpserver_sse_device.bmx` is a portable HTTPS SSE test image. Fill a
local copy with Wi-Fi and a temporary test certificate, then run
`python3 tests/test_httpserver_sse_device.py BOARD_IP test-cert.pem`. The test
checks trusted TLS, named and multiline events, retry hints, idle heartbeats,
completion, and `Last-Event-ID` on a second connection. All 19 host wire tests
pass; the verified HTTPS SSE test also passes on Pico 2 W with a 256 KiB managed
heap and ESP32-S31 with a 256 KiB managed heap.
