SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import Embedded.Runtime.Worker
Import "gc_allocation.c"

Extern "C"
    Function BenchmarkMulticore:Int() = "bmx_gc_allocation_multicore"
    Function PrepareBenchmark:Int() = "bmx_gc_allocation_prepare"
    Function Instrumented:Int() = "bmx_gc_allocation_instrumented"
    Function StatsReset() = "bmx_gc_allocation_stats_reset"
    Function LockEntries:UInt() = "bmx_gc_allocation_lock_entries"
    Function LockContended:UInt() = "bmx_gc_allocation_lock_contended"
    Function LockSpins:UInt() = "bmx_gc_allocation_lock_spins"
    Function NativeAllocateBatch:UInt(seed:UInt) = "bmx_gc_allocation_native_batch"
    Function SetRequest(batch:UInt) = "bmx_gc_allocation_request"
    Function Request:UInt() = "bmx_gc_allocation_requested"
    Function SetCompleted(batch:UInt) = "bmx_gc_allocation_complete"
    Function Completed:UInt() = "bmx_gc_allocation_completed"
    Function AddWorkerTime(us:ULong) = "bmx_gc_allocation_add_worker_time"
    Function WorkerTime:ULong() = "bmx_gc_allocation_worker_time"
    Function YieldTask() = "bmx_gc_allocation_yield"
End Extern

Const Batches:Int = 256
Const BatchSize:Int = 64

Type TAllocationNode
    Field value:UInt
End Type

' Only these New operations are inside the measured interval. The caller
' collects after the batch; automatic collection would spoil the sample.
Function AllocateBatch:UInt(seed:UInt)
    Local checksum:UInt
    For Local index:Int = 0 Until BatchSize
        Local node:TAllocationNode = New TAllocationNode
        node.value = seed + UInt(index)
        checksum :+ node.value
        node = Null
    Next
    Return checksum
End Function

' Same 64 Object allocations and checksum, with one generated loop poll per
' eight allocations instead of one poll per allocation in multicore mode.
Function AllocateBatchEight:UInt(seed:UInt)
    Local checksum:UInt
    Local node:TAllocationNode
    For Local group:Int = 0 Until BatchSize / 8
        Local value:UInt = seed + UInt(group * 8)
        node = New TAllocationNode
        node.value = value
        checksum :+ node.value
        node = New TAllocationNode
        node.value = value + 1
        checksum :+ node.value
        node = New TAllocationNode
        node.value = value + 2
        checksum :+ node.value
        node = New TAllocationNode
        node.value = value + 3
        checksum :+ node.value
        node = New TAllocationNode
        node.value = value + 4
        checksum :+ node.value
        node = New TAllocationNode
        node.value = value + 5
        checksum :+ node.value
        node = New TAllocationNode
        node.value = value + 6
        checksum :+ node.value
        node = New TAllocationNode
        node.value = value + 7
        checksum :+ node.value
        node = Null
    Next
    Return checksum
End Function

Function ManagedAllocationWorker() { nomangle }
    For Local batch:UInt = 1 To UInt(Batches)
        While Request() < batch
            YieldTask()
        Wend
        Local started:ULong = MonotonicMicroseconds()
        Local checksum:UInt = AllocateBatch(batch)
        AddWorkerTime(MonotonicMicroseconds() - started)
        If checksum = 0 Then RuntimeError "Allocation checksum failed"
        SetCompleted(batch)
    Next
End Function

SleepMicroseconds(3000000)
If Not PrepareBenchmark() Then RuntimeError "GC owner registration failed"
CollectObjects()
Local baselineFailures:UInt = ArenaFailureCount()
Local baselineCollections:UInt = AutomaticCollectionCount()
Local baselineCollectionCount:UInt = CollectionCount()
Local baselineObjects:UInt = ObjectAllocationCount()
Local checksum:UInt
Local allocationUs:ULong
Local collectionUs:ULong
StatsReset()

' A single allocating task, in both compiler/runtime modes.
For Local batch:Int = 1 To Batches
    Local started:ULong = MonotonicMicroseconds()
    checksum :+ AllocateBatch(UInt(batch))
    allocationUs :+ MonotonicMicroseconds() - started
    started = MonotonicMicroseconds()
    CollectObjects()
    collectionUs :+ MonotonicMicroseconds() - started
Next

Local ownerAllocationUs:ULong = allocationUs
Local ownerCollectionUs:ULong = collectionUs
Local ownerChecksum:UInt = checksum
Local ownerLockEntries:UInt = LockEntries()
Local ownerLockContended:UInt = LockContended()
Local ownerLockSpins:UInt = LockSpins()
allocationUs = 0
collectionUs = 0
Local unrolledChecksum:UInt
StatsReset()
For Local batch:Int = 1 To Batches
    Local started:ULong = MonotonicMicroseconds()
    unrolledChecksum :+ AllocateBatchEight(UInt(batch))
    allocationUs :+ MonotonicMicroseconds() - started
    started = MonotonicMicroseconds()
    CollectObjects()
    collectionUs :+ MonotonicMicroseconds() - started
Next
If unrolledChecksum <> ownerChecksum Then RuntimeError "Unrolled allocation checksum failed"
Local unrolledAllocationUs:ULong = allocationUs
Local unrolledCollectionUs:ULong = collectionUs
Local unrolledLockEntries:UInt = LockEntries()
Local unrolledLockContended:UInt = LockContended()
Local unrolledLockSpins:UInt = LockSpins()
allocationUs = 0
collectionUs = 0
Local nativeChecksum:UInt
StatsReset()
For Local batch:Int = 1 To Batches
    Local started:ULong = MonotonicMicroseconds()
    nativeChecksum :+ NativeAllocateBatch(UInt(batch))
    allocationUs :+ MonotonicMicroseconds() - started
    started = MonotonicMicroseconds()
    CollectObjects()
    collectionUs :+ MonotonicMicroseconds() - started
Next
If nativeChecksum <> ownerChecksum Then RuntimeError "Native allocation checksum failed"
Local nativeAllocationUs:ULong = allocationUs
Local nativeCollectionUs:ULong = collectionUs
Local nativeLockEntries:UInt = LockEntries()
Local nativeLockContended:UInt = LockContended()
Local nativeLockSpins:UInt = LockSpins()
Local parallelOwnerUs:ULong
Local parallelWorkerUs:ULong
Local parallelWallUs:ULong
Local parallelCollectionUs:ULong
Local parallelChecksum:UInt
Local parallelLockEntries:UInt
Local parallelLockContended:UInt
Local parallelLockSpins:UInt

If BenchmarkMulticore() Then
    ' The worker is started once and stays alive for every batch. Each task
    ' allocates the same amount; both are released together for each batch.
    If Not StartManagedWorker(ManagedAllocationWorker) Then RuntimeError "Worker start failed"
    StatsReset()
    allocationUs = 0
    collectionUs = 0
    For Local batch:UInt = 1 To UInt(Batches)
        Local batchStarted:ULong = MonotonicMicroseconds()
        SetRequest(batch)
        Local started:ULong = MonotonicMicroseconds()
        checksum :+ AllocateBatch(batch)
        allocationUs :+ MonotonicMicroseconds() - started
        While Completed() < batch
            YieldTask()
        Wend
        parallelWallUs :+ MonotonicMicroseconds() - batchStarted
        started = MonotonicMicroseconds()
        CollectObjects()
        collectionUs :+ MonotonicMicroseconds() - started
    Next
    If JoinManagedWorker() <> 1 Then RuntimeError "Worker join failed"
    parallelOwnerUs = allocationUs
    parallelWorkerUs = WorkerTime()
    parallelCollectionUs = collectionUs
    parallelChecksum = checksum
    parallelLockEntries = LockEntries()
    parallelLockContended = LockContended()
    parallelLockSpins = LockSpins()
End If

If ArenaFailureCount() <> baselineFailures Or ..
    AutomaticCollectionCount() <> baselineCollections Or ..
    CollectionCount() <> baselineCollectionCount + UInt(Batches * (3 + BenchmarkMulticore())) Or ..
    ObjectAllocationCount() <> baselineObjects + UInt(Batches * BatchSize * (3 + 2 * BenchmarkMulticore())) Or ..
    Not HeapIntegrityValid() Or InvalidReferenceCount() <> 0 Then ..
    RuntimeError "Allocation benchmark heap check failed"
Local benchmarkHighWater:UInt = ArenaHighWater()
Print "GC_ALLOC,done=1"

While True
    Print "GC_ALLOC,format=1,mode=" + BenchmarkMulticore() + ..
        ",arena=" + ArenaCapacity() + ",arena_high_water=" + benchmarkHighWater + ",case=owner" + ..
        ",allocations=" + (Batches * BatchSize) + ..
        ",allocation_us=" + ownerAllocationUs + ..
        ",collection_us=" + ownerCollectionUs + ..
        ",instrumented=" + Instrumented() + ..
        ",lock_entries=" + ownerLockEntries + ..
        ",lock_contended=" + ownerLockContended + ..
        ",lock_spins=" + ownerLockSpins + ..
        ",checksum=" + ownerChecksum
    Print "GC_ALLOC,format=1,mode=" + BenchmarkMulticore() + ..
        ",arena=" + ArenaCapacity() + ",arena_high_water=" + benchmarkHighWater + ..
        ",case=owner_eight,allocations=" + (Batches * BatchSize) + ..
        ",allocation_us=" + unrolledAllocationUs + ..
        ",collection_us=" + unrolledCollectionUs + ..
        ",instrumented=" + Instrumented() + ..
        ",lock_entries=" + unrolledLockEntries + ..
        ",lock_contended=" + unrolledLockContended + ..
        ",lock_spins=" + unrolledLockSpins + ..
        ",checksum=" + unrolledChecksum
    Print "GC_ALLOC,format=1,mode=" + BenchmarkMulticore() + ..
        ",arena=" + ArenaCapacity() + ",arena_high_water=" + benchmarkHighWater + ..
        ",case=owner_native,allocations=" + (Batches * BatchSize) + ..
        ",allocation_us=" + nativeAllocationUs + ..
        ",collection_us=" + nativeCollectionUs + ..
        ",instrumented=" + Instrumented() + ..
        ",lock_entries=" + nativeLockEntries + ..
        ",lock_contended=" + nativeLockContended + ..
        ",lock_spins=" + nativeLockSpins + ..
        ",checksum=" + nativeChecksum
    If BenchmarkMulticore() Then
        Print "GC_ALLOC,format=1,mode=1,arena=" + ArenaCapacity() + ..
            ",arena_high_water=" + benchmarkHighWater + ..
            ",case=parallel,allocations=" + (2 * Batches * BatchSize) + ..
            ",owner_allocation_us=" + parallelOwnerUs + ..
            ",worker_allocation_us=" + parallelWorkerUs + ..
            ",wall_us=" + parallelWallUs + ..
            ",collection_us=" + parallelCollectionUs + ..
            ",instrumented=" + Instrumented() + ..
            ",lock_entries=" + parallelLockEntries + ..
            ",lock_contended=" + parallelLockContended + ..
            ",lock_spins=" + parallelLockSpins + ..
            ",checksum=" + parallelChecksum
    End If
    Print "GC_ALLOC,done=1"
    SleepMicroseconds(1000000)
Wend
