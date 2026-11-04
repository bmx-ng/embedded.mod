#!/usr/bin/env python3
"""Run precise-root and internal handshake stress under host sanitizers."""

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
    parser.add_argument("--sanitizers", default="address,undefined")
    args = parser.parse_args()

    source = (native / "embedded_runtime.c").read_text()
    alignment = "    max_align_t alignment;"
    if source.count(alignment) != 1:
        raise SystemExit("Update the host alignment adapter for the current heap header")
    source = source.replace(alignment, "    _Alignas(16) max_align_t alignment;")

    with tempfile.TemporaryDirectory(prefix="embedded-gc-roots-") as directory:
        temporary = Path(directory)
        (temporary / "blitzmax").mkdir()
        (temporary / "blitzmax" / "embedded_platform.h").write_text(
            "#include <stdlib.h>\n"
            "#define BMX_EMBEDDED_PLATFORM_CONTEXT_VALID() 1\n"
            "#define BMX_EMBEDDED_PLATFORM_PANIC(message) abort()\n"
            "#define BMX_EMBEDDED_ARENA_STORAGE(name) name\n"
        )
        (temporary / "embedded_runtime_test.c").write_text(source)
        dead_strip = "-Wl,-dead_strip" if sys.platform == "darwin" else "-Wl,--gc-sections"
        common = [
            args.cc, "-O2", "-g", "-fsanitize=" + args.sanitizers, "-std=c11",
            "-DBMX_EMBEDDED_GC_VALIDATE_AFTER_COLLECTION=1",
            "-ffunction-sections", "-fdata-sections", "-I" + str(temporary),
            "-I" + str(native / "include"),
            "-I" + str(tests),
        ]
        executable = temporary / "gc_roots_test"
        subprocess.run(common + [str(tests / "embedded_gc_roots_host.c"),
            dead_strip, "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)

        # The existing device sweep/finalizer regression also runs against the
        # host runtime, including exception escape and resurrection paths.
        wrapper = temporary / "sweep_main.c"
        wrapper.write_text(
            "#include <stdio.h>\n"
            "#define BMX_EMBEDDED_ARENA_SIZE (64u * 1024u)\n"
            "#include \"embedded_runtime_test.c\"\n"
            "#include \"embedded_gc_sweep_conformance.c\"\n"
            "int main(void) { int line = bmx_embedded_gc_sweep_conformance(); "
            "if (line) { printf(\"FAIL: sweep line %d\\n\", line); return 1; } "
            "puts(\"PASS: sweep, finalizer and exception conformance\"); return 0; }\n"
        )
        sweep = temporary / "gc_sweep_test"
        subprocess.run(common + [str(wrapper), dead_strip, "-o", str(sweep)], check=True)
        subprocess.run([str(sweep)], check=True)

        static_field = temporary / "gc_static_field_test"
        subprocess.run(common + [str(tests / "embedded_gc_static_field_host.c"), dead_strip,
            "-o", str(static_field)], check=True)
        subprocess.run([str(static_field)], check=True)

        # Stage 1 internal protocol test. Target adapters and the restricted
        # managed-worker experiment are verified separately on both boards.
        handshake = temporary / "gc_handshake_test"
        subprocess.run(common + ["-pthread", str(native / "embedded_gc_handshake.c"),
            str(tests / "embedded_gc_handshake_host.c"), dead_strip,
            "-o", str(handshake)], check=True)
        subprocess.run([str(handshake)], check=True)

        multicore = temporary / "multicore"
        (multicore / "blitzmax").mkdir(parents=True)
        (multicore / "blitzmax" / "embedded_platform.h").write_text(
            "#include <sched.h>\n#include <stdlib.h>\n#include <stdint.h>\n"
            "extern _Thread_local unsigned bmx_test_context_slot;\n"
            "#define BMX_EMBEDDED_PLATFORM_CONTEXT_VALID() (bmx_test_context_slot < 2u)\n"
            "#define BMX_EMBEDDED_PLATFORM_CONTEXT_INDEX() bmx_test_context_slot\n"
            "#define BMX_EMBEDDED_PLATFORM_GC_WAIT() sched_yield()\n"
            "#define BMX_EMBEDDED_PLATFORM_PANIC(message) abort()\n"
            "#define BMX_EMBEDDED_ARENA_STORAGE(name) name\n"
        )
        (multicore / "embedded_runtime_test.c").write_text(source)
        integrated = temporary / "gc_multicore_runtime_test"
        subprocess.run(common[:1] + ["-I" + str(multicore)] + common[1:] + ["-pthread",
            str(native / "embedded_gc_handshake.c"),
            str(tests / "embedded_gc_multicore_runtime_host.c"), dead_strip,
            "-o", str(integrated)], check=True)
        subprocess.run([str(integrated)], check=True)

        raw_allocator = temporary / "gc_stage2_raw_allocator_test"
        subprocess.run(common[:1] + ["-I" + str(multicore)] + common[1:] + ["-pthread",
            str(native / "embedded_gc_handshake.c"),
            str(tests / "embedded_gc_stage2_raw_allocator_host.c"), dead_strip,
            "-o", str(raw_allocator)], check=True)
        subprocess.run([str(raw_allocator)], check=True)


if __name__ == "__main__":
    main()
