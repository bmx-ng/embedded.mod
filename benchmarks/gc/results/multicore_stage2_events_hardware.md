# Stage 2 cross-core events and managed callbacks

The [native event fixture](../../../tests/embedded_gc_stage2_events_device.bmx) posts 100,000 ordered five-field records from a runtime-owned worker while the owner drains the fixed native queue and repeatedly collects. It verifies every field, heap integrity, no pending records and no queue drops. The Pico queue now has a multicore-only atomic lock in addition to its local interrupt mask; local interrupt masking alone did not serialize the two cores. The ESP32-S3 queue already used an SMP critical section.

The [managed callback fixture](../../../tests/embedded_gc_stage2_callbacks_device.bmx) posts 10,000 records one at a time from the worker through the same deferred bridge. The owner dispatches each record through `PollSystem` and the managed event hook, verifies every field, allocates a managed Object in the hook and collects every 64 callbacks. The worker polls while waiting for acknowledgement. Both release, 64 KiB, opt-in multicore images passed on Pico 2 and ESP32-S3 on 2026-11-04:

| Board | Native event result | Managed callback result |
| --- | --- | --- |
| Pico 2 | `GC_STAGE2_EVENTS,format=1,events=100000,ordered=pass,collection=pass,dropped=0,done=1` | `GC_STAGE2_CALLBACKS,format=1,callbacks=10000,managed=pass,collection=pass,dropped=0,done=1` |
| ESP32-S3 | Same | Same |

These checks cover a worker producer and owner consumer. They do not yet exercise a physical interrupt producer or callback re-entry from an unregistered task.

The Pico single-core event conformance image was rebuilt with and without the new queue-lock source change, using the same release settings. The runtime object-file hashes differed because their source metadata changed, but the full disassembly of generated runtime instructions matched exactly. The multicore lock is compiled out of the single-core mode.
