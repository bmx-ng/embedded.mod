# CoAP over Thread

Import the platform Thread module and `Embedded.Network.ThreadCoAP`, attach to
a mesh, then call `ThreadCoAPStart()`. Importing CoAP selects its OpenThread
feature for this application build. The [CoAP API declarations](threadcoap.bmx)
include return values and parameter descriptions.

## Serve a resource

```blitzmax
ThreadCoAPStart()
ThreadCoAPResource("status")

Local request:Byte[1024]
Local requestMethod:Int, source:String
Local length:Int = ThreadCoAPReceive(request, requestMethod, source)
If length >= 0 Then
    If requestMethod = ThreadCoAPGet Then
        ThreadCoAPRespond(ThreadCoAPContent, [Byte(79), Byte(75)]) ' OK
    Else
        ThreadCoAPRespond(ThreadCoAPMethodNotAllowed)
    End If
End If
```

Poll `ThreadCoAPReceive` in the application loop. It returns `-11` when no
request is queued. The simple API has one path and one pending request. For
more paths, register up to four with `ThreadCoAPAddResource(path)`, then use
`ThreadCoAPReceiveNext(buffer, requestMethod, source, path, requestId)` and reply with
`ThreadCoAPRespondTo(requestId, code, payload)`. Answer every delivered request
to release its slot.

## Send requests

`ThreadCoAPSend(address, path, requestMethod, payload)` sends one confirmable request;
poll `ThreadCoAPResponse(buffer, code)` for its reply. To keep up to four
additional exchanges in flight, use `ThreadCoAPSendRequest(...)`, retain its
positive exchange ID, and poll `ThreadCoAPReadResponse(id, buffer, code)` for
each response. A return of `-11` means pending. `-90` means the supplied buffer
is too small; the request or response remains available for another read.

Paths omit the leading slash and are limited to 63 UTF-8 bytes. Base CoAP
payloads are at most 1024 bytes. Methods are GET, POST, PUT, and DELETE.

## Optional imports

| Import | What it adds | Limit |
| --- | --- | --- |
| `Embedded.Network.ThreadCoAPBlock` | Block1 uploads and Block2 responses in 256-byte segments | 4096 assembled bytes; one exchange |
| `Embedded.Network.ThreadCoAPObserve` | Subscribe, publish, and cancel Observe notifications | One subscriber; four queued values |
| `Embedded.Network.ThreadCoAPSecure` | CoAP over DTLS using a runtime PSK and identity | 1024-byte payload; one exchange |

Call `ThreadCoAPStart()` before registering blockwise or observable resources.
Secure CoAP uses its own `ThreadCoAPSecureStart(psk, identity)` and port 5684.
The PSK is 16–32 bytes; keep it out of tracked source and logs. Certificate
based DTLS is not exposed by this API.

Examples: [CoAP resource](../../../esp32.mod/examples/thread_coap_resource.bmx),
[concurrent peer](../../../nrf52.mod/examples/nrf52_thread_coap_peer.bmx),
[blockwise resource](../../../esp32.mod/examples/thread_coap_block_resource.bmx),
[Observe resource](../../../esp32.mod/examples/thread_coap_observe_resource.bmx),
and [secure resource](../../../esp32.mod/examples/thread_coap_secure_resource.bmx).
