# Queue-only hardware check — 2026-09-19

The integrated collector was built without a marker selection switch and run
on a Pico 2 W with a 64 KiB SRAM managed heap. The varied benchmark passed
its graph and heap checks, reported checksum 3154, and preserved a live graph
through 15 automatic collections. The arena high water was 65,520 bytes.

| Collection case | Median |
| --- | ---: |
| Almost empty heap | 15 µs |
| Forward-linked chain | 340.5 µs |
| Wide shared graph | 580 µs |
| Mixed cycle | 176.5 µs |
| Reclaim mixed garbage | 152 µs |

[Raw serial capture](integrated_pico2w_varied.log). Run `summarize.py` from the
parent directory to validate and summarize it again. The historical A/B
comparison is in [`history/`](../history/README.md).

The benchmark runs managed code only on core 0.
