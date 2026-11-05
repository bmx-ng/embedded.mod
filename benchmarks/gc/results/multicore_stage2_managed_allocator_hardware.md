# Stage 2 managed allocator device check

The [fixture](../../../tests/embedded_gc_stage2_managed_allocator_device.bmx) launches a registered native worker on the second core/task. It allocates and roots an Object, Array and String, then verifies that an oversized String allocation throws to the worker's own exception handler. The worker enters native-safe state and blocks without touching the heap while the owner collects. On re-entry it checks its values, then drops the roots; the owner collects again and checks reclamation. The worker unregisters before the fixture reports success.

On 2026-11-04, the opt-in 64 KiB arena image built for Pico 2 and ESP32-S3. The Pico 2 image was flashed, verified and started; its serial monitor reported `GC_STAGE2_ALLOCATOR,format=1,objects=pass,arrays=pass,strings=pass,oom=pass,native_safe=pass,done=1`. The ESP32-S3 image was flashed and hash-verified, then started with a watchdog reset. Its serial monitor reported the same passing result. Both devices ran the images rebuilt after the native-safe runtime entry points were added.

This fixture proves worker allocation and collection on the two target runtimes one board at a time. It does not exercise simultaneous allocations on the board, cross-core publication of managed references, or shared object mutation. Those remain part of the Stage 2 gate.
