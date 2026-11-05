SuperStrict
Framework BRL.StandardIO
Import Embedded.Runtime.Worker
Import Embedded.System.Time
Import "embedded_gc_stage2_managed_api_device.c"

Extern "C"
    Function SetJob(job:UInt) = "bmx_stage2_api_set_job"
    Function MarkReady(job:UInt) = "bmx_stage2_api_ready"
    Function WaitReady:Int(job:UInt) = "bmx_stage2_api_wait_ready"
    Function ReleaseJob(job:UInt) = "bmx_stage2_api_release"
    Function ReleasedJob:UInt() = "bmx_stage2_api_released"
    Function MarkFailed() = "bmx_stage2_api_failed"
    Function Failure:UInt() = "bmx_stage2_api_failure"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function CollectionCount:UInt() = "bmx_embedded_collection_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
    Function PendingEvents:UInt() = "bmx_embedded_event_pending"
    Function WaitNative() = "bmx_embedded_system_wait"
    Function WakeNative() = "bmx_embedded_system_wake"
End Extern

Type TWaitValue
    Field number:Int
End Type

Function WaitJob() { nomangle }
    Local node:TWaitValue = New TWaitValue
    Local values:Int[] = New Int[1]
    node.number = 37
    values[0] = 37
    Local label:String = "native-event-" + node.number
    MarkReady(1)
    Repeat
        WaitNative()
    Until ReleasedJob() = 1
    If node.number <> 37 Or values[0] <> 37 Or label <> "native-event-37" Then MarkFailed()
End Function

SleepMicroseconds(3000000)
Print "GC_STAGE2_NATIVE_EVENT_WAIT,phase=boot"
Local failedStep:Int
Local started:Int
Local joined:Int
If PendingEvents() Then failedStep = 1
If Not failedStep Then
    SetJob(1)
    started = StartManagedWorker(WaitJob)
    If Not started Then failedStep = 2
End If
If Not failedStep And Not WaitReady(1) Then failedStep = 3
Print "GC_STAGE2_NATIVE_EVENT_WAIT,phase=ready,failed_step=" + failedStep
If Not failedStep Then
    SleepMicroseconds(20000)
    Local before:UInt = CollectionCount()
    Local began:ULong = MonotonicMicroseconds()
    CollectObjects()
    If CollectionCount() <> before + 1 Or Not HeapValid() Then failedStep = 4
    If MonotonicMicroseconds() - began >= 300000 Then failedStep = 5
End If
Print "GC_STAGE2_NATIVE_EVENT_WAIT,phase=collected,failed_step=" + failedStep
If started Then
    ReleaseJob(1)
    For Local attempt:Int = 1 To 100
        WakeNative()
        joined = JoinManagedWorker()
        If joined Then Exit
    Next
    If Not failedStep And joined <> 1 Then failedStep = 6
End If
Print "GC_STAGE2_NATIVE_EVENT_WAIT,phase=joined,failed_step=" + failedStep
If Not failedStep And Failure() Then failedStep = 7
While True
    If failedStep Then
        Print "GC_STAGE2_NATIVE_EVENT_WAIT,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_NATIVE_EVENT_WAIT,roots=pass,collection=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
