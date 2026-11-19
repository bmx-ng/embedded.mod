# Embedded module tests

The individual `.bmx` files are hardware or build fixtures. UI changes should
at minimum preserve the broad conformance suite, the steady-state allocation
test and the three firmware tiers.

Hardware bring-up programs which require explicitly wired peripherals live
under `tests/hardware`. They are not part of unattended conformance runs. The
ST7735 Pico 2 W fixture documents its SPI0 wiring in constants and presents
RGB colour bars, text, and primitive drawing through the normal Graphics2D
framebuffer path.

## UI firmware-tier matrix

`run_ui_tier_matrix.sh` builds display-only, controls-only and touch-enabled
firmware, then checks both their linker maps and binary sizes. It verifies that:

- display-only firmware links neither controls nor touch support;
- controls-only firmware links controls but not touch support;
- interactive firmware links both optional layers;
- each image remains within its target budget; and
- the size differences between adjacent tiers remain plausible.

Run both default reference boards with:

```sh
tests/run_ui_tier_matrix.sh all
```

Pass `pico` or `esp32` instead of `all` to test one platform. The defaults are
`pico2_w` and `esp32_s31_korvo_1`; override them with
`UI_TEST_PICO_BOARD` and `UI_TEST_ESP32_BOARD`. Set `UI_TEST_BMK` to select a
particular `bmk` executable, or `UI_TEST_REBUILD=0` for an incremental local
run. The script never flashes a device.

The budgets measure the generated application `.bin`, which is comparable
within one target toolchain. Target-specific ceilings can be adjusted with
`UI_TEST_PICO_PASSIVE_MAX`, `UI_TEST_PICO_CONTROLS_MAX`,
`UI_TEST_PICO_INTERACTIVE_MAX` and their `UI_TEST_ESP32_*` counterparts when a
reviewed SDK or feature change deliberately moves the baseline.

## HTTPS server soak tests

`httpserver_mixed_device.bmx` is a hardware fixture for concurrent HTTPS,
server-sent events, and compressed WebSocket traffic. Build an ignored local
copy with Wi-Fi credentials and a temporary test certificate, then flash the
board. Keep credentials and private keys out of the repository. The fixture
reports managed heap integrity, allocation failures, and reusable bytes at
`/metrics`.

With the test image running, use its local IP address:

```sh
python3 -u tests/soak_httpserver_mixed_device.py DEVICE_IP --duration 600 --live-clients 3
```

The separate `httpserver_ws_device.bmx` fixture supports a longer WebSocket
session test, including compressed text, binary messages, fragmentation,
ping/pong, idle recovery, and repeated close/reconnect:

```sh
python3 -u tests/soak_httpserver_ws_device.py DEVICE_IP --duration 600
```

Both clients pin the certificate currently presented by the local test image
and verify it on subsequent connections. Use `--live-clients 2` to close the
SSE stream before opening the HTTP requests while the WebSocket remains open.
Each client exits on its first unexpected response or connection error.
The WebSocket client also accepts `--reconnect-delay-ms` for testing how a
short pause between sessions affects a single-connection server.

On the tested ESP32-S3, reserving a 256 KB managed heap in internal SRAM
caused intermittent TLS handshake resets during repeated compressed WebSocket
sessions. A 128 KB SRAM heap and a 512 KB PSRAM heap both completed seven-minute
single-connection runs. For an ESP32-S3 with PSRAM, build the HTTPS fixture with
`-heap-region psram -heap 512k` so internal SRAM remains available to TLS and
the network stack. Recheck the memory budget on other boards.

## Responsive layout matrix

`embedded_ui_layout_matrix.bmx` builds the same passive six-card composition
at 128x64, 320x240 and 800x480. It verifies the adaptive one-, two- and
five-column layouts, walks the retained tree iteratively to reject invalid or
unclipped out-of-frame geometry, and repeats the checks after a dirty redraw.
It deliberately imports no controls or touch adapter, so it also remains a
display-only build fixture suitable for resource-constrained targets.

`embedded_ui_dirty_equivalence.bmx` renders matching retained trees through
normal dirty invalidation and forced full redraws, then compares every raster
byte after value changes, visibility-driven reflow and restoration. Both
one-bit and RGB565 framebuffers are covered.
