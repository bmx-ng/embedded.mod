# Multicore collection pause baseline

Measured on 2026-11-04 on the attached Pico 2 and ESP32-S3 (`esp32s3_n8r8`) using release `-gc-multicore` firmware and 64/256 KiB internal SRAM arenas. The [pause fixture](../gc_pause.bmx) keeps a chain of 1,024/4,096 Objects reachable (the forward graph reaches about 75% of arena capacity), then times twelve complete `CollectObjects()` calls with the owner alone and with a registered worker polling on the other core. It also times an alternating-link graph with the worker, and separate contiguous-garbage and fragmented-garbage sweeps of 512/2,048 Objects. Setup, graph checks and heap checks are outside the timed calls. Every image reported `checks=pass`, with no arena failure or automatic collection, and verified the expected number of explicit collections.

| Board | Arena | Live owner median / max | Live with worker median / max | Alternating links with worker median / max | Garbage sweep with worker median / max | Fragmented sweep with worker median / max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Pico 2 | 64 KiB | 1.744 / 1.752 ms | 1.928 / 1.951 ms | 1.931 / 1.937 ms | 0.280 / 0.287 ms | 0.360 / 0.360 ms |
| Pico 2 | 256 KiB | 6.926 / 6.931 ms | 7.652 / 7.678 ms | 7.666 / 7.673 ms | 1.053 / 1.061 ms | 1.373 / 1.374 ms |
| ESP32-S3 | 64 KiB | 1.946 / 1.955 ms | 1.989 / 2.005 ms | 1.991 / 2.005 ms | 0.369 / 0.371 ms | 0.493 / 0.511 ms |
| ESP32-S3 | 256 KiB | 7.696 / 7.697 ms | 7.853 / 7.859 ms | 7.853 / 7.856 ms | 1.354 / 1.356 ms | 1.851 / 1.867 ms |

The live-chain work grew approximately fourfold when the arena and live node count grew fourfold. Starting a polling worker added about 0.18/0.73 ms on Pico and 0.04/0.16 ms on ESP32-S3 at 64/256 KiB. This is the difference between two phases of the same firmware image; it includes rendezvous, the worker's roots and other collection work, so it does not isolate handshake time. Alternating physical-link direction did not materially change these samples. The temporary array used to assemble that graph raised peak arena use to about 54/214 KiB during construction; it was collected before the alternating-link samples.

These are **whole collection-call durations**. For the live cases they include stop request, worker acknowledgement where present, root discovery, marking and release. The garbage cases also include sweeping. No finalizers run. The worker polls tightly in this fixture, so these samples do not bound pause time when a task has a long poll gap or blocks without entering native-safe state. Twelve samples per case give a baseline and observed maximum, not a production latency percentile or worst-case guarantee. Phase times and request-to-ack time remain unmeasured.

The 256 KiB live-graph pauses are around 8 ms with a worker. There is no universal pause target across applications. A developer can reduce collection frequency by reusing objects and can place explicit collections at suitable points, while avoiding allocation in latency-sensitive paths. Those choices do not guarantee that an automatic collection will never occur. The current stop-the-world collector remains in place; revisit Stage 4 only when a representative application demonstrates an unacceptable pause and can compare it with the throughput, memory and complexity costs of a more complex collector.

Raw captures: [Pico 64 KiB](multicore_pause_pico2_64k.log), [Pico 256 KiB](multicore_pause_pico2_256k.log), [ESP32-S3 64 KiB](multicore_pause_esp32s3_64k.log), [ESP32-S3 256 KiB](multicore_pause_esp32s3_256k.log).
