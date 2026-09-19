# Embedded GC benchmarks

Both programs use the production mark-queue collector. They perform internal
heap checks and print one completion marker on success. Neither runs managed
work on the second core.

- `gc_benchmark.bmx` measures ordinary field updates, tracing a backward
  allocation-order chain, and reclaiming short-lived objects.
- `gc_varied.bmx` covers an almost empty heap, a forward chain, a wide graph
  with shared references, a cycle with Strings and Arrays, and mixed garbage.
  It checks graph contents and reclamation, then holds a live graph through
  allocation pressure that forces automatic collections.

Build either program from the Pico or ESP32 SDK checkout with the same board
and heap settings that the application will use. These examples use a 64 KiB
managed heap:

Pico 2 W, from `BlitzMax-pico`:

```sh
./bin/bmk makeapp -a -r -l pico -g arm -board pico2_w -heap 64k -o /private/tmp/gc_benchmark mod/embedded.mod/benchmarks/gc/gc_benchmark.bmx
./bin/bmk makeapp -a -r -l pico -g arm -board pico2_w -heap 64k -o /private/tmp/gc_varied mod/embedded.mod/benchmarks/gc/gc_varied.bmx
```

Flash, verify, and capture each UF2 image with `capture_pico.py`. Put
`picotool` on `PATH` or set `PICOTOOL`, and pass the connected USB serial port:

```sh
python3 mod/embedded.mod/benchmarks/gc/capture_pico.py /private/tmp/gc_benchmark.uf2 benchmark.log --port /dev/cu.usbmodem101
python3 mod/embedded.mod/benchmarks/gc/capture_pico.py /private/tmp/gc_varied.uf2 varied.log --port /dev/cu.usbmodem101 --marker GC_VARIED
python3 mod/embedded.mod/benchmarks/gc/summarize.py benchmark.log varied.log
```

The capture script requires the corresponding `done=1` line. `summarize.py`
also checks sample completeness, graph checks, checksum, and automatic
collection count. Each collection case reports 12 microsecond samples.
Enter BOOTSEL manually if the board's existing firmware does not respond to
`picotool`'s reset request.

ESP32-S3 44-pin N16R8, from `BlitzMax-esp32`:

```sh
./bin/bmk makeapp -a -r -l esp32 -g xtensa -board esp32s3_44pin_n16r8 -heap 64k -o /private/tmp/gc_benchmark mod/embedded.mod/benchmarks/gc/gc_benchmark.bmx
./bin/bmk makeapp -a -r -l esp32 -g xtensa -board esp32s3_44pin_n16r8 -heap 64k -o /private/tmp/gc_varied mod/embedded.mod/benchmarks/gc/gc_varied.bmx
```

Connect the USB-C socket labelled `COM`. Set `ESPPORT` to its CH343P serial
device and add `-x` to the build command to flash and verify. The ESP-IDF Tools
Python includes `pyserial`; use it to reset the board and capture a complete
run after flashing:

```sh
python mod/embedded.mod/benchmarks/gc/capture_esp32.py --port "$ESPPORT" --output benchmark.log
python mod/embedded.mod/benchmarks/gc/capture_esp32.py --port "$ESPPORT" --output varied.log --marker GC_VARIED
python3 mod/embedded.mod/benchmarks/gc/summarize.py benchmark.log varied.log
```

The ESP32 capture script also requires the corresponding `done=1` line.

The original before/after measurements, raw logs, and comparison scripts are
preserved in [`history/`](history/README.md). The legacy marker was removed
after those runs; current builds use the queue directly.

The [queue-only hardware check](results/README.md) records the current build's
serial output and timings.
