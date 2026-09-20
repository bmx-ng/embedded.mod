#!/usr/bin/env python3
"""Check first-fit selection and unlinking at every position in short free lists."""

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    tests = Path(__file__).resolve().parent
    native = tests.parent / "runtime.mod" / "native"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--runtime", type=Path, default=native / "embedded_runtime.c")
    args = parser.parse_args()
    source = args.runtime.read_text()
    # A 64-bit host can have 8-byte max_align_t with a 40-byte block header.
    # Match the runtime's required 16-byte header alignment in this test copy.
    alignment = "    max_align_t alignment;"
    if source.count(alignment) != 1:
        raise SystemExit("Update the host alignment adapter for the current heap header")
    source = source.replace(alignment, "    _Alignas(16) max_align_t alignment;")
    with tempfile.TemporaryDirectory(prefix="embedded-allocation-") as directory:
        temporary = Path(directory)
        (temporary / "blitzmax").mkdir()
        (temporary / "blitzmax" / "embedded_platform.h").write_text(
            "#include <stdlib.h>\n"
            "#define BMX_EMBEDDED_PLATFORM_CONTEXT_VALID() 1\n"
            "#define BMX_EMBEDDED_PLATFORM_PANIC(message) abort()\n"
            "#define BMX_EMBEDDED_ARENA_STORAGE(name) name\n"
        )
        (temporary / "embedded_runtime_test.c").write_text(source)
        executable = temporary / "allocation_test"
        dead_strip = "-Wl,-dead_strip" if sys.platform == "darwin" else "-Wl,--gc-sections"
        subprocess.run([
            args.cc, "-O2", "-g", "-fsanitize=address,undefined", "-std=c11",
            "-ffunction-sections", "-fdata-sections", "-I" + str(temporary),
            "-I" + str(native / "include"),
            str(tests / "embedded_allocation_search_host.c"), dead_strip,
            "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
