#!/usr/bin/env python3
"""Compare two serial logs from the embedded GC benchmark."""

import argparse
import math
import statistics
from pathlib import Path


def read_log(path: Path) -> dict:
    result = {"samples": {}}
    for line in path.read_text(errors="replace").splitlines():
        marker = line.find("GC_BENCH,")
        if marker < 0:
            continue
        fields = {}
        for item in line[marker + len("GC_BENCH,") :].split(","):
            key, separator, value = item.partition("=")
            if separator:
                fields[key] = value.strip()
        if "format" in fields:
            result["metadata"] = fields
        elif fields.get("case") == "mutator":
            result["mutator"] = fields
        elif "sample" in fields:
            result["samples"].setdefault(fields["case"], {})[int(fields["sample"])] = int(fields["us"])
        elif fields.get("done") == "1":
            result["done"] = True
    if not result.get("done") or "metadata" not in result or "mutator" not in result:
        raise ValueError(f"{path}: incomplete GC_BENCH output")
    return result


def ordered_samples(log: dict, case: str) -> list[int]:
    samples = log["samples"].get(case, {})
    if sorted(samples) != list(range(12)):
        raise ValueError(f"{case}: expected samples 0 through 11")
    return [samples[index] for index in range(12)]


def p95(values: list[int]) -> int:
    ordered = sorted(values)
    return ordered[math.ceil(0.95 * len(ordered)) - 1]


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
    for field in ("format", "mode", "arena_capacity"):
        if old[field] != new[field]:
            raise ValueError(f"mismatched {field}: {old[field]} versus {new[field]}")
    if before["mutator"]["checksum"] != after["mutator"]["checksum"]:
        raise ValueError("mutator checksums differ")

    print(f"Mode: {old['mode']}; arena: {old['arena_capacity']} bytes")
    print("| Case | Before median µs | After median µs | Before p95 µs | After p95 µs | Median speedup |")
    print("| --- | ---: | ---: | ---: | ---: | ---: |")
    cases = {
        "mutator": ([int(before["mutator"]["us"])], [int(after["mutator"]["us"])]),
        "live_backward_chain": (
            ordered_samples(before, "live_backward_chain"),
            ordered_samples(after, "live_backward_chain"),
        ),
        "reclaim_garbage": (
            ordered_samples(before, "reclaim_garbage"),
            ordered_samples(after, "reclaim_garbage"),
        ),
    }
    for name, (old_times, new_times) in cases.items():
        old_median, new_median = statistics.median(old_times), statistics.median(new_times)
        speedup = old_median / new_median if new_median else float("inf")
        print(f"| {name} | {format_median(old_median)} | {format_median(new_median)} | {p95(old_times)} | {p95(new_times)} | {speedup:.2f}× |")
    print(f"Arena high water: {old['arena_high_water']} → {new['arena_high_water']} bytes")
    print("The mutator row has one sample; repeat complete runs to estimate its spread.")


if __name__ == "__main__":
    main()
