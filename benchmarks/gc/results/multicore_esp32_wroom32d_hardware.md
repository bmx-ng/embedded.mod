# ESP32-WROOM-32D multicore GC hardware check

On 2026-11-04, the connected ESP32-WROOM-32D identified as an ESP32-D0WD-V3
revision 3.1 with two cores, 4 MB flash, and no PSRAM. Each fixture was built
in release mode with `-board esp32_wroom_32d -heap 64k -gc-multicore`, flashed
over its UART port, and hash-verified by esptool. The serial checker reset the
board and required the matching project boot banner and completion marker.

| Fixture | Serial result |
| --- | --- |
| [Core handshake](../../../tests/embedded_gc_handshake_device.bmx) | `GC_HANDSHAKE,format=1,checks=pass,done=1` |
| [Managed worker API](../../../tests/embedded_gc_stage2_managed_api_device.bmx) | `GC_STAGE2_MANAGED_API,format=2,jobs=100,objects=pass,arrays=pass,strings=pass,exception=pass,reclaim=pass,native_sleep=pass,collections=pass,done=1` |
| [Concurrent stress](../../../tests/embedded_gc_stage2_stress_device.bmx) | `GC_STAGE2_STRESS,format=1,rounds=10000,concurrent=pass,cycles=pass,mutation=pass,oom=pass,reclaim=pass,duration_us=1486838,done=1` |
| [Finalizers](../../../tests/embedded_gc_stage2_finalizer_device.bmx) | `GC_STAGE2_FINALIZER,format=1,allocation=pass,finalizers=pass,reclaim=pass,done=1` |

The stress result covers 10,000 concurrent allocation rounds in 1.487 seconds.
These checks exercise the opt-in collector on the original ESP32 target with
an SRAM arena. They do not measure stop-the-world pause time or application
throughput.

The fixtures used `embedded.mod` collector commit `7be8ed7` and `esp32.mod`
commit `cefd26d`, which includes the WROOM-32D board profile. The generated
application image SHA-256 values, in table order, were:

```text
a3acecbc5926b9dc74a0c431e11c7e97e93fbabbd0a873d5b0c03ec729cd9555
a202e3d90a922f267ca566b95ff05b564fec51cc09769fe0a97d3d49bc3cd289
6de7a17475c57c2aed5355aa14d9a78567862ce225f0f8d0ae14ea719f73896d
eeab0c46b2d0dbf3cebef2e5a8ced4220a127756f885b00b5aff5daef3f09e28
```
