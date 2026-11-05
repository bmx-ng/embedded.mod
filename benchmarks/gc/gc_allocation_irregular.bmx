SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import Embedded.Runtime.Worker
Import "gc_allocation.c"
Import "gc_allocation_irregular.c"

Extern "C"
    Function BenchmarkMulticore:Int() = "bmx_gc_allocation_multicore"
    Function PrepareBenchmark:Int() = "bmx_gc_allocation_prepare"
    Function Instrumented:Int() = "bmx_gc_allocation_instrumented"
    Function Timed:Int() = "bmx_gc_allocation_timed"
    Function StatsReset() = "bmx_gc_allocation_stats_reset"
    Function LockEntries:UInt() = "bmx_gc_allocation_lock_entries"
    Function LockContended:UInt() = "bmx_gc_allocation_lock_contended"
    Function LockSpins:UInt() = "bmx_gc_allocation_lock_spins"
    Function LockWaitUs:ULong() = "bmx_gc_allocation_lock_wait_us"
    Function SetRequest(batch:UInt) = "bmx_gc_allocation_request"
    Function Request:UInt() = "bmx_gc_allocation_requested"
    Function SetCompleted(batch:UInt) = "bmx_gc_allocation_complete"
    Function Completed:UInt() = "bmx_gc_allocation_completed"
    Function AddWorkerTime(us:ULong) = "bmx_gc_allocation_add_worker_time"
    Function WorkerTime:ULong() = "bmx_gc_allocation_worker_time"
    Function YieldTask() = "bmx_gc_allocation_yield"
    Function AllocateIrregular:UInt(seed:UInt, count:UInt) = "bmx_gc_allocation_irregular_batch"
    Function AddWorkerChecksum(checksum:UInt) = "bmx_gc_allocation_irregular_add_worker_checksum"
    Function WorkerChecksum:UInt() = "bmx_gc_allocation_irregular_worker_checksum"
    Function ObjectSize:UInt(kind:UInt) = "bmx_gc_allocation_irregular_size"
End Extern

Const BatchesPerCase:Int = 256
Const Cases:Int = 3

Function OwnerCount:UInt(caseId:Int)
    If caseId = 2 Then Return 16
    Return 64
End Function

Function WorkerCount:UInt(caseId:Int)
    If caseId = 1 Then Return 16
    Return 64
End Function

Function IrregularWorker() { nomangle }
    For Local batch:UInt = 1 To UInt(BatchesPerCase * Cases)
        While Request() < batch
            YieldTask()
        Wend
        Local caseId:Int = Int((batch - 1) / UInt(BatchesPerCase))
        Local started:ULong = MonotonicMicroseconds()
        Local checksum:UInt = AllocateIrregular(batch + 1000000, WorkerCount(caseId))
        AddWorkerTime(MonotonicMicroseconds() - started)
        If checksum = 0 Then RuntimeError "Irregular worker checksum failed"
        AddWorkerChecksum(checksum)
        SetCompleted(batch)
    Next
End Function

SleepMicroseconds(3000000)
If Not BenchmarkMulticore() Or Not PrepareBenchmark() Then ..
    RuntimeError "Irregular allocation benchmark requires multicore GC"
CollectObjects()
Local baselineFailures:UInt = ArenaFailureCount()
Local baselineCollections:UInt = AutomaticCollectionCount()
Local baselineCollectionCount:UInt = CollectionCount()
Local baselineObjects:UInt = ObjectAllocationCount()
Local ownerChecksum:UInt
Local expectedObjects:UInt
Local results:String[] = New String[Cases]

If Not StartManagedWorker(IrregularWorker) Then RuntimeError "Worker start failed"
For Local caseId:Int = 0 Until Cases
    StatsReset()
    Local priorWorkerUs:ULong = WorkerTime()
    Local ownerUs:ULong
    Local wallUs:ULong
    Local collectionUs:ULong
    Local ownerCount:UInt = OwnerCount(caseId)
    Local workerCount:UInt = WorkerCount(caseId)
    expectedObjects :+ UInt(BatchesPerCase) * (ownerCount + workerCount)
    For Local offset:Int = 1 To BatchesPerCase
        Local batch:UInt = UInt(caseId * BatchesPerCase + offset)
        Local batchStarted:ULong = MonotonicMicroseconds()
        SetRequest(batch)
        Local started:ULong = MonotonicMicroseconds()
        Local checksum:UInt = AllocateIrregular(batch, ownerCount)
        ownerUs :+ MonotonicMicroseconds() - started
        If checksum = 0 Then RuntimeError "Irregular owner checksum failed"
        ownerChecksum :+ checksum
        While Completed() < batch
            YieldTask()
        Wend
        wallUs :+ MonotonicMicroseconds() - batchStarted
        started = MonotonicMicroseconds()
        CollectObjects()
        collectionUs :+ MonotonicMicroseconds() - started
    Next
    Local lockEntries:UInt = LockEntries()
    Local lockContended:UInt = LockContended()
    Local lockSpins:UInt = LockSpins()
    Local lockWaitUs:ULong = LockWaitUs()
    Local highWater:UInt = ArenaHighWater()
    If Not HeapIntegrityValid() Or InvalidReferenceCount() <> 0 Then ..
        RuntimeError "Irregular allocation heap check failed"
    results[caseId] = "GC_IRREG,format=1,case=" + caseId + ..
        ",owner_count=" + ownerCount + ",worker_count=" + workerCount + ..
        ",batches=" + BatchesPerCase + ",owner_us=" + ownerUs + ..
        ",worker_us=" + (WorkerTime() - priorWorkerUs) + ..
        ",wall_us=" + wallUs + ",collection_us=" + collectionUs + ..
        ",instrumented=" + Instrumented() + ",timed=" + Timed() + ..
        ",lock_entries=" + lockEntries + ",lock_contended=" + lockContended + ..
        ",lock_spins=" + lockSpins + ",lock_wait_us=" + lockWaitUs + ..
        ",high_water=" + highWater
Next
If JoinManagedWorker() <> 1 Then RuntimeError "Worker join failed"
If ArenaFailureCount() <> baselineFailures Or ..
    AutomaticCollectionCount() <> baselineCollections Or ..
    CollectionCount() <> baselineCollectionCount + UInt(BatchesPerCase * Cases) Or ..
    ObjectAllocationCount() <> baselineObjects + expectedObjects Or ..
    ownerChecksum = 0 Or WorkerChecksum() = 0 Or ..
    Not HeapIntegrityValid() Or InvalidReferenceCount() <> 0 Then ..
    RuntimeError "Irregular allocation final check failed"
Local summary:String = "GC_IRREG,sizes=" + ObjectSize(0) + "/" + ObjectSize(1) + "/" + ..
    ObjectSize(2) + "/" + ObjectSize(3) + ",objects=" + expectedObjects + ..
    ",owner_checksum=" + ownerChecksum + ",worker_checksum=" + WorkerChecksum()
While True
    For Local caseId:Int = 0 Until Cases
        Print results[caseId]
    Next
    Print summary
    Print "GC_IRREG,done=1"
    SleepMicroseconds(1000000)
Wend
