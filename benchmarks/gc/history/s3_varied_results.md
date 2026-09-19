# ESP32-S3 44-pin N16R8 varied GC test — 2026-09-19

Both release images used a 64 KiB internal-SRAM managed arena on the same
ESP32-S3 board. Each timed case has 12 samples. The benchmark also checked
graph contents, reclamation after dropping roots, heap integrity, and survival
of a live graph through 15 automatic collections. Both variants passed with
checksum 3154.

| Collection case | Legacy median | Queue median | Speedup |
| --- | ---: | ---: | ---: |
| Almost empty heap | 27 µs | 25 µs | 1.08× |
| Forward-linked 64-node chain | 394 µs | 372 µs | 1.06× |
| Wide graph with shared references, Strings and Arrays | 763 µs | 664 µs | 1.15× |
| 20-node cycle with Strings and Array link | 228.5 µs | 205 µs | 1.11× |
| Reclaim mixed short-lived objects | 290 µs | 204 µs | 1.42× |

Both variants reached the same arena high water: 65,520 of 65,536 bytes.
The queue ELF uses 28 fewer bytes of text, with the same data and BSS. The
automatic collection count was 15 in both runs.

Raw serial logs: [legacy](s3_varied_legacy.txt),
[queue](s3_varied_queue.txt). Compare them with `compare_varied.py`.

This benchmark runs managed code only on CPU0. It does not measure a
multicore GC handshake or guarantee the same speedup in a larger application.
