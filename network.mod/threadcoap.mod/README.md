# Thread CoAP application API

Import `Embedded.Network.ThreadCoAP` after the platform Thread module, then
start the mesh and call `ThreadCoAPStart()`. The import selects the CoAP-enabled
OpenThread build profile for the application.

The original `ThreadCoAPResource`, `ThreadCoAPReceive`, `ThreadCoAPRespond`,
`ThreadCoAPSend`, and `ThreadCoAPResponse` calls remain available for a simple
single-resource application. The additional API supports four more resource
paths, four pending server requests, and four concurrent client exchanges:

```blitzmax
ThreadCoAPAddResource("health")
ThreadCoAPAddResource("echo")

Local method:Int, source:String, path:String, requestId:Int
Local request:Byte[512]
Local length:Int = ThreadCoAPReceiveNext(request, method, source, path, requestId)
If length >= 0 Then
    ' Build a response for this request ID, using its path and method.
    ThreadCoAPRespondTo(requestId, ThreadCoAPContent, [Byte(Asc("O")), Byte(Asc("K"))])
End If
```

`ThreadCoAPSendRequest` returns a positive exchange ID or a negative error.
Keep each ID and poll `ThreadCoAPReadResponse(id, data, code)` separately. It
returns `-11` while waiting, a payload length on success, and a negative error
on failure. Successful reads and completed errors release their exchange slot.
When the supplied buffer is too small, `-90` leaves the response available for
a retry with a larger buffer. The server receive call has the same buffer
behavior. A delivered server request occupies its slot until
`ThreadCoAPRespondTo` succeeds; applications should respond to every request,
including unsupported methods.

Payloads are still limited to 512 bytes per request or response. Each resource
path is limited to 63 UTF-8 bytes. The new API supports GET, POST, PUT, and
DELETE and sends confirmable requests. Observe, block transfers, DTLS-secured
CoAP, and streaming payloads are separate future additions. The ESP32 and
nRF52 examples exercise multiple paths and two concurrent exchanges.
