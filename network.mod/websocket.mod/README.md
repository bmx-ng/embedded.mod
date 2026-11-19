# Embedded.Network.WebSocket

Import `Embedded.Network.WebSocket` only for applications with WebSocket
endpoints. The HTTP server contains a small generic upgrade hook; the
WebSocket handshake hash, framing code, and per-client buffers
belong to this separate module. It works with the same plain HTTP and HTTPS
listeners on ESP32 and Pico W.

Register a GET upgrade route with a handler:

```blitzmax
Import Embedded.Network.HTTPServer
Import Embedded.Network.WebSocket

Type TMessages Implements IHTTPWebSocketHandler
    Method Accept:Int(request:THTTPRequest)
        ' Check Origin and application credentials before upgrading.
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

server.RouteUpgrade("/messages", ..
    THTTPWebSocketUpgrade.Create(New TMessages, 4096, 4096))
```

Callbacks run from `THTTPServer.Service()` on the managed application context.
`SendText` and `SendBinary` return `False` when the bounded output queue is full
or closing. The two `Create` limits set the maximum complete message
and outgoing queued bytes; they default to 2 KiB and 4 KiB respectively.
Allow space for frame headers and control replies when choosing a queue size.
One open WebSocket occupies
one `maxConnections` slot. `Disconnect(code, reason)` starts a close handshake;
`IsClosed()` and `PendingBytes()` expose the current state. The server releases
the session when its socket closes and calls `Closed` once.

The module accepts masked client frames, reassembles fragmented text or binary
messages within the configured limit, validates text as UTF-8, replies to
pings, handles close frames, and sends idle pings. It rejects unsupported
opcodes and RSV bits. It does not negotiate extensions, compression, or
subprotocols. Applications should authenticate and check `Origin` in `Accept`;
the WebSocket handshake alone does not authorize a client.

`tests/httpserver_ws_device.bmx` is a portable HTTPS test image. Fill a local
copy with Wi-Fi and temporary test credentials, then run
`python3 tests/test_httpserver_ws_device.py BOARD_IP test-cert.pem`. The host
wire tests cover the handshake, frames, protocol errors, and rejected upgrades.
All 20 host wire tests pass. Five repeated trusted WSS sessions pass on Pico
2 W and ESP32-S31 with 256 KiB managed heaps, including fragmented text,
ping/pong, binary echo, and close. A separate HTTP-only build confirms that
this module is excluded unless imported.
