# Graphics2D benchmarks

This directory contains deterministic, allocation-free timed workloads for the
portable embedded Graphics2D renderer. The first benchmark deliberately draws
only to memory. It measures raster performance without mixing in SPI bandwidth,
DMA, VSync, or display-controller setup time.

`graphics2d_render_benchmark.bmx` runs the same suite against 160x128 RGB565 and
Mono1 buffers. It covers full and small fills, horizontal and diagonal lines,
rectangle and circle primitives, unscaled and scale-3 bitmap text, RGB565
copies, scaling, tinting, alpha blending, and a rotated drawing target.

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

## Representative UI frames

`graphics2d_ui_frame_esp32_s31_korvo_1.bmx` measures a deterministic retained
dashboard built from `Embedded.UI`. It exercises real layout, labels, status
indicators, an arc gauge, a sparkline, and a progress bar. The three cases are:

- `single_status`: one small status indicator changes;
- `dashboard_tick`: several separated dashboard values change together;
- `full_redraw`: the complete retained tree is redrawn.

Each case reports four separate phases. `ui_prepare` measures widget state
updates and invalid-region merging, `ui_render` measures retained-tree drawing,
`ui_present` measures physical display submission, and `ui_frame` is their sum.
The records also include the mean dirty-region count and pixel area, making it
possible to distinguish drawing improvements from better damage tracking or
display-driver behaviour.

Run the S31 reference workload with:

```sh
bmk makeapp -r -a -board esp32_s31_korvo_1 -heap-region psram -heap 512k -x \
    benchmarks/graphics2d/graphics2d_ui_frame_esp32_s31_korvo_1.bmx
```

This is intentionally a display-only scene. It does not import touch or the
interactive control adapter, so input polling cannot distort the frame timings.

The checked-in `results` directory contains matching S31 baseline and optimized
captures. The optimized renderer temporarily disables primitive-level damage
tracking while a retained UI region is drawn, then publishes the UI's already
merged regions once. Compare the captures with:

```sh
python3 benchmarks/graphics2d/compare_results.py \
    benchmarks/graphics2d/results/esp32_s31_korvo_1_2026-11-15_ui_frame.log \
    benchmarks/graphics2d/results/esp32_s31_korvo_1_2026-11-15_ui_frame_optimized.log
```

On the reference device this reduces best dashboard render time from 56,075 us
to 47,290 us (15.7%) and full-redraw render time from 69,544 us to 51,473 us
(26.0%). Physical presentation is synchronized to the display and can therefore
move between refresh boundaries even when drawing becomes faster; use
`ui_render` when evaluating renderer-only changes.

The scaled-text captures add `text_spleen_5x8_scale3` to the raster suite. On
the S31, emitting enlarged RGB565 mask rows as horizontal runs reduces this
case from 23,523 us to 21,084 us (10.4%) without changing unscaled RGB565 or
Mono1 output. In the representative dashboard capture, the same change reduces
best dashboard rendering from 47,290 us to 45,670 us (3.4%) and full redraw
rendering from 51,473 us to 49,556 us (3.7%).
