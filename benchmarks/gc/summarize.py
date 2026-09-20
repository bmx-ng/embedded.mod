#!/usr/bin/env python3
"""Validate and summarize a current embedded GC benchmark serial log."""

import argparse
import math
import statistics
from pathlib import Path


CASES = {
    "ALLOC_SEARCH": ("head", "middle", "tail", "split", "miss", "churn"),
    "GC_BENCH": ("live_backward_chain", "reclaim_garbage"),
    "GC_VARIED": ("empty", "forward_chain", "wide_shared", "mixed_cycle", "reclaim_mixed"),
    "GC_SCALE": ("forward", "zigzag"),
    "GC_SWEEP": ("all_live", "contiguous", "fragmented", "raw_survivors"),
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
    markers = [marker for marker in CASES if any(marker + "," in line for line in lines)]
    if len(markers) != 1:
        raise ValueError(f"{path}: expected exactly one benchmark marker")
    marker = markers[0]
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

    if not done or not metadata or metadata.get("format") != "1" or \
            (marker != "GC_SCALE" and metadata.get("mode") != "single"):
        raise ValueError(f"{path}: incomplete or unexpected benchmark output")
    if set(samples) != set(CASES[marker]):
        raise ValueError(f"{path}: missing or unexpected benchmark case")
    for case in CASES[marker]:
        expected_samples = 8 if marker == "GC_SCALE" else 12
        if sorted(samples[case]) != list(range(expected_samples)):
            raise ValueError(f"{path}: {case} needs samples 0 through {expected_samples - 1}")
    if marker == "GC_BENCH":
        if not mutator or mutator.get("checksum") != "286270096":
            raise ValueError(f"{path}: mutator checksum failed")
    elif marker == "GC_VARIED" and \
            (not checks or metadata.get("checksum") != "3154" or int(metadata.get("auto_collections", 0)) < 1):
        raise ValueError(f"{path}: graph or automatic collection checks failed")

    if marker == "GC_SCALE":
        nodes = int(metadata.get("nodes", 0))
        if not checks or nodes < 32 or int(metadata.get("checksum", 0)) != nodes * (nodes + 1):
            raise ValueError(f"{path}: scale graph checks failed")

    if marker == "GC_SWEEP" and (not checks or int(metadata.get("nodes", 0)) < 1):
        raise ValueError(f"{path}: sweep checks failed")

    if marker == "ALLOC_SEARCH" and (not checks or int(metadata.get("holes", 0)) < 2 or
            metadata.get("batch") != "32" or metadata.get("churn_steps") != "2048"):
        raise ValueError(f"{path}: allocation checks failed")

    arena = metadata.get("arena", metadata.get("arena_capacity"))
    print(f"{path.name}: {marker}, arena {arena} bytes" +
          (f", high water {metadata['arena_high_water']} bytes" if "arena_high_water" in metadata else ""))
    if marker == "GC_SCALE":
        print(f"  live nodes: {metadata['nodes']}")
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
