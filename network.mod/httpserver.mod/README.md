# Embedded.Network.HTTPServer

`Embedded.Network.HTTPServer` is a single-managed-context HTTP/1.0 and HTTP/1.1
server. The same route and response code builds for ESP32 and Pico W. Its
transport uses `BRL.Socket`; handlers run only inside the application's call to
`Service()`.

## First milestone

- GET, HEAD and POST; exact and `:parameter` routes; bounded query and header
  access; text, HTML, JSON, bytes, redirect and length-known stream responses.
- One request per TCP connection. Responses include `Content-Length` and
  `Connection: close`. HEAD sends the corresponding headers and no body.
- Static files use `BRL.FileSystem` metadata and `ReadStream`, so mounted
  `littlefs::` and `sd::` paths use the same transfer loop. Files are read in
  configured chunks. Directory URLs resolve to `index.html`.
- Strict CRLF framing, HTTP/1.1 Host requirement, numeric Content-Length,
  rejection of duplicate lengths, and rejection of unsupported Transfer-Encoding
  and Expect headers. Pipelined requests are not dispatched.
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

The supplied [device example](examples/device_api.bmx) has a status/JSON route,
a token-protected GPIO route, LittleFS static files on both targets and
optional SD static files on ESP32, plus a bounded POST echo used by device
tests. Fill in `examples/device_api.local.bmx` with the Wi-Fi name, password,
a random control token and a board-safe GPIO pin. This file is ignored by Git;
build it instead of the tracked example. Pico builds with a 32 KiB managed heap
and a reserved storage area are recommended for this example. ESP32 LittleFS needs
the board's `storage` partition; SD requires a board with configured SDMMC.

## Resource defaults

| Resource | Default |
| --- | ---: |
| Active clients | 1 |
| Routes | 16 |
| Request line | 256 bytes |
| Header block / count | 1024 bytes / 16 |
| Buffered request body | 1024 bytes |
| Response body helper | 1024 bytes |
| Stream transfer buffer | 512 bytes |
| Header / body / write timeout | 5 s / 10 s / 10 s |

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
LittleFS, or `/sd/...` on an ESP32 SD mount. On-device wire and
allocation-pressure runs are still required before declaring cross-target
behavioural equivalence.

Keep-alive, chunked transfer, range/cache responses, upload streaming, SSE,
WebSockets, multipart, authentication helpers, captive-portal workflows and OTA
are later layers. HTTPS will use an optional transport so plain-HTTP route code
does not change. No TLS or outbound certificate-verification settings are
changed by this module.
