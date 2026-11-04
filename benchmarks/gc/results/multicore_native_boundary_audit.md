# Multicore native blocking boundary audit

The opt-in collector can trace a worker during a native block only when its live managed values remain in registered root frames and the native call does not touch managed memory. `enter_native_safe` publishes that state; `leave_native_safe` waits until any active collection ends before managed execution resumes. The owner is still the only collector.

| Boundary | Current treatment in opt-in builds |
| --- | --- |
| `SleepMicroseconds`, `SleepMilliseconds`, and legacy `Delay`/`MicroDelay` | A registered worker enters native-safe before sleeping and leaves afterward. Zero-duration calls keep their existing path. |
| Native event wait (`bmx_embedded_system_wait`) | A registered worker enters native-safe around the wait. Event queues and wake signals are native data. |
| UART readable-within, put-byte, and TX-drain waits | A registered worker enters native-safe around these scalar-only calls. |
| UART, I2C, SPI, stdio, and filesystem transfers | **Not yet certified for managed workers.** They may block while retaining a raw pointer to a caller-owned buffer. A native-safe transition would require a proven stable, rooted buffer and no concurrent access while collection runs. |
| Target power sleep and other SDK calls | **Not yet certified for managed workers.** These need separate target-specific review because they may affect both cores or SDK task state. |

The managed-worker device regression now holds an Object, Array and String across three 200 ms worker blocks (`SleepMicroseconds`, `SleepMilliseconds`, `Delay`). The owner waits 20 ms, then requires a completed collection while those values are still worker-rooted. It checks the live values after the block, joins, and checks reclamation. This covers the compiler-generated root frame across the native call as well as the runtime state transition. The C host suite separately checks native-safe re-entry during an active stop.

On 2026-11-04, the release `-gc-multicore` regression passed 100 worker jobs on the attached [Pico 2](multicore_native_boundary_pico2.log) and [ESP32-S3](multicore_native_boundary_esp32s3.log), including all three sleep paths and a completed collection for every job. Both ordinary single-core time-conformance images also compiled. The host GC suite passed under AddressSanitizer and UndefinedBehaviorSanitizer. Scalar UART waits and the native event wait compiled on both targets; they still need direct device overlap checks.

This is a bounded audit of the common scalar blocking paths, not a promise that arbitrary SDK or pointer-based calls are safe from a managed worker. The next audit should start with the managed buffer ownership contract for UART, I2C and SPI, then examine ESP32 filesystem/stdio and target-specific network operations.
