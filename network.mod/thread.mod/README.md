# Embedded.Network.Thread

Import `NRF52.Network.Thread` or `ESP32.Network.Thread` to include the radio
adapter and the portable `Embedded.Network.Thread` API. This module is opt-in.
The current targets are nRF52840 with Zephyr 4.5.0 and ESP32-H2/C6/S31 with the
project's ESP-IDF 6.1 toolchain. RP/Pico needs an external IEEE 802.15.4 radio
and has no adapter here.

`ThreadForm(name, channel)` generates a fresh active operational dataset and
starts a mesh. `ThreadActiveDataset()` returns that dataset as hexadecimal text.
`ThreadJoin(datasetHex)` installs an existing active dataset and starts the
Thread interface. This is out-of-band provisioning: it does not perform Thread
Joiner commissioning. `ThreadLeave()` disables the Thread interface; the
installed dataset remains available for a later join. A dataset contains the
network key: treat it as a secret and do not print it in production firmware.

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

For a two-board test, build `nrf52_thread_echo.bmx` or `thread_form_echo.bmx`
on the first board and `thread_udp_peer.bmx` on the second. Copy the first
board's printed dataset and mesh IPv6 address into the peer example. The peer
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
