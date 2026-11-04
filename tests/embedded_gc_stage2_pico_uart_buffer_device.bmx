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
    Function UARTConfigurePins:Int(controller:Int, txPin:UInt, rxPin:UInt) = "bmx_embedded_uart_configure_pins"
    Function UARTInit:UInt(controller:Int, baudrate:UInt) = "bmx_embedded_uart_init"
    Function UARTReadTimeout:Int(controller:Int, buffer:Byte Ptr, length:Int, timeoutMicroseconds:UInt) = "bmx_embedded_uart_read_timeout_us"
    Function UARTDeinit:Int(controller:Int) = "bmx_embedded_uart_deinit"
End Extern

Function ReadJob() { nomangle }
    Local buffer:Byte Ptr = GetBuffer()
    MarkReady(1)
    If UARTReadTimeout(1, buffer, 4096, 400000) < 0 Then MarkFailed()
End Function

SleepMicroseconds(3000000)
Local failedStep:Int
Local transferBuffer:Byte Ptr
Local workerStarted:Int
Local joined:Int
If Not UARTConfigurePins(1, 4, 5) Then failedStep = 1
If Not failedStep And Not UARTInit(1, 9600) Then failedStep = 2
If Not failedStep Then
    transferBuffer = MemAlloc(4096)
    If Not transferBuffer Then failedStep = 3
End If
If Not failedStep Then
    SetBuffer(transferBuffer)
    workerStarted = StartManagedWorker(ReadJob)
    If Not workerStarted Then failedStep = 4
End If
If Not failedStep And Not WaitReady(1) Then failedStep = 5
If Not failedStep Then
    SleepMicroseconds(20000)
    Local before:UInt = CollectionCount()
    Local started:ULong = MonotonicMicroseconds()
    CollectObjects()
    If MonotonicMicroseconds() - started >= 300000 Then failedStep = 9
    If CollectionCount() <> before + 1 Or Not HeapValid() Then failedStep = 6
End If
If workerStarted Then
    For Local attempt:Int = 1 To 100
        joined = JoinManagedWorker()
        If joined Then Exit
    Next
    If Not failedStep And joined <> 1 Then failedStep = 7
End If
If Not failedStep And Failure() Then failedStep = 8
If Not workerStarted Or joined Then
    SetBuffer(Null)
    If transferBuffer Then MemFree(transferBuffer)
    UARTDeinit(1)
End If
While True
    If failedStep Then
        Print "GC_STAGE2_PICO_UART_BUFFER,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_PICO_UART_BUFFER,raw=pass,collection=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
