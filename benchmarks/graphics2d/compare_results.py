#!/usr/bin/env python3
"""Compare summary rows from two Graphics2D benchmark captures."""

from __future__ import annotations

import argparse
from pathlib import Path


Key = tuple[str, str, str, str, str, str]


def load(path: Path) -> dict[Key, int]:
    results: dict[Key, int] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line.startswith("G2D_BENCH,"):
            continue
        fields: dict[str, str] = {}
        for item in line.split(",")[1:]:
            if "=" in item:
                name, value = item.split("=", 1)
                fields[name] = value
        if fields.get("kind") != "summary" or "best_us" not in fields:
            continue
        key = (
            fields.get("platform", "unknown"),
            fields.get("width", "unknown"),
            fields.get("height", "unknown"),
            fields.get("phase", "unknown"),
            fields.get("pixel_format", "unknown"),
            fields.get("case", "unknown"),
        )
        results[key] = int(fields["best_us"])
    return results


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    before = load(args.before)
    after = load(args.after)
    common = sorted(before.keys() & after.keys())
    if not common:
        raise SystemExit("no matching Graphics2D summary rows found")

    print("| Platform | Size | Phase | Format | Case | Before us | After us | Speedup | Change |")
    print("|---|---:|---|---|---|---:|---:|---:|---:|")
    for platform, width, height, phase, pixel_format, case_name in common:
        key = (platform, width, height, phase, pixel_format, case_name)
        old = before[key]
        new = after[key]
        speedup = old / new if new else float("inf")
        change = ((new - old) * 100.0 / old) if old else 0.0
        print(
            f"| {platform} | {width}x{height} | {phase} | {pixel_format} | "
            f"{case_name} | {old} | {new} | "
            f"{speedup:.2f}x | {change:+.1f}% |"
        )


if __name__ == "__main__":
    main()
