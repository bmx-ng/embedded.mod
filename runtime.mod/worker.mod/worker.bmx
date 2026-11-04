' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: One managed worker for opt-in embedded multicore builds.
about: StartManagedWorker runs a no-argument global function on the second
core/task. JoinManagedWorker returns 1 after normal completion, -1 after an
uncaught worker exception, or 0 while it is still running. Only the owner
task may start or join. Shared managed values require an explicit atomic
handoff and precise roots; ordinary shared field writes are not synchronized.
Worker sleeps and scalar UART waits can overlap owner collection. On Pico and
ESP32, blocking UART, I2C and SPI transfers can also overlap collection when
every buffer is outside the managed arena or allocated with MemAlloc. Keep each
buffer alive until the call returns. An array-backed pointer keeps the worker
running, so collection waits for that transfer to finish; keep the array
referenced throughout the call. Stdio and filesystem transfers still need
their own native-blocking audit.
End Rem
Module Embedded.Runtime.Worker
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Extern "C"
    Function StartManagedWorker:Int(entry()) = "bmx_embedded_gc_worker_start_function"
    Function JoinManagedWorker:Int(waitBudget:UInt = 100000) = "bmx_embedded_gc_worker_join"
End Extern
?
