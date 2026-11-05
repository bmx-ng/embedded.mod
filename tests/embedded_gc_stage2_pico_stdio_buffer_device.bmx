SuperStrict
Framework BRL.StandardIO
Import Embedded.Runtime.Worker
Import Embedded.System.Time
Import "embedded_gc_stage2_managed_api_device.c"

Extern "C"
    Function MarkReady(job:UInt) = "bmx_stage2_api_ready"
    Function WaitReady:Int(job:UInt) = "bmx_stage2_api_wait_ready"
    Function MarkFailed() = "bmx_stage2_api_failed"
    Function Failure:UInt() = "bmx_stage2_api_failure"
    Function SetBuffer(buffer:Byte Ptr) = "bmx_stage2_api_set_buffer"
    Function GetBuffer:Byte Ptr() = "bmx_stage2_api_get_buffer"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function CollectionCount:UInt() = "bmx_embedded_collection_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
    Function RecordRead(count:Int, value:Int) = "bmx_stage2_api_record_read"
    Function ReadCount:Int() = "bmx_stage2_api_read_count"
    Function ReadByte:Int() = "bmx_stage2_api_read_byte"
    Function StdioRead:Long(buffer:Byte Ptr, count:Long) = "bmx_pico_stdio_read"
End Extern

Function ReadJob() { nomangle }
    Local buffer:Byte Ptr = GetBuffer()
    MarkReady(1)
    For Local attempt:Int = 1 To 16
        Local count:Long = StdioRead(buffer, 1)
        RecordRead(Int(count), Int(buffer[0]))
        If count <> 1 Then
            MarkFailed()
            Return
        End If
        If buffer[0] = 120 Then Return
    Next
    MarkFailed()
End Function

SleepMicroseconds(3000000)
Local failedStep:Int
Local buffer:Byte Ptr = MemAlloc(1)
Local workerStarted:Int
Local joined:Int
If Not buffer Then failedStep = 1
If Not failedStep Then
    SetBuffer(buffer)
    workerStarted = StartManagedWorker(ReadJob)
    If Not workerStarted Then failedStep = 2
End If
If Not failedStep And Not WaitReady(1) Then failedStep = 3
If Not failedStep Then
    SleepMicroseconds(20000)
    Local before:UInt = CollectionCount()
    Local started:ULong = MonotonicMicroseconds()
    CollectObjects()
    If CollectionCount() <> before + 1 Or Not HeapValid() Then failedStep = 4
    If MonotonicMicroseconds() - started >= 300000 Then failedStep = 5
End If
Print "GC_STAGE2_STDIO_READY,send=x"
If workerStarted Then
    Local joinStarted:ULong = MonotonicMicroseconds()
    Repeat
        joined = JoinManagedWorker()
        If joined Then Exit
        If MonotonicMicroseconds() - joinStarted >= 30000000 Then Exit
        SleepMicroseconds(1000)
    Forever
    If Not failedStep And joined <> 1 Then failedStep = 6
End If
If Not failedStep And Failure() Then failedStep = 7
If Not workerStarted Or joined Then
    SetBuffer(Null)
    If buffer Then MemFree(buffer)
End If
While True
    If failedStep Then
        Print "GC_STAGE2_STDIO_BUFFER,failed_step=" + failedStep + ",read_count=" + ReadCount() + ",read_byte=" + ReadByte()
    Else
        Print "GC_STAGE2_STDIO_BUFFER,raw=pass,collection=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
