SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import Embedded.Runtime.Worker
Import "gc_benchmark.c"
Import "gc_sweep.c"
Import "gc_pause.c"

Extern "C"
    Function BenchmarkMulticore:Int() = "bmx_embedded_benchmark_multicore"
    Function PrepareBenchmark:Int() = "bmx_gc_pause_prepare"
    Function PrepareSweep:Int(kind:Int, count:Int) = "bmx_sweep_prepare"
    Function CheckSweep:Int(kind:Int, count:Int) = "bmx_sweep_check"
    Function MarkWorkerReady() = "bmx_gc_pause_worker_ready"
    Function WorkerReady:UInt() = "bmx_gc_pause_ready"
    Function WorkerRun:UInt() = "bmx_gc_pause_run"
    Function StopWorker() = "bmx_gc_pause_stop"
    Function YieldTask() = "bmx_gc_pause_yield"
    Function PhaseTimingEnabled:Int() = "bmx_gc_pause_phase_timing_enabled"
    Function StopTime:UInt() = "bmx_gc_pause_stop_us"
    Function MarkTime:UInt() = "bmx_gc_pause_mark_us"
    Function SweepTime:UInt() = "bmx_gc_pause_sweep_us"
End Extern

Const Samples:Int = 12
Const Cases:Int = 5

Type TPauseNode
    Field next:TPauseNode
    Field value:Int
End Type

Function BuildChain:TPauseNode(count:Int)
    Local head:TPauseNode = New TPauseNode
    Local cursor:TPauseNode = head
    For Local index:Int = 0 Until count
        cursor.value = index + 1
        If index < count - 1 Then
            cursor.next = New TPauseNode
            cursor = cursor.next
        End If
    Next
    Return head
End Function

Function BuildZigzag:TPauseNode(count:Int)
    Local nodes:TPauseNode[] = New TPauseNode[count]
    For Local index:Int = 0 Until count
        nodes[index] = New TPauseNode
        nodes[index].value = index + 1
    Next
    Local head:TPauseNode
    Local cursor:TPauseNode
    For Local position:Int = 0 Until count
        Local index:Int
        If position Mod 2 = 0 Then
            index = position / 2
        Else
            index = count - 1 - position / 2
        End If
        If cursor Then
            cursor.next = nodes[index]
        Else
            head = nodes[index]
        End If
        cursor = nodes[index]
    Next
    Return head
End Function

Function CheckChain(head:TPauseNode, count:Int)
    Local cursor:TPauseNode = head
    Local sum:Long
    For Local index:Int = 0 Until count
        If Not cursor Then RuntimeError "Pause benchmark chain is short"
        sum :+ cursor.value
        cursor = cursor.next
    Next
    If cursor Or sum <> Long(count) * (count + 1) / 2 Then ..
        RuntimeError "Pause benchmark chain check failed"
End Function

Function PollWorker() { nomangle }
    MarkWorkerReady()
    While WorkerRun()
        YieldTask()
    Wend
End Function

Function MeasureLive(times:ULong[], stopTimes:UInt[], markTimes:UInt[], ..
        sweepTimes:UInt[], first:Int)
    For Local sample:Int = 0 Until Samples
        Local started:ULong = MonotonicMicroseconds()
        CollectObjects()
        Local index:Int = first + sample
        times[index] = MonotonicMicroseconds() - started
        stopTimes[index] = StopTime()
        markTimes[index] = MarkTime()
        sweepTimes[index] = SweepTime()
        SleepMicroseconds(5000)
    Next
End Function

SleepMicroseconds(3000000)
If Not BenchmarkMulticore() Or Not PrepareBenchmark() Then ..
    RuntimeError "Pause benchmark requires multicore GC"
Local arena:UInt = ArenaCapacity()
Local liveCount:Int = Int(arena / 64)
Local sweepCount:Int = Int(arena / 128)
If liveCount < 32 Or sweepCount > 2048 Then RuntimeError "Unsupported pause benchmark arena"
Local times:ULong[] = New ULong[Samples * Cases]
Local stopTimes:UInt[] = New UInt[Samples * Cases]
Local markTimes:UInt[] = New UInt[Samples * Cases]
Local sweepTimes:UInt[] = New UInt[Samples * Cases]
Local labels:String[] = ["live_owner", "live_worker", "zigzag_worker", ..
    "garbage_worker", "fragmented_worker"]
CollectObjects()
Local baselineFailures:UInt = ArenaFailureCount()
Local baselineAutomatic:UInt = AutomaticCollectionCount()
Local graph:TPauseNode = BuildChain(liveCount)
CollectObjects()
CheckChain(graph, liveCount)
Local liveHighWater:UInt = ArenaHighWater()
Local collectionBefore:UInt = CollectionCount()

MeasureLive(times, stopTimes, markTimes, sweepTimes, 0)
If CollectionCount() <> collectionBefore + UInt(Samples) Then ..
    RuntimeError "Owner-only pause collections did not run"
If Not StartManagedWorker(PollWorker) Then RuntimeError "Pause worker start failed"
While Not WorkerReady()
    YieldTask()
Wend
MeasureLive(times, stopTimes, markTimes, sweepTimes, Samples)
If CollectionCount() <> collectionBefore + UInt(2 * Samples) Then ..
    RuntimeError "Worker-active pause collections did not run"
CheckChain(graph, liveCount)
graph = Null
CollectObjects()
graph = BuildZigzag(liveCount)
CollectObjects()
CheckChain(graph, liveCount)
Local zigzagHighWater:UInt = ArenaHighWater()
MeasureLive(times, stopTimes, markTimes, sweepTimes, 2 * Samples)
CheckChain(graph, liveCount)
graph = Null
CollectObjects()

For Local kind:Int = 1 To 2
    For Local sample:Int = 0 Until Samples
        If Not PrepareSweep(kind, sweepCount) Then RuntimeError "Pause sweep setup failed"
        Local started:ULong = MonotonicMicroseconds()
        CollectObjects()
        Local index:Int = (kind + 2) * Samples + sample
        times[index] = MonotonicMicroseconds() - started
        stopTimes[index] = StopTime()
        markTimes[index] = MarkTime()
        sweepTimes[index] = SweepTime()
        If Not CheckSweep(kind, sweepCount) Then RuntimeError "Pause sweep check failed"
        SleepMicroseconds(5000)
    Next
Next

StopWorker()
If JoinManagedWorker() <> 1 Then RuntimeError "Pause worker join failed"
If ArenaFailureCount() <> baselineFailures Or ..
    AutomaticCollectionCount() <> baselineAutomatic Or ..
    CollectionCount() <> collectionBefore + UInt(3 * Samples + 3 + 3 * 2 * Samples) Or ..
    Not HeapIntegrityValid() Or InvalidReferenceCount() <> 0 Then ..
    RuntimeError "Pause benchmark heap check failed"
Local highWater:UInt = ArenaHighWater()

While True
    Print "GC_PAUSE,format=1,arena=" + arena + ",live_nodes=" + liveCount + ..
        ",sweep_nodes=" + sweepCount + ",live_high_water=" + liveHighWater + ..
        ",zigzag_high_water=" + zigzagHighWater + ",high_water=" + highWater
    For Local kind:Int = 0 Until Cases
        For Local sample:Int = 0 Until Samples
            Print "GC_PAUSE,case=" + labels[kind] + ",sample=" + sample + ..
                ",us=" + times[kind * Samples + sample]
            If PhaseTimingEnabled() Then
                Local index:Int = kind * Samples + sample
                Print "GC_PAUSE_PHASE,case=" + labels[kind] + ",sample=" + sample + ..
                    ",stop_us=" + stopTimes[index] + ",mark_us=" + markTimes[index] + ..
                    ",sweep_us=" + sweepTimes[index]
            End If
        Next
    Next
    Print "GC_PAUSE,checks=pass"
    Print "GC_PAUSE,done=1"
    SleepMicroseconds(1000000)
Wend
