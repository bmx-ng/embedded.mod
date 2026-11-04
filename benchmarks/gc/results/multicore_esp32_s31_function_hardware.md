# ESP32-S31 Function-CoreBoard-1 multicore GC hardware check

On 2026-11-04, the attached board identified as an ESP32-S31 revision 0.0
with two application cores, 16 MB flash, and 16 MB PSRAM. The release fixtures
used `-board esp32_s31_function_coreboard_1 -g riscv32 -gc-multicore` and a
64 KiB managed heap. Each application image was flashed over the UART bridge,
hash-verified by esptool, and checked after a serial reset against its project
boot banner and completion marker.

| Fixture | Heap | Serial result |
| --- | --- | --- |
| [Core handshake](../../../tests/embedded_gc_handshake_device.bmx) | SRAM | `GC_HANDSHAKE,format=1,checks=pass,done=1` |
| [Managed worker API](../../../tests/embedded_gc_stage2_managed_api_device.bmx) | SRAM | `GC_STAGE2_MANAGED_API,format=2,jobs=100,objects=pass,arrays=pass,strings=pass,exception=pass,reclaim=pass,native_sleep=pass,collections=pass,done=1` |
| [Concurrent stress](../../../tests/embedded_gc_stage2_stress_device.bmx) | SRAM | `GC_STAGE2_STRESS,format=1,rounds=10000,concurrent=pass,cycles=pass,mutation=pass,oom=pass,reclaim=pass,duration_us=683984,done=1` |
| [Finalizers](../../../tests/embedded_gc_stage2_finalizer_device.bmx) | SRAM | `GC_STAGE2_FINALIZER,format=1,allocation=pass,finalizers=pass,reclaim=pass,done=1` |
| [Concurrent stress](../../../tests/embedded_gc_stage2_stress_device.bmx) | PSRAM | `GC_STAGE2_STRESS,format=1,rounds=10000,concurrent=pass,cycles=pass,mutation=pass,oom=pass,reclaim=pass,duration_us=683517,done=1` |

The two stress runs completed in about 0.684 seconds each. This fixture is a
functional stress check; its duration alone does not measure general
application throughput or PSRAM latency.

The initial RISC-V multicore build failed before flashing because the compiler
looked for the ordinary `BRL.Blitz` interface while bmk had emitted the
`.gcmc` interface. The [compiler fix](../../../../blitzmax.mod/compiler.mod/compiler_options.bmx)
uses the multicore suffix for imported interfaces. A compiler regression using
only a multicore RISC-V interface failed with the previous compiler and passed
with the fix. All five device images above used the corrected compiler from
`blitzmax.mod` commit `6118518` and the S31 board profile in `esp32.mod`
commit `cefd26d`.

The generated application image SHA-256 values, in table order, were:

```text
58cb5400f9cb3b8eb1b60bfbc3d70a84623c078ba8248ed9e0cc2928fad1ecb5
27d5f3b25675789b3c7fefbddbba44e4407051f73d8d6bc6f5c911124068e1e8
ab3d95e9221fd9d5ebad3ac02f2d4de6f6d32f63be9dafb1e85f1149e94bf41d
d98c59d969bb17b839a4aa0f9a73f2837780a76c276856e0dbc46fb14011f2d2
4f8c3e44379efe4b404fabd8185ded5991469a05bcb13956717838bd6f01db13
```
