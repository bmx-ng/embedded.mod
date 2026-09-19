# Pico 2 W varied GC test — 2026-09-19

Both release images used a 64 KiB SRAM managed arena on the same Pico 2 W.
Each timed case has 12 samples. The benchmark also checked graph contents,
reclamation after dropping roots, heap integrity, and survival of a live graph
through 15 automatic collections. Both variants passed with checksum 3154.

| Collection case | Legacy median | Queue median | Speedup |
| --- | ---: | ---: | ---: |
| Almost empty heap | 17 µs | 15 µs | 1.13× |
| Forward-linked 64-node chain | 358 µs | 341 µs | 1.05× |
| Wide graph with shared references, Strings and Arrays | 650 µs | 581 µs | 1.12× |
| 20-node cycle with Strings and Array link | 194 µs | 176.5 µs | 1.10× |
| Reclaim mixed short-lived objects | 208 µs | 154 µs | 1.35× |

Both variants reached the same arena high water: 65,520 of 65,536 bytes.
The queue image adds 152 bytes of firmware text and no BSS. The automatic
collection count was 15 in both runs.

Raw serial logs: [legacy](pico2w_varied_legacy.txt),
[queue](pico2w_varied_queue.txt). Compare them with `compare_varied.py`.

This benchmark runs managed code only on core 0. It does not measure a
multicore GC handshake or guarantee the same speedup in a larger application.
