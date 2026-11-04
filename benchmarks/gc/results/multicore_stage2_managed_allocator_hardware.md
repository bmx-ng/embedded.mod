# Stage 2 managed allocator device check

The [fixture](../../../tests/embedded_gc_stage2_managed_allocator_device.bmx) launches a registered native worker on the second core/task. It allocates and roots an Object, Array and String, then verifies that an oversized String allocation throws to the worker's own exception handler. The owner collects while those roots are held, checks all three live counts and heap integrity, then collects again after the worker drops the roots and checks reclamation. The worker checks its values after the first collection and unregisters before the fixture reports success.

On 2026-11-04, the opt-in 64 KiB arena image built for Pico 2 and ESP32-S3. The Pico 2 image was flashed, verified and started; its serial monitor reported `GC_STAGE2_ALLOCATOR,format=1,objects=pass,arrays=pass,strings=pass,oom=pass,done=1`. The ESP32-S3 image was flashed and hash-verified, then started with a watchdog reset. Its serial monitor reported the same passing result. Both devices ran the images rebuilt after the final allocator changes.

This fixture proves worker allocation and collection on the two target runtimes one board at a time. It does not exercise simultaneous allocations on the board, cross-core publication of managed references, or shared object mutation. Those remain part of the Stage 2 gate.
