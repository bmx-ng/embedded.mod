# Embedded.Network.Thread

Import `NRF52.Network.Thread` or `ESP32.Network.Thread` to include the radio
adapter and the portable `Embedded.Network.Thread` core and UDP API. Imports
select optional OpenThread features for each firmware build:

| Import | Feature selected |
| --- | --- |
| `Embedded.Network.ThreadCommissioning` | Joiner and Commissioner |
| `Embedded.Network.ThreadDiscovery` | SRP client and DNS client |
| `Embedded.Network.ThreadServer` | On-mesh SRP and DNS-SD server, plus discovery client |

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
object releases its port.

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
This first API slice supports one published service per process.
The service type is a short DNS-SD type; queries use OpenThread's default
`default.service.arpa` domain.

`ThreadServiceBrowse(serviceType)` starts a DNS-SD browse. Poll
`ThreadServiceBrowseState()` until zero, then read up to eight labels using
`ThreadServiceBrowseResult(index)` until it returns an empty string. Resolve a
label with `ThreadServiceResolve(label, serviceType)` and poll
`ThreadServiceResolveState(ipv6Address, port)` until zero. Pending operations
return 1 and failures are negative OpenThread error codes. One browse and one
resolve can be in flight per process. TXT records, multiple local services,
and continuous browse updates are not yet exposed. The nRF52, C6, and H2
builds can select the SRP/DNS client APIs; server hosting is tested on S31 only. The
`thread_service_echo.bmx`, `thread_service_peer.bmx`, and
`nrf52_thread_service_peer.bmx` examples show a named UDP exchange.

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
