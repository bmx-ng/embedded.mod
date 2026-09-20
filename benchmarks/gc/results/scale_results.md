# Collector scaling on larger SRAM heaps — 2026-09-20

`gc_scale.bmx` keeps a chain of managed nodes live during collection. The
node count grows with the configured heap: 512 nodes at 64 KiB and 2,048 at
256 KiB. It measures both nearby forward links and links that alternate
between the two ends of the allocation order. Each number is the median of
eight release-build collections on the same board and heap size.

| Board | Heap | Links | Previous lookup | Two cursors | Speedup |
| --- | ---: | --- | ---: | ---: | ---: |
| Pico 2 W | 64 KiB | Forward | 11.357 ms | 0.955 ms | 11.9× |
| Pico 2 W | 64 KiB | Zigzag | 11.392 ms | 0.951 ms | 12.0× |
| Pico 2 W | 256 KiB | Forward | 171.224 ms | 3.768 ms | 45.4× |
| Pico 2 W | 256 KiB | Zigzag | 171.361 ms | 3.747 ms | 45.7× |
| ESP32-S3 N16R8 | 256 KiB | Forward | 148.651 ms | 4.365 ms | 34.1× |
| ESP32-S3 N16R8 | 256 KiB | Zigzag | 148.780 ms | 4.365 ms | 34.1× |

The previous lookup is the queue collector from `origin/master` at `f5738e7`.
Both versions use a 256 KiB **internal SRAM** heap on the ESP32-S3; these
results do not measure PSRAM. Every run passed its graph checksum and heap
integrity checks. `summarize.py` validates the raw captures:

- Pico 64 KiB: [before](scale_pico2w_64k_before.log),
  [two cursors](scale_pico2w_64k_two_cursor.log)
- Pico 256 KiB: [before](scale_pico2w_256k_before.log),
  [two cursors](scale_pico2w_256k_two_cursor.log)
- ESP32-S3 256 KiB: [before](scale_s3_256k_before.log),
  [two cursors](scale_s3_256k_two_cursor.log)

The two-cursor lookup adds two pointers to the collection's stack context and
no heap metadata. These graphs have favorable spatial locality at one or both
ends. Arbitrary references can still make lookup traverse much of the heap;
the speedup is workload dependent. Managed work runs only on core 0.

The existing varied benchmark also passed with this lookup on
[Pico 2 W](two_cursor_pico2w_varied.log) and
[ESP32-S3](two_cursor_s3_varied.log), including 15 automatic collections on
each board.
