# Thread networking

Use `ESP32.Network.Thread` or `NRF52.Network.Thread` in the application. The
platform import includes `Embedded.Network.Thread`, which provides mesh setup,
IPv6 addresses, and UDP. Add optional imports for the features the firmware
needs; each board build gets its own OpenThread configuration and image.
The [core API declarations](thread.bmx) carry bbdoc comments for every public
constant, function, type, and method.

## Start or resume a mesh

```blitzmax
SuperStrict
Framework BRL.StandardIO
Import ESP32.Network.Thread ' Or NRF52.Network.Thread

Local result:Int = ThreadStartSaved()
If result = ThreadErrorNoSavedNetwork Then
    result = ThreadForm("MyMesh", 15)
End If
If result <> 0 Then RuntimeError "Thread start failed: " + result

Local role:Int = ThreadWaitForAttached()
If role < ThreadRoleChild Then RuntimeError "Thread attach failed: " + role
```

`ThreadForm` creates a **new** network and replaces the stored dataset. The
saved dataset survives `ThreadLeave` and application reflashing. Call
`ThreadForget` only during an explicit reprovisioning flow. To put another
board on the same mesh, use [commissioning](#commission-a-second-board) or
`ThreadJoin(ThreadActiveDataset())` with a dataset transferred securely from
another node. A dataset contains the network key; do not log it in deployed
firmware.

`ThreadIPv6Address(index)` enumerates this node's addresses. Child, Router,
and Leader are attached roles. A standalone mesh has no LAN or Internet route;
that requires a border router.

## Exchange UDP datagrams

For one receive port, call `ThreadUDPOpen(port)`, then poll
`ThreadUDPReceive(buffer, source, sourcePort)`. Send a reply with
`ThreadUDPSend(source, sourcePort, buffer, length)`. An empty receive queue
returns `-11`. A buffer that is too small returns `-90` and leaves the datagram
queued. `ThreadUDPClose()` releases the port.

```blitzmax
Local socket:TThreadUDPSocket = TThreadUDPSocket.Open(12345)
If Not socket Then RuntimeError "UDP bind failed"
Local packet:Byte[1280]
Local source:String, sourcePort:Int

While True
    Local length:Int = socket.Receive(packet, source, sourcePort)
    If length >= 0 Then socket.Send(source, sourcePort, packet, length)
    Delay 20
Wend
```

`TThreadUDPSocket` provides up to eight independent ports. `Open(0)` chooses a
port, readable with `LocalPort()`. `Connect` sets a default peer and filters
incoming datagrams; use `SendConnected` and `Disconnect` with that peer. Each
socket has a configurable queue of 1–16 datagrams and a maximum datagram size
of 1–1280 bytes. `Dropped()` counts discarded packets. Use
`ThreadUDPNetifAny` when the socket must also receive traffic from a backbone
interface on a supported platform.

## Commission a second board

Import `Embedded.Network.ThreadCommissioning` in both applications. The first
board must already be attached. On it:

1. Call `ThreadCommissionerStart()` and poll `ThreadCommissionerState()` until
   `ThreadCommissionerActive`.
2. Call `ThreadCommissionerAddJoiner(eui64, pskd, timeoutSecs)`. Obtain the
   joiner's 16-digit factory EUI-64 with `ThreadFactoryEui64()` on that board.
3. Call `ThreadCommissionerStop()` when commissioning is complete.

On the joining board, call `ThreadJoinerStart(pskd)`, poll
`ThreadJoinerStatus()` until it returns zero, then call
`ThreadWaitForAttached()`. The acquired dataset is saved for later boots.
Use a unique PSKd per device: 6–32 uppercase letters or digits, excluding
I, O, Q, and Z. An empty EUI-64 authorizes any device with the PSKd during
the timeout; prefer the exact device ID. See the
[Commissioner](../../../esp32.mod/examples/thread_commissioner.bmx) and
[Joiner](../../../esp32.mod/examples/thread_joiner.bmx) examples.

## Select features

| Import | Adds | Starting point |
| --- | --- | --- |
| `Embedded.Network.ThreadDiscovery` | SRP client, DNS-SD browse/resolve, TXT records | `ThreadServiceClientEnable` |
| `Embedded.Network.ThreadServer` | On-mesh SRP/DNS-SD server on ESP32 | `ThreadServiceServerEnable` |
| `Embedded.Network.ThreadCoAP` | CoAP client and resources | [CoAP guide](../threadcoap.mod/README.md) |
| `Embedded.Network.ThreadCoAPBlock` | Block1/Block2, up to 4096 bytes | `ThreadCoAPBlockResource` |
| `Embedded.Network.ThreadCoAPObserve` | Observable resource and subscription | `ThreadCoAPObserveResource` |
| `Embedded.Network.ThreadCoAPSecure` | PSK-based CoAP over DTLS | `ThreadCoAPSecureStart` |
| `Embedded.Network.ThreadTCP` | One bounded TCP stream or listener | `ThreadTCPOpen` |
| `ESP32.Network.ThreadBorderRouter` | Wi-Fi or Ethernet backbone routing | [Border router guide](../../../esp32.mod/network.mod/threadborderrouter.mod/README.md) |

### Discover a service

On an attached ESP32 server, call `ThreadServiceServerEnable()`. On a client,
call `ThreadServiceClientEnable()` and wait for
`ThreadServiceClientRunning()` before publishing or querying. Publish a named
service with `ThreadServicePublish(host, instance, type, port)` and poll
`ThreadServicePublishState()` until zero. Browse with `ThreadServiceBrowse(type)`;
when its state is zero, read `ThreadServiceBrowseCount()` and each
`ThreadServiceBrowseResult(index)`. Pass a result to
`ThreadServiceResolve(instance, type)` and poll `ThreadServiceResolveState`
for its IPv6 address and port.

`TThreadPublishedService.Publish(...)` manages up to eight services and TXT
records. `TThreadServiceBrowser.Start(...)` refreshes the one-shot browse at
an interval. See the [service catalog server](../../../esp32.mod/examples/thread_service_catalog.bmx)
and [nRF peer](../../../nrf52.mod/examples/nrf52_thread_service_catalog_peer.bmx).

### Use TCP

Import `Embedded.Network.ThreadTCP`. Call `ThreadTCPOpen()`, then
`ThreadTCPConnect(address, port)` or `ThreadTCPListen(port)`. Wait until
`ThreadTCPState()` is `ThreadTCPConnected`. `ThreadTCPSend()` queues up to
1024 bytes; wait for `ThreadTCPSendReady()` before another send.
`ThreadTCPReceive()` returns `-11` when no data is ready and zero at end of
stream. Finish with `ThreadTCPEndSend()` and `ThreadTCPClose()`.

## Limits and platforms

| Feature | Current limit |
| --- | --- |
| Simple UDP API | One port; eight queued datagrams |
| UDP socket objects | Eight; 1280-byte maximum datagram; queue depth up to 16 |
| Discovery | One browse and one resolve in flight; 32 labels; 1024 TXT bytes |
| Base CoAP | 1024-byte payload; one simple exchange plus four additional concurrent exchanges |
| Blockwise CoAP | One resource and client exchange; 4096-byte assembled payload |
| Observe | One subscriber and client subscription; four queued values |
| Secure CoAP | One resource and client exchange; PSK authentication |
| TCP | One stream endpoint; 1024-byte send |

The adapters target nRF52840 with Zephyr 4.5.0 and ESP32-H2/C6/S31 with the
project's ESP-IDF 6.1 toolchain. The SRP server has been exercised on S31;
H2 radio operation remains untested. RP/Pico has no Thread adapter here.
Builds can use `BMX_ESP32_EXTRA_SDKCONFIG` or `BMX_NRF52_EXTRA_CONF_FILE` for
platform configuration overlays when feature imports are insufficient.

Examples: [ESP32 mesh echo](../../../esp32.mod/examples/thread_form_echo.bmx),
[ESP32 UDP peer](../../../esp32.mod/examples/thread_udp_peer.bmx), and
[nRF mesh echo](../../../nrf52.mod/examples/nrf52_thread_echo.bmx).
