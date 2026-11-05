# Writing multicore embedded apps in BlitzMax

An embedded BlitzMax app normally runs its managed code on one core. On a
dual-core Pico or ESP32, `-gc-multicore` lets it start one additional managed
worker. The application task remains the **owner** on core 0; the worker runs
on core 1. Both can allocate BlitzMax Objects, Arrays and Strings.

This is useful when the owner needs to keep servicing a user interface or web
server while another calculation runs. It does not turn every library call into
a thread-safe operation: decide which task owns each device, socket and object.

## Build and run

Import `Embedded.Runtime.Worker` and build with `-gc-multicore`. For example,
from the BlitzMax SDK directory, this builds the first example for an ESP32-S3:

```sh
./bin/bmk makeapp -a -r -l esp32 -board esp32s3_n16r8 -heap 128k \
  -gc-multicore -o /tmp/two_cores \
  mod/embedded.mod/examples/multicore/01_start_and_join.bmx
```

For a Pico 2 W, use `-l pico -g arm -board pico2_w` instead. Choose the board
profile and heap size for your device. Upload the resulting firmware using your
normal target workflow. Without `-gc-multicore`, the ordinary single-core
collector remains the default.

`StartManagedWorker()` takes a no-argument global function and returns nonzero
when it starts. Only one managed worker can run at a time. The owner calls
`JoinManagedWorker()` to reclaim the worker and allow another job to start:

| Join result | Meaning |
| --- | --- |
| `1` | Worker finished normally. |
| `0` | Worker is still running, or there is no worker to join. |
| `-1` | An uncaught worker exception ended the job. |

`JoinManagedWorker(0)` checks without waiting. The default call waits for a
bounded period and can still return `0`.

## 1. Start a worker and keep the owner running

This program starts a managed worker, then prints from the owner while the
worker is active. The worker uses a String and sleeps. The owner does not
need to manage a task handle or call the collector itself.

```blitzmax
SuperStrict
Framework BRL.StandardIO
Import Embedded.Runtime.Worker
Import Embedded.System.Time

Function BackgroundJob()
    Local message:String = "Hello from the worker"
    If message.Length = 0 Then Throw "worker failed"
    SleepMilliseconds(500)
End Function

If Not StartManagedWorker(BackgroundJob) Then RuntimeError "Could not start worker"

For Local tick:Int = 1 To 5
    Print "Owner is still running: " + tick
    SleepMilliseconds(100)
Next

Local result:Int
Repeat
    result = JoinManagedWorker()
Until result <> 0
If result <> 1 Then RuntimeError "Worker failed"
Print "Both tasks finished"
```

The complete source is [01_start_and_join.bmx](../examples/multicore/01_start_and_join.bmx).
Use a function that eventually returns for this pattern. The owner can then
start another job after a successful join.

## 2. Return a result after joining

A simple way to pass a result back is to let the worker write it, **join**, and
only then read it on the owner. Neither task reads and writes the value at the
same time. The completed join supplies the synchronization for this one-shot
handoff.

```blitzmax
Global workerResult:Int

Function Calculate()
    Local total:Int
    For Local number:Int = 1 To 1000
        total :+ number
    Next
    workerResult = total
End Function

If Not StartManagedWorker(Calculate) Then RuntimeError "Could not start worker"

' The owner can do other work here, but must not read workerResult yet.
Local result:Int
Repeat
    result = JoinManagedWorker()
Until result <> 0
If result <> 1 Then RuntimeError "Worker failed"
Print "Result: " + workerResult
```

This excerpt needs the `Framework` and `Import` lines from the first example.
The complete [02_result_after_join.bmx](../examples/multicore/02_result_after_join.bmx)
also does a calculation on the owner while the worker runs. Do not use a plain
global variable for live progress reports while both tasks can access it;
those need an atomic or locked handoff.

## 3. Keep a web server responsive during a calculation

The [HTTP server](../network.mod/httpserver.mod/README.md) is serviced by the
owner task. Initialize Wi-Fi, create the server, register routes, and call
`server.Service()` on core 0. Run an independent calculation on the worker.
The owner polls for completion without holding up the server:

```blitzmax
If Not server.Start() Then RuntimeError server.LastError()
If Not StartManagedWorker(Calculate) Then RuntimeError "Could not start worker"

While True
    PollEvent()
    Local result:Int = JoinManagedWorker(0)
    If result = 1 Then
        publishedResult = workerResult ' Safe to read after join.
    ElseIf result = -1 Then
        RuntimeError "Worker failed"
    End If
    server.Service(4)
    Delay(1)
Wend
```

The complete ESP32 [03_webserver_and_worker.bmx](../examples/multicore/03_webserver_and_worker.bmx)
adds a `/status` JSON route. It first returns a result of `0`, then the worker's
calculated result after join. Set the Wi-Fi name and password in a private copy
of the file before flashing; keep credentials out of source control. The
example has no storage partition or GPIO requirement.

Keep the server and its handlers on the owner task. `Embedded.Network.HTTPServer`
is a single-managed-context server; the whole server has not been validated on
the worker. The owner must still call `Service()` regularly. A slow handler or
filesystem operation on the owner can delay responses even while the worker is
busy elsewhere.

## Rules to keep in mind

- **Give each piece of mutable state an owner.** The GC keeps objects alive;
  it does not make simultaneous reads and writes to ordinary fields or globals
  safe. Use the join pattern for completed results. For live messages, use a
  separately synchronized handoff with precise managed roots.
- **Keep managed calls within the two registered contexts.** Other ESP32
  FreeRTOS tasks and native callbacks must not enter managed BlitzMax code
  directly. Use the established deferred-event path to bring callbacks to
  the owner.
- **Review blocking calls on the worker.** Sleeps and selected UART, I/O and
  ESP32 socket operations have been checked for worker use. This does not
  cover every SDK or library call. A `Byte Ptr` buffer passed to native code
  must stay allocated until that call returns; if it points into a managed
  Array, keep the Array referenced for the whole call.
- **Expect brief shared pauses.** The collector stops both managed tasks
  together. A worker that takes too long to reach a safe point can delay a
  collection. Keep request handlers short and measure pauses in the application
  that matters to you.

The [worker API](../runtime.mod/worker.mod/worker.bmx) documents the supported
calls. The [native-boundary audit](../benchmarks/gc/results/multicore_native_boundary_audit.md)
lists which blocking operations have been checked on the worker. The
[collector design](../MULTICORE_GC_DESIGN.md) explains the stop-the-world
tradeoff and measured limits.
