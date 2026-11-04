# Stage 2 managed worker API

The opt-in `Embedded.Runtime.Worker` module exposes `StartManagedWorker(entry())` and `JoinManagedWorker(waitBudget)`. The runtime registers the owner on first use, starts one no-argument managed function on the second core/task and catches an uncaught exception at the worker boundary. Join returns 1 after a normal exit, -1 after an exception, or 0 while still running. A second start before join is rejected. Shared values still require an explicit atomic handoff and precise roots.

The [fixture](../../../tests/embedded_gc_stage2_managed_api_device.bmx) starts 100 generated BlitzMax worker jobs. Each job creates and roots an Object, Array and String. The owner collects while those values live only on the worker, releases the worker, joins and collects to verify reclamation. The eighth job throws through the runtime boundary; the following jobs verify reuse. The test reports the pass line only after all collections have valid heap metadata and all three live counts return to baseline.

On 2026-11-04 both 64 KiB, opt-in multicore release images were flashed and passed on Pico 2 and ESP32-S3: `GC_STAGE2_MANAGED_API,format=1,jobs=100,objects=pass,arrays=pass,strings=pass,exception=pass,reclaim=pass,done=1`. The host root suite also passed in AddressSanitizer/UndefinedBehaviorSanitizer and ThreadSanitizer modes after the API addition.
