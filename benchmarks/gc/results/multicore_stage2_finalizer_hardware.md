# Stage 2 finalizer concurrency device check

The [fixture](../../../tests/embedded_gc_stage2_finalizer_device.bmx) starts a registered worker, allocates 24 finalizable Objects on the owner, then collects. The first finalizer releases the worker to allocate 300 managed Objects while the owner invokes the remaining finalizers. The owner checks the heap, collects again to reclaim both sets of Objects, and verifies that each finalizer ran exactly once. The [host test](../../../tests/embedded_gc_stage2_finalizer_concurrency_host.c) additionally throws from the second finalizer while the worker allocates, then checks cleanup and later reclamation under both AddressSanitizer/UndefinedBehaviorSanitizer and ThreadSanitizer.

On 2026-11-04, the opt-in 64 KiB arena images built for Pico 2 and ESP32-S3. The Pico 2 image was flashed and verified, then reported `GC_STAGE2_FINALIZER,format=1,allocation=pass,finalizers=pass,reclaim=pass,done=1`. The ESP32-S3 image was flashed and hash-verified, started with a watchdog reset, and reported the same result.

This checks one worker and one finalizer cycle per device. It does not cover repeated worker lifecycle or every callback and native-block interleaving.
