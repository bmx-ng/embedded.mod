# Multicore collection phase measurements

Measured on 2026-11-04 on the attached Pico 2 and ESP32-S3 (`esp32s3_n8r8`). Both used release `-gc-multicore` firmware, a 256 KiB internal SRAM arena, and `BMX_EMBEDDED_GC_PHASE_TIME=1`. This is the same [pause fixture](../gc_pause.bmx) as the [whole-call baseline](multicore_pause_baseline.md), with clock reads around stop request and acknowledgement, reachability audit, and sweep. Each case has twelve samples. Every run reported `checks=pass` and `done=1`.

All values below are microseconds. `Total` is the complete `CollectObjects()` call; phase times are subsets of that call. The stop column shows median and observed maximum to expose handshake variation. The other columns show medians.

| Board | Case | Total median | Stop median / max | Mark median | Sweep median |
| --- | --- | ---: | ---: | ---: | ---: |
| Pico 2 | Live, owner only | 6,933 | 0 / 1 | 6,931 | 0 |
| Pico 2 | Live, worker polling | 7,675 | 1 / 9 | 7,671 | 0 |
| Pico 2 | Alternating links, worker | 7,675 | 1 / 2 | 7,671 | 0 |
| Pico 2 | Contiguous garbage, worker | 1,109 | 1 / 2 | 22 | 848 |
| Pico 2 | Fragmented garbage, worker | 1,443.5 | 1 / 1 | 22 | 1,052.5 |
| ESP32-S3 | Live, owner only | 7,760 | 3.5 / 4 | 7,748.5 | 0 |
| ESP32-S3 | Live, worker polling | 7,920.5 | 10 / 17 | 7,902 | 0 |
| ESP32-S3 | Alternating links, worker | 7,920.5 | 10 / 12 | 7,902 | 0 |
| ESP32-S3 | Contiguous garbage, worker | 1,355 | 10 / 12 | 30 | 992.5 |
| ESP32-S3 | Fragmented garbage, worker | 1,851 | 9.5 / 13 | 30 | 1,343.5 |

With this tightly polling worker, the stop request was a small part of each measured pause. The live graph was dominated by marking. Most of the fragmented-garbage call was sweeping; time outside the three measured phases includes collector bookkeeping and scanning for finalizers. The additional time with a worker in the live cases appears primarily within reachability audit, which also scans the worker's roots. These data do not isolate the reason for every part of that difference.

These phase readings add clock calls to the collector and should only be compared within the diagnostic firmware. The worker polls tightly, so the observed stop times do not bound arbitrary poll gaps or a native call that fails to enter native-safe state. No finalizers run in this fixture. Twelve samples provide observed medians and maxima, not a worst-case latency bound. The diagnostic result does not justify changing the stop-the-world design without an application pause target and a measured alternative.

The ESP32-S3 also emitted an IDLE0 task-watchdog warning during the fixture's CPU-intensive heap-integrity validation, outside the timed collection calls. The warning did not reset the device; a repeat run produced the same passing results. The serial capture begins at the result block and does not include the earlier warning. The stack trace on the monitoring run resolved to `bmx_embedded_heap_integrity_valid_unlocked` from `bmx_sweep_prepare`.

Raw captures: [Pico 2](multicore_pause_phases_pico2_256k.log), [ESP32-S3](multicore_pause_phases_esp32s3_256k.log). Build from the SDK checkout, for example:

```sh
BMX_EMBEDDED_GC_PHASE_TIME=1 ./bin/bmk makeapp -a -r -l pico -g arm -board pico2 -heap 256k -gc-multicore -o /tmp/gc_pause_phase_pico2 mod/embedded.mod/benchmarks/gc/gc_pause.bmx
BMX_EMBEDDED_GC_PHASE_TIME=1 ./bin/bmk makeapp -a -r -l esp32 -board esp32s3_n8r8 -heap 256k -gc-multicore -o /tmp/gc_pause_phase_esp32.bin mod/embedded.mod/benchmarks/gc/gc_pause.bmx
```
