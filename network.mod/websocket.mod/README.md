# Embedded.Network.WebSocket

`Embedded.Network.WebSocket` adds bounded WebSocket endpoints to
[`Embedded.Network.HTTPServer`](../httpserver.mod/README.md). Import it only
in applications that use WebSockets. The HTTP server's generic upgrade hook
does not link WebSocket framing code or allocate WebSocket buffers by itself.
Routes work with plain HTTP (`ws://`) or the optional HTTPS listener
(`wss://`) on ESP32 and Pico W.

## Add a route

Implement `IHTTPWebSocketHandler`, create an upgrade handler, and register a
GET upgrade route **before** starting the server:

```blitzmax
Framework BRL.StandardIO
Import BRL.EventQueue
Import Embedded.Network.HTTPServer
Import Embedded.Network.WebSocket

Type TMessages Implements IHTTPWebSocketHandler
    Method Accept:Int(request:THTTPRequest)
        ' Replace this check with your application's origin and authentication rules.
        Return request.Header("Origin") = "https://example.test"
    End Method

    Method Open(socket:THTTPWebSocket, request:THTTPRequest)
        socket.SendText("connected")
    End Method

    Method Message(socket:THTTPWebSocket, data:Byte[], isText:Int)
        If isText Then
            Local value:String = ""
            If data.length Then value = String.FromUTF8Bytes(Varptr data[0], data.length)
            socket.SendText(value)
        Else
            socket.SendBinary(data)
        End If
    End Method

    Method Closed(socket:THTTPWebSocket, code:Int)
    End Method
End Type

Local server:THTTPServer = THTTPServer.Create()
If Not server Then RuntimeError "HTTP server creation failed"
Local upgrade:THTTPWebSocketUpgrade = THTTPWebSocketUpgrade.Create(New TMessages)
If Not upgrade Then RuntimeError "WebSocket setup failed"
If Not server.RouteUpgrade("/messages", upgrade) Then RuntimeError "Route setup failed"
If Not server.Start() Then RuntimeError server.LastError()

While True
    PollEvent()
    server.Service(4)
    Delay 1
Wend
```

The example uses the HTTP server's default port 8080. Configure Wi-Fi before
`Start()` on a device. For WSS, import `Embedded.Network.HTTPSTLS` and pass
a `THTTPSTLSListener` to `THTTPServer.Create(config, tls)`; the handler and
service loop stay the same. See the
[HTTPS setup](../httpserver.mod/README.md#https-on-esp32-and-pico-w) and the
complete [device test image](../../tests/httpserver_ws_device.bmx).

## Callbacks and connection lifetime

| Callback | When it runs |
| --- | --- |
| `Accept(request)` | Before the upgrade; return `False` to send HTTP 403. Check the origin and application credentials here. |
| `Open(socket, request)` | Once after the upgrade succeeds. |
| `Message(socket, data, isText)` | Once for each complete text or binary message. Text is validated UTF-8; `isText` identifies its type. |
| `Closed(socket, code)` | Once when the connection ends, including disconnects and failures. |

Callbacks run inside `THTTPServer.Service()` on the managed application
context. Keep them short, call `Service()` frequently, and access a socket
only from that context. `SendText()` and `SendBinary()` queue complete
messages; each returns `False` if the message exceeds the route limit, the
bounded output queue is full, or the connection is closing. Decide in the
application whether to retry or drop a message. `PendingBytes()` reports
queued output; `Disconnect(code, reason)` starts a close handshake and
`IsClosed()` reports its completion.

Each open WebSocket occupies one HTTP server `maxConnections` slot until it
closes. Size that setting for simultaneous HTTP, SSE and WebSocket clients.
`THTTPWebSocketUpgrade.Create(handler, maxMessageBytes, maxPendingBytes)`
defaults to a 2 KiB complete message limit and a 4 KiB outgoing queue.
Accepted ranges are 64–65536 bytes and 256–65536 bytes respectively.
Leave room in the output queue for frame headers and control replies.
The server calls `Closed` and releases the slot when the connection ends.

The module reassembles fragmented messages within the route limit, replies to
pings, sends idle pings, handles close frames, and rejects invalid framing,
unsupported opcodes, unnegotiated RSV bits, and invalid UTF-8 text.

## Optional subprotocols

Set the supported tokens before registering the route:

```blitzmax
If Not upgrade.SetSubprotocols(["messages.v2", "messages.v1"]) Then ..
    RuntimeError "Invalid WebSocket subprotocol"
```

The first client-offered protocol present in this list is available through
`socket.Subprotocol()`. Without a match, the upgrade succeeds with no
subprotocol. An invalid token in the client's offer rejects the handshake.
Pass `Null` to `SetSubprotocols` to clear the list.

## Optional compression

Add `Import Embedded.Network.WebSocketDeflate` with the other imports, then
attach its factory before `RouteUpgrade()`:

```blitzmax
upgrade.SetCompressionFactory(THTTPWebSocketDeflateFactory.Create())
```

Register the route after this call. Compression code is linked only when
imported, and negotiation happens only for routes with a factory. The client
must offer `permessage-deflate` with `client_max_window_bits`. Both
directions then use a 9-bit window with no context takeover. Unsupported
offers are declined and the connection continues without compression.
Short messages may remain uncompressed when deflate would make them larger.
Decompressed messages remain subject to `maxMessageBytes`.

## Security and testing

A successful WebSocket handshake does not authenticate a client. Apply the
application's authentication and `Origin` rules in `Accept()`. Use WSS for
traffic that needs TLS, and arrange trusted certificate storage as described
in the HTTP server's HTTPS guide.

`tests/run_httpserver_host.sh` runs the host wire tests, including WebSocket
handshakes, frames, protocol errors and rejected upgrades. For device
testing, configure a local copy of `tests/httpserver_ws_device.bmx` with
Wi-Fi and temporary test credentials. After flashing it, run:

```sh
python3 tests/test_httpserver_ws_device.py BOARD_IP test-cert.pem
```

For longer WebSocket and mixed HTTPS/SSE/WebSocket runs, see
[`tests/README.md`](../../tests/README.md#https-server-soak-tests). That
guide records the tested heap settings and the ESP32-S3 internal-SRAM TLS
headroom finding.
