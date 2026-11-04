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
Worker sleeps and scalar UART waits can overlap owner collection. Blocking
calls that retain a raw buffer pointer, such as UART, I2C, SPI, stdio and
filesystem transfers, are not yet certified for managed workers and can make
an owner collection time out while the call is blocked.
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
