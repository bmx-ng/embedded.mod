SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_managed_worker_device.c"

Type TManagedWorkerNode
    Field value:Int
End Type

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
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
End Extern

Function ManagedWorkerHold:Int(node:TManagedWorkerNode) { nomangle }
    If node.value <> 123 Then Return 1
    ManagedWorkerReady()
    While ManagedWorkerMode() = 0
        ManagedWorkerYield()
    Wend
    node = Null
    ManagedWorkerReleased()
    While ManagedWorkerMode() = 1
        ManagedWorkerYield()
    Wend
    Return 0
End Function

SleepMicroseconds(3000000)
Local failedStep:Int
CollectObjects()
Local baseline:UInt = LiveObjects()
Local node:TManagedWorkerNode = New TManagedWorkerNode
node.value = 123
If Not StartManagedWorker(node) Then failedStep = 1
If Not failedStep And Not ManagedWorkerWait(1) Then failedStep = 2
node = Null
If Not failedStep Then
    Local garbage:TManagedWorkerNode = New TManagedWorkerNode
    garbage = Null
    If Not CollectObjects() Or LiveObjects() <> baseline + 1 Or Not HeapValid() Then failedStep = 3
End If
If Not failedStep Then
    ManagedWorkerSetMode(1)
    If Not ManagedWorkerWait(2) Then failedStep = 4
End If
If Not failedStep Then
    CollectObjects()
    If LiveObjects() <> baseline Or Not HeapValid() Then failedStep = 5
End If
If Not failedStep Then
    ManagedWorkerSetMode(2)
    If Not ManagedWorkerWait(3) Then failedStep = 6
End If
While True
    If failedStep Then
        Print "GC_MANAGED_WORKER,failed_step=" + failedStep
    Else
        Print "GC_MANAGED_WORKER,format=1,roots=pass,poll=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
