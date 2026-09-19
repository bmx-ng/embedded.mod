#!/usr/bin/env python3
"""Validate and summarize a current embedded GC benchmark serial log."""

import argparse
import math
import statistics
from pathlib import Path


CASES = {
    "GC_BENCH": ("live_backward_chain", "reclaim_garbage"),
    "GC_VARIED": ("empty", "forward_chain", "wide_shared", "mixed_cycle", "reclaim_mixed"),
}


def fields_from(line: str, marker: str) -> dict[str, str]:
    fields = {}
    for item in line.split(marker + ",", 1)[1].split(","):
        key, separator, value = item.partition("=")
        if separator:
            fields[key] = value.strip()
    return fields


def summarize(path: Path) -> None:
    lines = path.read_text(errors="replace").splitlines()
    marker = "GC_VARIED" if any("GC_VARIED," in line for line in lines) else "GC_BENCH"
    metadata = None
    samples = {}
    mutator = None
    checks = False
    done = False
    for line in lines:
        if marker + "," not in line:
            continue
        fields = fields_from(line, marker)
        if "format" in fields:
            metadata = fields
        elif "sample" in fields:
            samples.setdefault(fields["case"], {})[int(fields["sample"])] = int(fields["us"])
        elif fields.get("case") == "mutator":
            mutator = fields
        elif fields.get("checks") == "pass":
            checks = True
        elif fields.get("done") == "1":
            done = True

    if not done or not metadata or metadata.get("format") != "1" or metadata.get("mode") != "single":
        raise ValueError(f"{path}: incomplete or unexpected benchmark output")
    if set(samples) != set(CASES[marker]):
        raise ValueError(f"{path}: missing or unexpected benchmark case")
    for case in CASES[marker]:
        if sorted(samples[case]) != list(range(12)):
            raise ValueError(f"{path}: {case} needs samples 0 through 11")
    if marker == "GC_BENCH":
        if not mutator or mutator.get("checksum") != "286270096":
            raise ValueError(f"{path}: mutator checksum failed")
    elif not checks or metadata.get("checksum") != "3154" or int(metadata.get("auto_collections", 0)) < 1:
        raise ValueError(f"{path}: graph or automatic collection checks failed")

    print(f"{path.name}: {marker}, arena {metadata['arena_capacity']} bytes, "
          f"high water {metadata['arena_high_water']} bytes")
    if mutator:
        print(f"  ordinary updates: {int(mutator['us']):,} µs")
    if marker == "GC_VARIED":
        print(f"  automatic collections: {metadata['auto_collections']}")
    for case in CASES[marker]:
        values = list(samples[case].values())
        median = f"{statistics.median(values):,.1f}".rstrip("0").rstrip(".")
        p95 = sorted(values)[math.ceil(0.95 * len(values)) - 1]
        print(f"  {case}: median {median} µs, p95 {p95} µs")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()
    for path in args.logs:
        summarize(path)


if __name__ == "__main__":
    main()
