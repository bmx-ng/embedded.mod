SuperStrict
Framework BRL.StandardIO
Import Embedded.Runtime.Worker
Import Embedded.System.Time
Import "embedded_gc_stage2_managed_api_device.c"

Extern "C"
    Function SetJob(job:UInt) = "bmx_stage2_api_set_job"
    Function CurrentJob:UInt() = "bmx_stage2_api_job"
    Function MarkReady(job:UInt) = "bmx_stage2_api_ready"
    Function WaitReady:Int(job:UInt) = "bmx_stage2_api_wait_ready"
    Function ReleaseJob(job:UInt) = "bmx_stage2_api_release"
    Function ReleasedJob:UInt() = "bmx_stage2_api_released"
    Function MarkFailed() = "bmx_stage2_api_failed"
    Function Failure:UInt() = "bmx_stage2_api_failure"
    Function WorkerYield() = "bmx_stage2_api_yield"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function LiveObjects:UInt() = "bmx_embedded_object_live_count"
    Function LiveArrays:UInt() = "bmx_embedded_array_live_count"
    Function LiveStrings:UInt() = "bmx_embedded_string_live_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
End Extern

Type TWorkerValue
    Field value:Int
End Type

Function ManagedJob() { nomangle }
    Local index:UInt = CurrentJob()
    Local node:TWorkerValue = New TWorkerValue
    Local values:Int[] = New Int[1]
    Local text:String = "job-" + index
    node.value = Int(index)
    values[0] = Int(index)
    MarkReady(index)
    While ReleasedJob() <> index
        WorkerYield()
    Wend
    If node.value <> Int(index) Or values[0] <> Int(index) Or text.Length = 0 Then MarkFailed()
    If index = 8 Then Throw "expected worker exception"
    node = Null
    values = Null
    text = Null
End Function

SleepMicroseconds(3000000)
CollectObjects()
Local baselineObjects:UInt = LiveObjects()
Local baselineArrays:UInt = LiveArrays()
Local baselineStrings:UInt = LiveStrings()
Local failedStep:Int
For Local index:UInt = 1 To 100
    SetJob(index)
    If Not StartManagedWorker(ManagedJob) Then failedStep = 1
    If Not failedStep And StartManagedWorker(ManagedJob) Then failedStep = 2
    If Not failedStep And Not WaitReady(index) Then failedStep = 3
    If Not failedStep Then
        CollectObjects()
        If Not HeapValid() Then failedStep = 4
    End If
    ReleaseJob(index)
    Local joined:Int
    For Local attempt:Int = 1 To 100
        joined = JoinManagedWorker()
        If joined Then Exit
    Next
    Local expectedJoin:Int = 1
    If index = 8 Then expectedJoin = -1
    If Not failedStep And joined <> expectedJoin Then failedStep = 5
    If Not failedStep And Failure() Then failedStep = 6
    CollectObjects()
    If Not failedStep And (LiveObjects() <> baselineObjects Or ..
            LiveArrays() <> baselineArrays Or LiveStrings() <> baselineStrings Or ..
            Not HeapValid()) Then failedStep = 7
    If failedStep Then Exit
Next
While True
    If failedStep Then
        Print "GC_STAGE2_MANAGED_API,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_MANAGED_API,format=1,jobs=100,objects=pass,arrays=pass,strings=pass,exception=pass,reclaim=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
