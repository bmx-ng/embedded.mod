#!/usr/bin/env python3
"""Compare correctness and timing logs from gc_varied.bmx."""

import argparse
import math
import statistics
from pathlib import Path


CASES = ("empty", "forward_chain", "wide_shared", "mixed_cycle", "reclaim_mixed")


def read_log(path: Path) -> dict:
    result = {"samples": {}}
    for line in path.read_text(errors="replace").splitlines():
        marker = line.find("GC_VARIED,")
        if marker < 0:
            continue
        fields = {}
        for item in line[marker + len("GC_VARIED,") :].split(","):
            key, separator, value = item.partition("=")
            if separator:
                fields[key] = value.strip()
        if "format" in fields:
            result["metadata"] = fields
        elif "sample" in fields:
            result["samples"].setdefault(fields["case"], {})[int(fields["sample"])] = int(fields["us"])
        elif fields.get("checks") == "pass":
            result["checks"] = True
        elif fields.get("done") == "1":
            result["done"] = True
    if not result.get("done") or not result.get("checks") or "metadata" not in result:
        raise ValueError(f"{path}: incomplete or failing GC_VARIED output")
    if set(result["samples"]) != set(CASES):
        raise ValueError(f"{path}: unexpected benchmark cases")
    for case in CASES:
        if sorted(result["samples"][case]) != list(range(12)):
            raise ValueError(f"{path}: {case} needs samples 0 through 11")
    return result


def p95(values: list[int]) -> int:
    return sorted(values)[math.ceil(0.95 * len(values)) - 1]


def format_median(value: float) -> str:
    return f"{value:,.1f}".rstrip("0").rstrip(".")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path, help="serial log with mark_queue=0")
    parser.add_argument("after", type=Path, help="serial log with mark_queue=1")
    args = parser.parse_args()
    before, after = read_log(args.before), read_log(args.after)
    old, new = before["metadata"], after["metadata"]
    if old.get("mark_queue") != "0" or new.get("mark_queue") != "1":
        raise ValueError("expected mark_queue=0 before and mark_queue=1 after")
    for field in ("format", "mode", "arena_capacity", "checksum"):
        if old[field] != new[field]:
            raise ValueError(f"mismatched {field}: {old[field]} versus {new[field]}")
    if old["checksum"] != "3154":
        raise ValueError(f"unexpected graph checksum: {old['checksum']}")
    if int(old["auto_collections"]) < 1 or int(new["auto_collections"]) < 1:
        raise ValueError("automatic collections were not exercised")

    print(f"Mode: {old['mode']}; arena: {old['arena_capacity']} bytes; checksum: {old['checksum']}")
    print("| Case | Before median µs | After median µs | Before p95 µs | After p95 µs | Median speedup |")
    print("| --- | ---: | ---: | ---: | ---: | ---: |")
    for case in CASES:
        old_times = list(before["samples"][case].values())
        new_times = list(after["samples"][case].values())
        old_median, new_median = statistics.median(old_times), statistics.median(new_times)
        speedup = old_median / new_median if new_median else float("inf")
        print(f"| {case} | {format_median(old_median)} | {format_median(new_median)} | "
              f"{p95(old_times)} | {p95(new_times)} | {speedup:.2f}× |")
    print(f"Arena high water: {old['arena_high_water']} → {new['arena_high_water']} bytes")
    print(f"Automatic collections under allocation pressure: {old['auto_collections']} → {new['auto_collections']}")
    print("Both variants passed the heap, graph, reclamation, and checksum checks.")


if __name__ == "__main__":
    main()
