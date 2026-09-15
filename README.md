# BlitzMax embedded runtime

This module family owns the compact runtime ABI shared by constrained embedded
targets. It contains managed allocation, precise roots, garbage collection,
finalization, core type layouts, strings, arrays, objects, enums, and exception
frames. Target repositories provide the small platform contract used for
execution-context checks, panic handling, and managed-arena placement.

`HeapIntegrityValid()` audits the arena's physical block chain, free list,
allocation flags, bounds, alignment, and live allocation metrics without
changing heap state. It is intended for hardware stress tests and diagnostics.

Managed Object, Array, and String allocation first performs automatic
collection and one retry. If that retry fails, the runtime throws a static
String describing the allocation kind, so failure itself requires no heap
memory and can be caught by BlitzMax `Try/Catch`. With no active exception
frame the target panic handler receives the same type-specific message. Raw
`MemAlloc` remains explicitly fallible and returns `Null` on exhaustion.
Uncaught String exceptions are reported as bounded UTF-8 without allocating.
Uncaught Object exceptions use their generated `ToString` hook, falling back
to the concrete type name if formatting fails. The target remains responsible
for printing, halting, or resetting after receiving that shared message.
Ordinary `Object.ToString()` calls and Object-to-String conversions use the
same generated hook, with an allocation-backed pointer representation when a
concrete type does not override it. Overrides of `ToString`, `Compare`,
`HashCode`, and `Equals` may call `Super` through the base type's compact hook.
`Object.SendMessage` likewise supports overrides, virtual calls, direct `Super`
calls, and the standard `Null` fallback through a compact descriptor hook.
Virtual and Interface methods may return callable values; compact method tables
preserve the callable's nested function-pointer ABI during dispatch.
If an exception escapes a finalizer, the interrupted collection discards its
pending-finalizer queue and returns the collector to an idle state. Finalizers
already entered remain at-most-once, while untouched finalizers are eligible
again on the next collection.

`Embedded.Hardware.GPIO` is the first portable hardware API. It provides the
digital I/O, pull resistor, and qualitative drive-strength operations whose
semantics can be kept equivalent across embedded targets. Each target owns the
native implementation behind the neutral `bmx_embedded_gpio_*` ABI.

`Embedded.System.Time` provides 64-bit monotonic microsecond and millisecond
clocks plus sleep operations with equivalent minimum-duration semantics. Clock
trees, alarms, timer channels, and interrupt hand-off remain target-specific.

Where a portable module has a target-specific counterpart, target repositories
should mirror its namespace layout and equivalent operation names, then add
capabilities which only that target can support.

`Embedded.Hardware.UART` provides the common low-level controller contract:
pin routing, initialization, baud and frame format, flow control, synchronous
I/O, deadline reads, status, persistent break, CRLF translation, and error
flags. Target-only controller features remain in the matching target module.

`Embedded.Hardware.BufferedUART` adds a managed receive buffer and line-oriented
helpers above that common UART contract. `Embedded.Hardware.GPIOEvents` turns
target interrupt notifications into events drained safely by the managed owner
task; native interrupt handlers never enter BlitzMax directly.

`Embedded.Hardware.I2C` provides portable master-controller configuration,
blocking and deadline reads and writes, and an atomic repeated-Start write/read
operation. Slave operation, raw FIFO access, and other controller-specific
features remain target-owned.

`Embedded.Hardware.SPI` provides portable controller configuration plus 8-bit
and 16-bit blocking simplex and full-duplex transfers. Applications control
chip select through `Embedded.Hardware.GPIO`, leaving target-specific peripheral
and DMA facilities in the target module.

`Embedded.Hardware.ADC` provides pin-oriented initialization and single raw
conversions with explicit resolution and range discovery. Calibration,
attenuation, converter sequencing, FIFOs, and DMA remain target-specific.

`Embedded.Hardware.PWM` provides pin-oriented frequency, duty, polarity, and
enable control. Duty uses a portable 0-65535 scale; targets quantize it to their
hardware resolution and reject resource changes that would silently retune
another configured output.

`Embedded.Hardware.Watchdog` provides portable watchdog enable, feed, disable,
status, timeout validation, and watchdog-reset detection. Timing inspection and
debugger-pause controls remain available through target modules where supported.

`Embedded.System.Device` provides a target-derived unique identifier, normalized
reset reasons, and reboot requests. Identifier sizes and the reset distinctions
available after startup vary by target.

`Embedded.Text.Unicode` optionally enables the shared Unicode String case and
case-folding tables. Without that import, embedded applications retain the
smaller ASCII-only implementation.

`Embedded.Random` connects each target's native device-entropy source to the
standard `Random.Core` generator API. It also exposes raw 32-bit and 64-bit
values and buffer filling. Entropy guarantees and explicit source controls
remain target-specific.

SDK startup, board selection, peripheral features without equivalent semantics,
standard I/O transports, and interrupt hand-off remain target-owned.
