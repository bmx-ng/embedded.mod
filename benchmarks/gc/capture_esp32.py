#!/usr/bin/env python3
"""Reset an ESP32-S3 UART board and save one complete GC benchmark run."""

import argparse
import sys
import time

try:
    import serial
except ImportError as exc:
    raise SystemExit("pyserial is required; use the ESP-IDF Tools Python") from exc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--marker", choices=("GC_BENCH", "GC_VARIED"), default="GC_BENCH")
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    lines = []
    started = False
    deadline = time.monotonic() + args.timeout
    try:
        with serial.Serial(args.port, 115200, timeout=0.25) as connection:
            connection.reset_input_buffer()
            # On the 44-pin board, the CH343P bridge controls EN with RTS.
            connection.dtr = False
            connection.rts = True
            time.sleep(0.1)
            connection.rts = False
            while time.monotonic() < deadline:
                line = connection.readline().decode("utf-8", "replace").strip()
                if not line:
                    continue
                print(line, flush=True)
                if line.startswith(f"{args.marker},format=1,"):
                    started = True
                if started:
                    lines.append(line)
                if started and line == f"{args.marker},done=1":
                    with open(args.output, "w", encoding="utf-8") as output:
                        output.write("\n".join(lines) + "\n")
                    return 0
                if "Guru Meditation Error" in line or "RuntimeError" in line:
                    break
    except serial.SerialException as exc:
        print(f"Serial port {args.port}: {exc}", file=sys.stderr)
        return 1
    print("The GC benchmark did not complete", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
