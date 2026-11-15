# Graphics2D benchmarks

This directory contains deterministic, allocation-free timed workloads for the
portable embedded Graphics2D renderer. The first benchmark deliberately draws
only to memory. It measures raster performance without mixing in SPI bandwidth,
DMA, VSync, or display-controller setup time.

`graphics2d_render_benchmark.bmx` runs the same suite against 160x128 RGB565 and
Mono1 buffers. It covers full and small fills, horizontal and diagonal lines,
rectangle and circle primitives, bitmap text, RGB565 copies, scaling, tinting,
alpha blending, and a rotated drawing target.

Each workload is warmed twice and measured seven times. Output uses stable
comma-separated `key=value` records beginning with `G2D_BENCH`. Sample rows
preserve timing variation; summary rows provide the best and arithmetic mean.
The best time is useful for comparing raster changes because it is least
affected by interrupts. Every sample also checksums the complete framebuffer.
The run fails if identical workloads produce different pixels.

Build a release firmware in the usual way, for example:

```sh
bmk makeapp -r -a -board pico2 benchmarks/graphics2d/graphics2d_render_benchmark.bmx
bmk makeapp -r -a -board baguette_s3 benchmarks/graphics2d/graphics2d_render_benchmark.bmx
```

Graphics workloads may use a larger managed heap. On a PSRAM-equipped ESP32,
for example:

```sh
bmk makeapp -r -a -board esp32_s31_korvo_1 -heap-region psram -heap 512k \
    benchmarks/graphics2d/graphics2d_render_benchmark.bmx
```

Capture the serial output before and after a renderer change, then compare it:

```sh
python3 benchmarks/graphics2d/compare_results.py before.log after.log
```

The comparison reports `old / new` speedup and elapsed-time percentage change.
A positive speedup above `1.00x`, or a negative percentage, is an improvement.

## Benchmark rules

- Use release builds; debug builds measure checking and instrumentation.
- Keep the board, CPU frequency, compiler and build options unchanged.
- Do not compare results with different `format` values.
- Preserve workload iteration counts when creating an optimisation baseline.
- Rendering and physical presentation must remain separate measurements.
- Add a new workload rather than changing an existing workload's meaning.

Physical presentation benchmarks will use this core with an initialized display
and driver-owned framebuffer. Create the benchmark with `CreateWithBuffer`, then
call `RunPresentationSuite(display)`. It measures complete, half-size, 32x32,
and two-region updates. Those results use `phase=present` so SPI or parallel-
transfer improvements cannot be mistaken for raster improvements. A hardware
launcher is intentionally responsible for pins, bus rate and display setup,
which must be recorded alongside its captured results.

The ESP32-S31 Korvo-1 800x480 RGB launcher is provided as a reference physical
adapter:

```sh
bmk makeapp -r -a -board esp32_s31_korvo_1 -heap-region psram -heap 512k -x \
    benchmarks/graphics2d/graphics2d_present_esp32_s31_korvo_1.bmx
```
