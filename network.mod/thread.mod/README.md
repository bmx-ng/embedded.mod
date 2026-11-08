# Embedded.Network.Thread

Import `NRF52.Network.Thread` or `ESP32.Network.Thread` to include the radio
adapter and the portable `Embedded.Network.Thread` core and UDP API. Imports
select optional OpenThread features for each firmware build:

| Import | Feature selected |
| --- | --- |
| `Embedded.Network.ThreadCommissioning` | Joiner and Commissioner |
| `Embedded.Network.ThreadDiscovery` | SRP client and DNS client |
| `Embedded.Network.ThreadServer` | On-mesh SRP and DNS-SD server, plus discovery client |
| `Embedded.Network.ThreadCoAP` | CoAP client and server |

The server import is available on ESP32 builds. Each board/application build
has its own OpenThread configuration and firmware image; the imports used by a
C6 application do not affect an S31 or nRF application build.
The current targets are nRF52840 with Zephyr 4.5.0 and ESP32-H2/C6/S31 with the
project's ESP-IDF 6.1 toolchain. RP/Pico needs an external IEEE 802.15.4 radio
and has no adapter here.

`ThreadForm(name, channel)` generates a fresh active operational dataset and
starts a mesh. `ThreadActiveDataset()` returns that dataset as hexadecimal text.
`ThreadStartSaved()` starts using the active dataset stored by OpenThread. It
returns `ThreadErrorNoSavedNetwork` (`-61`) when no dataset is stored, so an
application can call `ThreadForm()` only on first boot. `ThreadForm()` explicitly
replaces any existing dataset; `ThreadLeave()` does not erase it. The ESP32
adapter uses NVS and the nRF52 adapter uses Zephyr settings for persistence.
`ThreadJoin(datasetHex)` installs an existing active dataset and starts the
Thread interface. This is out-of-band provisioning: it does not perform Thread
Joiner commissioning. `ThreadLeave()` disables the Thread interface; the
installed dataset remains available for `ThreadStartSaved()`. A dataset contains
the network key: treat it as a secret and do not print it in production firmware.

On-mesh commissioning uses a node already attached to the mesh as Commissioner;
no border router is needed. On that node call `ThreadCommissionerStart()`, poll
`ThreadCommissionerState()` until `ThreadCommissionerActive`, then authorize a
joiner with `ThreadCommissionerAddJoiner(factoryEui64, pskd, timeoutSecs)`.
`ThreadFactoryEui64()` on the joiner supplies the 16 hex digits for
`factoryEui64`. An empty EUI-64 authorizes any device with that PSKd during the
timeout; use a specific EUI-64 in deployed firmware. The PSKd must contain 6–32
uppercase letters or digits, excluding I, O, Q, and Z. Use a unique PSKd for
each device. `ThreadCommissionerStop()` ends the commissioning session.

On the joining node call `ThreadJoinerStart(pskd)`, then poll
`ThreadJoinerStatus()`; it returns 1 while joining, 0 once credentials have been
received and the Thread interface has started, or a negative OpenThread error.
`ThreadWaitForAttached()` then confirms that it attached. A successful join
stores the operational dataset, which `ThreadStartSaved()` uses on later boots.
`ThreadJoinerStop()` cancels a pending attempt. A node with an old stored network
can call `ThreadForget()` first; this erases persistent Thread settings and is
intended for an explicit reprovisioning flow. Polling must occur in the managed
application task, because starting Thread in the OpenThread join callback is
not safe. The Commissioner must be attached before it can petition to become
active. More than one Commissioner can petition, but only one is active at a
time.

The ESP32 examples `thread_commissioner.bmx` and `thread_joiner.bmx` show the
two sides. Set matching, unique credentials and the joiner's factory EUI-64
before flashing. For a board already provisioned to another network, call
`ThreadForget()` once from an explicit reprovisioning action before starting
the joiner example; do not erase the network on every boot. After joining,
`thread_saved_node.bmx` resumes that network without embedding its dataset;
`thread_saved_udp_peer.bmx` additionally exchanges UDP with an echo node.

`ThreadRole()` returns Disabled (0), Detached (1), Child (2), Router (3), or
Leader (4). `ThreadWaitForAttached(timeoutMs)` returns a role of at least Child
or a negative timeout/error. `ThreadIPv6Address(index)` enumerates local IPv6
addresses, returning an empty string after the last one. Mesh-local addresses
work between Thread nodes. Reaching devices outside the mesh requires a Thread
border router with an appropriate IPv6 route; IPv4-only destinations also need
NAT64 service. Forming a standalone mesh does not provide Internet access.

`ThreadUDPOpen(port)` binds one OpenThread UDP/IPv6 receive port per process.
`ThreadUDPSend(address, port, data, length)` returns bytes queued for delivery
or a negative error. `ThreadUDPReceive(buffer, sourceAddress, sourcePort)`
returns the received size, `-11` when no datagram is queued, or `-90` when the
caller buffer is too small (the datagram remains queued). Eight datagrams of
up to 512 bytes are buffered; oversize or overflow datagrams are counted by
`ThreadUDPDropped()`. `ThreadUDPClose()` releases the port. Calls must be made
from the managed application task. These UDP calls use OpenThread's own socket
path and support Thread IPv6 traffic on both targets.

`TThreadUDPSocket.Open(port)` opens one of four additional UDP endpoints. Each
endpoint has its own eight-datagram, 512-byte receive queue and `Send`,
`Receive`, `Dropped`, and `Close` methods. The older `ThreadUDP*` functions
remain available. `Open` returns `Null` when binding fails. Deleting a socket
object releases its port. The optional second argument selects the interface:
`ThreadUDPNetifThread` (the default) uses OpenThread's internal mesh socket,
while `ThreadUDPNetifAny` also allows a platform UDP socket where the target
provides one. On an ESP32 border router, use `ThreadUDPNetifAny` to receive
datagrams sent from the backbone to a local Thread address.

Service discovery uses OpenThread SRP and DNS-SD. On an attached ESP32-S31 with
`Embedded.Network.ThreadServer` imported,
`ThreadServiceServerEnable()` starts an on-mesh SRP server; poll
`ThreadServiceServerState()` for 1 (running). The server import enables the SRP
server and Thread network-data publisher without configuring Wi-Fi/Ethernet
routing. On a client, `ThreadServiceClientEnable()` discovers the server from
Thread network data; poll `ThreadServiceClientRunning()` before querying. Use
`ThreadServicePublish(hostLabel, instanceLabel, serviceType, udpPort)` to
register a service such as `_bmxecho._udp`. Poll
`ThreadServicePublishState()` until zero. `ThreadServiceUnpublish()` removes it.
The original functions retain their single-service calling convention.
`TThreadPublishedService.Publish(host, instance, type, port, txtEntries)` adds
one of up to four independently managed services on the same SRP host label.
Its `State()` is 1 while pending, 0 when registered, 2 when removed, or a
negative error. `Unpublish()` requests removal; `Close()` releases the object
and unregisters it asynchronously if necessary. TXT entries are UTF-8 strings
such as `id=one` or boolean keys. `ThreadTXTEncode()` and `ThreadTXTDecode()`
convert between strings and bounded DNS TXT wire data (256 bytes total).
The service type is a short DNS-SD type; queries use OpenThread's default
`default.service.arpa` domain.

`ThreadServiceBrowse(serviceType)` starts a DNS-SD browse. Poll
`ThreadServiceBrowseState()` until zero, then read up to eight labels using
`ThreadServiceBrowseResult(index)` until it returns an empty string. Resolve a
label with `ThreadServiceResolve(label, serviceType)` and poll
`ThreadServiceResolveState(ipv6Address, port)` until zero. Pending operations
return 1 and failures are negative OpenThread error codes. After a successful
resolve, `ThreadServiceResolvedTXT()` returns the raw TXT bytes and
`ThreadServiceResolvedTXTTruncated()` reports whether the 256-byte buffer was
too small. One browse and one resolve can be in flight per process.
`TThreadServiceBrowser.Start(type, intervalMs)` repeats the one-shot browse at
the chosen interval; `Poll()` returns 2 when the set of instance labels
changes, 1 while a query is pending, 0 when unchanged, or an error. Its
`Results()` returns a snapshot. Only one such browser may be active per
process. This is periodic refresh, not a push subscription. The nRF52, C6, and H2
builds can select the SRP/DNS client APIs; server hosting is tested on S31 only. The
`thread_service_echo.bmx`, `thread_service_peer.bmx`, and
`nrf52_thread_service_peer.bmx` examples show a named UDP exchange. The
`thread_service_catalog.bmx` and `nrf52_thread_service_catalog_peer.bmx`
examples exercise multiple services, TXT records, and refreshed browsing.

`Embedded.Network.ThreadCoAP` adds a bounded CoAP endpoint. Call
`ThreadCoAPStart(port)` (default 5683) and, on a server, register one URI path
with `ThreadCoAPResource(path)`. Poll `ThreadCoAPReceive(buffer, method,
sourceAddress)` from the managed task and answer with `ThreadCoAPRespond(code,
payload)`. A client sends a confirmable GET or POST with `ThreadCoAPSend` and
polls `ThreadCoAPResponse(buffer, code)`; -11 means the reply is pending.
Requests and responses are limited to 512 payload bytes, with one outstanding
request on each side. The initial API does not expose Observe, block transfers,
or secure CoAP. The `thread_coap_resource.bmx` and
`nrf52_thread_coap_peer.bmx` and `thread_coap_peer.bmx` examples use DNS-SD to
find a CoAP resource before exchanging GET and POST requests.

For unusual settings, `BMX_ESP32_EXTRA_SDKCONFIG` supplies an ESP-IDF
configuration overlay and `BMX_NRF52_EXTRA_CONF_FILE` supplies a Zephyr
overlay. Feature imports are the normal way to select support. Changing the
feature set requires rebuilding that application's firmware image.

For a two-board test, build `nrf52_thread_echo.bmx` or `thread_form_echo.bmx`
on the first board and `thread_udp_peer.bmx` on the second. The first board
resumes its saved network after reboot, forming one only when none is saved.
Copy its printed dataset and mesh IPv6 address into the peer example. The peer
sends `PING` every four seconds, and the first board echoes it. The peer prints
`THREAD_ECHO=pass` after an intact reply. H2, C6, and S31 may serve as ESP32
nodes with matching board profiles. The printed dataset is a test aid only.

On 2026-11-07, an ESP32-S31 formed a mesh as Leader and a nice!nano nRF52840
joined as Child. Repeated four-byte UDP `PING` packets were received and echoed
intact between the two physical boards.

On 2026-11-08, an ESP32-C6 SuperMini joined an ESP32-S31 standalone mesh and
repeatedly exchanged the same four-byte UDP `PING` and echo. The C6 reported
`THREAD_ECHO=pass`, while the S31 reported `THREAD_RX=4` and `THREAD_ECHO=4`.
ESP32-H2 firmware builds passed, but H2 radio operation, border routing, and
radio coexistence remain untested.

On 2026-11-08, the S31 resumed its saved network after an application flash and
another reset, reported `THREAD_NETWORK=resumed`, and remained Leader. Its UDP
echo exchange with the C6 continued on the same mesh. The nice!nano nRF52840
also reported `THREAD_NETWORK=resumed` after a new application flash and again
after a physical reset, retaining the same mesh IPv6 addresses.

The nRF52840 was then provisioned with the S31's current dataset. It joined as
Child and repeatedly received intact UDP echoes from the S31 while the C6
continued exchanging packets. After restoring the saved-network nRF52 example,
the nRF52840 reported `THREAD_NETWORK=resumed` on that same mesh.

On 2026-11-08, the S31 became an on-mesh Commissioner and authorized the C6
SuperMini by its exact factory EUI-64 and a temporary PSKd. The C6 erased its
old Thread settings, completed Joiner commissioning, and reported
`THREAD_COMMISSIONED=attached` with Child role. After flashing a different app,
the C6 reported `THREAD_NETWORK=resumed` and attached as Router, confirming
the commissioned dataset persisted. The S31 echo app was restored and received
repeated four-byte UDP packets from the C6 peer.

The nice!nano nRF52840 subsequently completed on-mesh Joiner commissioning
against the S31 Commissioner, which authorized its exact factory EUI-64. It
attached as Child and repeatedly received intact four-byte UDP echoes from
the restored S31 echo app. After restoring the nRF52 saved-network echo app,
it reported `THREAD_NETWORK=resumed` with addresses on the same mesh.

On 2026-11-08, the S31 enabled an on-mesh SRP and DNS-SD server and registered
the `_bmxecho._udp` echo service. The nRF52840, running from its saved dataset,
discovered `bmx-echo`, resolved the S31's mesh IPv6 address and UDP port, and
received repeated intact `PING` echoes. The nRF52 saved-network echo app was
restored afterward and again reported `THREAD_NETWORK=resumed` on the same mesh.
The C6 discovery peer firmware built and flashed, but yielded no application
serial output after a normal reset, so C6 discovery remains unverified on
hardware. Its previous saved-network UDP peer firmware was restored, and the
S31 again received and echoed four-byte packets from that C6 peer repeatedly.

On 2026-11-08, the S31 registered two `_bmxecho._udp` instances with distinct
ports and TXT records. The nRF52840 resumed its saved mesh, discovered both
instances, resolved each port and TXT record, and received intact UDP echoes
from both. During the S31's removal and re-registration of the second service,
the nRF52 browser reported catalog counts of two, one, then two. Both echoes
passed again after the service returned. The S31 continued echoing packets
from the C6 throughout this test. The nRF52 saved-network echo app was then
restored and reported `THREAD_NETWORK=resumed`; the restored S31 echo app again
received and echoed the C6's four-byte packets.

The initial CoAP API was tested on 2026-11-08 with the S31 hosting a DNS-SD
advertised `status` resource and the nRF52840 resuming its saved mesh. The
nRF52 resolved the CoAP service and received a confirmable GET response with
`OK` and a POST response echoing `PING`; the S31 logged successful handling of
both requests. The C6 SuperMini also resumed the saved mesh, resolved the
service, and passed the same GET and POST exchange with the S31. S31 and C6
firmware builds passed with the CoAP import, and an S31 core-only build passed
with CoAP disabled in its generated OpenThread configuration. The earlier
saved-network echo applications were restored on all three boards: the nRF52
reported `THREAD_NETWORK=resumed`, and the S31 again received and echoed UDP
packets from the C6.
