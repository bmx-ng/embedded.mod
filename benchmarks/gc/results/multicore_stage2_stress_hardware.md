# Stage 2 concurrent allocation and handoff stress

The [fixture](../../../tests/embedded_gc_stage2_stress_device.bmx) runs 10,000 rounds with one persistent worker and a 64 KiB managed arena. In every round both tasks allocate and root an Object, Array and String. The Object points to itself. The worker publishes all three values through atomic, precisely rooted slots, then drops its local roots. The owner collects, verifies that only the published values survive, checks every value, mutates all three, and hands ownership back. The worker verifies the mutation and clears the slots. The owner collects again and requires all three live counts to return to baseline. Each task also catches oversized Object, Array and String allocations every 128 rounds. Every collection checks heap integrity and invalid-reference count.

Both opt-in release images passed on 2026-11-04:

| Board | Result | Duration |
| --- | --- | ---: |
| Pico 2 | `GC_STAGE2_STRESS,format=1,rounds=10000,concurrent=pass,cycles=pass,mutation=pass,oom=pass,reclaim=pass,duration_us=603529,done=1` | 0.604 s |
| ESP32-S3 | Same pass fields, `duration_us=1404358` | 1.404 s |

The S3 took about 2.33 times as long for this fixture. Its first image restarted just before completing the last round: a collection request could overlap worker exit, causing unregister to fail and the runtime to panic. The trampoline now checks that no worker roots or exception frames remain, parks for the active collection and retries unregistration. A deterministic host test forces that overlap under ThreadSanitizer; the corrected S3 image completed. The final Pico timing also uses the corrected runtime.
