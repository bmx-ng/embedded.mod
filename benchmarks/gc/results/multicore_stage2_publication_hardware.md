# Stage 2 atomic publication device check

The [fixture](../../../tests/embedded_gc_stage2_publication_device.bmx) roots three atomic reference slots in the owner task. A registered worker allocates and initializes an Object with a self-cycle, an Array and a String, then publishes each pointer with a release store and drops its local roots. The owner collects and verifies that the atomic slots alone retain all three allocations. The tasks take turns mutating and reading the values, using release/acquire commands to transfer write ownership. After both tasks drop their references, the owner collects again and checks reclamation.

On 2026-11-04, the opt-in 64 KiB arena image built for Pico 2 and ESP32-S3. The Pico 2 image was flashed and verified, then its serial monitor reported `GC_STAGE2_PUBLICATION,format=1,objects=pass,arrays=pass,strings=pass,cycle=pass,mutation=pass,reclaim=pass,done=1`. The ESP32-S3 image was flashed and hash-verified, started with a watchdog reset, and reported the same passing result.

This tests one cross-core handoff on each board. It does not prove that unsynchronized shared object fields are safe, nor does it cover repeated create/join, native blocking or callback interleavings.
