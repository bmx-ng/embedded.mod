SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_managed_worker_device.c"

Type TManagedWorkerLeaf
    Field value:Int
End Type

Type TManagedWorkerNode
    Field value:Int
    Field StaticArray members:TManagedWorkerLeaf[2]
End Type

Struct SManagedWorkerPayload
    Field StaticArray members:TManagedWorkerLeaf[2]
End Struct

Extern "C"
    Function StartManagedWorker:Int(node:TManagedWorkerNode) = "bmx_gc_managed_worker_start"
    Function ManagedWorkerMode:Int() = "bmx_gc_managed_worker_mode"
    Function ManagedWorkerSetMode(mode:Int) = "bmx_gc_managed_worker_set_mode"
    Function ManagedWorkerReady() = "bmx_gc_managed_worker_ready"
    Function ManagedWorkerReleased() = "bmx_gc_managed_worker_released"
    Function ManagedWorkerWait:Int(state:Int) = "bmx_gc_managed_worker_wait"
    Function ManagedWorkerYield() = "bmx_gc_managed_worker_yield"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function LiveObjects:UInt() = "bmx_embedded_object_live_count"
    Function LiveArrays:UInt() = "bmx_embedded_array_live_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
End Extern

Function ManagedWorkerHold:Int(node:TManagedWorkerNode) { nomangle }
    If node.value <> 123 Then Return 1
    Local total:Int
    Local payload:SManagedWorkerPayload
    payload.members[0] = node.members[0]
    payload.members[1] = node.members[1]
    For Local item:TManagedWorkerLeaf = EachIn payload.members
        node = Null
        total :+ item.value
        If total = 7 Then ManagedWorkerReady()
        While ManagedWorkerMode() = 0
            ManagedWorkerYield()
        Wend
    Next
    If total <> 16 Then Return 2
    payload.members[0] = Null
    payload.members[1] = Null
    ManagedWorkerReleased()
    While ManagedWorkerMode() = 1
        ManagedWorkerYield()
    Wend
    Return 0
End Function

SleepMicroseconds(3000000)
Local failedStep:Int
Local firstCollected:UInt
Local firstLive:UInt
Local firstLiveArrays:UInt
Local firstValid:UInt
CollectObjects()
Local baseline:UInt = LiveObjects()
Local baselineArrays:UInt = LiveArrays()
Local node:TManagedWorkerNode = New TManagedWorkerNode
node.value = 123
Local first:TManagedWorkerLeaf = New TManagedWorkerLeaf
first.value = 7
Local second:TManagedWorkerLeaf = New TManagedWorkerLeaf
second.value = 9
node.members[0] = first
node.members[1] = second
If Not StartManagedWorker(node) Then failedStep = 1
If Not failedStep And Not ManagedWorkerWait(1) Then failedStep = 2
node = Null
first = Null
second = Null
If Not failedStep Then
    Local garbage:TManagedWorkerNode = New TManagedWorkerNode
    garbage = Null
    firstCollected = CollectObjects()
    firstLive = LiveObjects()
    firstLiveArrays = LiveArrays()
    firstValid = HeapValid()
    If firstCollected < 2 Or firstLive <> baseline + 2 Or firstLiveArrays <> baselineArrays Or Not firstValid Then failedStep = 3
End If
If Not failedStep Then
    ManagedWorkerSetMode(1)
    If Not ManagedWorkerWait(2) Then failedStep = 4
End If
If Not failedStep Then
    CollectObjects()
    If LiveObjects() <> baseline Or LiveArrays() <> baselineArrays Or Not HeapValid() Then failedStep = 5
End If
If Not failedStep Then
    ManagedWorkerSetMode(2)
    If Not ManagedWorkerWait(3) Then failedStep = 6
End If
While True
    If failedStep Then
        Print "GC_MANAGED_WORKER,failed_step=" + failedStep
        If failedStep = 3 Then Print "GC_MANAGED_DEBUG,baseline=" + baseline + ",collected=" + firstCollected + ",live=" + firstLive + ",arrays=" + firstLiveArrays + ",valid=" + firstValid
    Else
        Print "GC_MANAGED_WORKER,format=1,roots=pass,poll=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
