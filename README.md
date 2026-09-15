# BlitzMax embedded modules

`embedded.mod` is the portable foundation for BlitzMax applications running on
microcontrollers. It provides the compact managed runtime used by embedded
targets and a growing set of hardware, networking, I/O, and system APIs whose
behaviour can be kept consistent across different device families.

Applications use these modules through a supported target distribution. The
target supplies its SDK integration, board definitions, upload process, and the
native adapter behind each portable API:

- [pico.mod](https://github.com/bmx-ng/pico.mod) supports Raspberry Pi Pico
  boards.
- [esp32.mod](https://github.com/bmx-ng/esp32.mod) supports Espressif ESP32
  devices.

See the target README for installation, board selection, build options, and
upload instructions.

## Portable and target-specific APIs

Use an `Embedded.*` module when an application should run on more than one
embedded target. Use `Pico.*` or `ESP32.*` when the hardware exposes a useful
feature which cannot be represented honestly by a common API.

For example, ordinary digital I/O can be portable:

```blitzmax
SuperStrict

Import Embedded.Hardware.GPIO
Import Embedded.System.Time

Const LEDPin:UInt = 4

GPIOInit(LEDPin)
GPIOSetOutput(LEDPin)

While True
    GPIOPut(LEDPin, True)
    SleepMilliseconds(250)
    GPIOPut(LEDPin, False)
    SleepMilliseconds(250)
Wend
```

Board pin numbers and electrical suitability are still properties of the
selected board. A portable application should keep those choices in its board
configuration rather than assume every board routes the same pins.

Target-specific code can live beside the shared part when necessary:

```blitzmax
?pico
Import Pico.Hardware.PIO
?esp32
Import ESP32.Storage.NVS
?
```

The target namespaces are not deprecated or second-class. They are the right
place for PIO, ESP32 NVS, OTA, detailed radio controls, native DMA facilities,
and other capabilities that do not share equivalent semantics.

## Shared module map

| Module | Portable contract |
| --- | --- |
| `Embedded.Hardware.GPIO` | Digital input/output, pull resistors, drive strength, and interrupt configuration |
| `Embedded.Hardware.GPIOEvents` | GPIO interrupts delivered safely as BlitzMax events |
| `Embedded.Hardware.ADC` | Pin-oriented one-shot conversion, resolution, and input-range discovery |
| `Embedded.Hardware.PWM` | Pin-oriented frequency, polarity, enable, and 16-bit-scaled duty control |
| `Embedded.Hardware.I2C` | Master setup, deadline reads and writes, and repeated-Start write/read transactions |
| `Embedded.Hardware.SPI` | 8-bit and 16-bit blocking simplex and full-duplex transfers |
| `Embedded.Hardware.UART` | Controller setup, pin routing, framing, flow control, synchronous I/O, deadlines, break, and error state |
| `Embedded.IO.BufferedUART` | A managed receive buffer and `TStream`-compatible, line-oriented UART access |
| `Embedded.Hardware.Watchdog` | Enable, feed, disable, timeout validation, status, and reset detection |
| `Embedded.Network.WiFi` | Station initialization, scanning, joining, link state, and IPv4 configuration |
| `Embedded.Network.BLE` | Scanning, advertising, connections, GATT client/server operation, security, bonding, MTU, and PHY controls |
| `Embedded.Random` | Device entropy through the standard `Random.Core` generator API, plus raw values and buffer filling |
| `Embedded.System.Time` | Monotonic microsecond/millisecond clocks and minimum-duration sleeps |
| `Embedded.System.Device` | Unique device identity, normalized reset reasons, and reboot requests |
| `Embedded.System.Power` | Capability-driven idle, returning sleep, dormant sleep, and low-leakage pin operations |
| `Embedded.Text.Unicode` | Optional Unicode String case and case-folding tables; without it the compact runtime remains ASCII-only |
| `Embedded.Runtime.Memory` | Managed-arena, collection, finalizer, root, allocation-failure, and integrity diagnostics |
| `Embedded.Runtime.Events` | Registration and accounting for events deferred out of native callback context |

Not every target or board implements every optional operation. APIs which need
optional hardware expose capability queries or return an explicit unavailable
or invalid-state result. Consult the matching target module for native
extensions and target-specific restrictions.

## Events and native callbacks

Native interrupt and SDK callback contexts must not allocate managed objects or
enter arbitrary BlitzMax code. Target adapters copy bounded data into native
queues. `PollSystem()` or `WaitSystem()` later converts those records into
managed events in the application context.

This affects GPIO events, Wi-Fi, BLE, and similar asynchronous services. An
application using them must keep servicing the system event loop. The relevant
modules expose dropped-event counters where queue pressure can lose records.

## Managed runtime behaviour

Embedded targets use a compact, precise managed runtime rather than the desktop
runtime ABI. It supports ordinary BlitzMax objects, arrays, strings, enums,
inheritance, virtual and interface dispatch, exceptions, finalizers, and
precisely described roots.

Managed allocation performs collection and one retry before throwing a static,
allocation-free String exception. This means allocation failure from `New`,
array creation, and String creation can be caught with normal `Try/Catch`.
Uncaught failures are passed to the target panic handler. Raw `MemAlloc()` is
deliberately different: it remains fallible and returns `Null`.

`Embedded.Runtime.Memory` exposes heap capacity, use, high-water marks,
allocation and collection counts, finalizer state, root counts, reachability
audits, and `HeapIntegrityValid()` for hardware stress tests and diagnostics.

Assertions are removed from release builds. In debug builds a failed `Assert`
uses the embedded exception/panic path; embedded targets do not maintain a
separate BlitzMax debug stack.

Low-level ABI details and the requirements for adding another embedded backend
are documented in [Runtime and target integration](docs/runtime-integration.md).

## What remains target-owned

The shared layer only includes concepts with genuinely comparable behaviour.
The target repositories continue to own:

- SDK startup, CPU and board selection, memory-map and flash configuration;
- board profiles, pin aliases, console transports, building, uploading, and
  device inspection;
- filesystems and storage layout, including LittleFS, SD cards, NVS, and OTA
  partitions;
- hardware engines such as Pico PIO or target-specific DMA and timer channels;
- radio modes and security facilities beyond the common Wi-Fi and BLE
  contracts; and
- debugger integration, reset/boot modes, and target-specific power states.

That boundary is intentional: portable programs can stay with `Embedded.*`,
while device-focused programs retain access to the complete target API.

## Testing portability

The `tests` directory contains shared conformance programs for the language
runtime and portable modules. The Pico and ESP32 repositories build and run
those programs through their own SDKs and hardware test scripts. A change to a
shared contract should be exercised on both target families before it is
considered portable.

Generated `.bmx` build directories are local build output and are ignored by
the repository.
