#!/usr/bin/env python3
"""Flash one Pico benchmark image and save its USB serial output."""

import argparse
import os
import select
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("firmware", help="benchmark UF2 image")
    parser.add_argument("output", help="raw serial log destination")
    parser.add_argument("--port", required=True, help="USB serial device")
    parser.add_argument("--picotool", default=os.environ.get("PICOTOOL", "picotool"))
    parser.add_argument("--marker", choices=("GC_BENCH", "GC_VARIED", "GC_SCALE", "GC_SWEEP", "GC_CHECK", "ALLOC_SEARCH"), default="GC_BENCH")
    parser.add_argument("--timeout", type=float, default=45.0)
    args = parser.parse_args()

    subprocess.run(
        [args.picotool, "load", "-f", "-v", "-x", args.firmware], check=True
    )

    deadline = time.monotonic() + args.timeout
    device = None
    pending = bytearray()
    lines = []
    try:
        while time.monotonic() < deadline:
            if device is None:
                try:
                    device = os.open(args.port, os.O_RDONLY | os.O_NONBLOCK)
                except OSError:
                    time.sleep(0.1)
                    continue
            try:
                ready, _, _ = select.select([device], [], [], 0.2)
                if not ready:
                    continue
                chunk = os.read(device, 4096)
                if not chunk:
                    time.sleep(0.1)
                    continue
            except OSError:
                os.close(device)
                device = None
                continue
            pending.extend(chunk)
            while b"\n" in pending:
                raw, _, pending = pending.partition(b"\n")
                line = raw.decode("utf-8", errors="replace").rstrip("\r")
                print(line, flush=True)
                lines.append(line)
                if line == f"{args.marker},done=1":
                    with open(args.output, "w", encoding="utf-8") as output:
                        output.write("\n".join(lines) + "\n")
                    return 0
    finally:
        if device is not None:
            os.close(device)
    print("Timed out before the benchmark completed", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
