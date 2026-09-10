# BlitzMax embedded runtime

This module family owns the compact runtime ABI shared by constrained embedded
targets. It contains managed allocation, precise roots, garbage collection,
finalization, core type layouts, strings, arrays, objects, enums, and exception
frames. Target repositories provide the small platform contract used for
execution-context checks, panic handling, and managed-arena placement.

Platform hardware APIs, SDK startup, board selection, peripheral drivers,
standard I/O transports, and interrupt hand-off remain target-owned.
