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
    Function RecordRead(count:Int, value:Int) = "bmx_stage2_api_record_read"
    Function ReadCount:Int() = "bmx_stage2_api_read_count"
    Function ReadValue:Int() = "bmx_stage2_api_read_byte"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function CollectionCount:UInt() = "bmx_embedded_collection_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
    Function UARTConfigurePins:Int(controller:Int, txPin:UInt, rxPin:UInt) = "bmx_embedded_uart_configure_pins"
    Function GPIOPullUp:Int(pin:UInt) = "bmx_embedded_gpio_pull_up"
    Function UARTInit:UInt(controller:Int, baudrate:UInt) = "bmx_embedded_uart_init"
    Function UARTReadableWithin:Int(controller:Int, timeoutMicroseconds:UInt) = "bmx_embedded_uart_is_readable_within_us"
    Function UARTDeinit:Int(controller:Int) = "bmx_embedded_uart_deinit"
End Extern

Type TWaitValue
    Field number:Int
End Type

Function WaitJob() { nomangle }
    Local node:TWaitValue = New TWaitValue
    Local values:Int[] = New Int[1]
    node.number = 107
    values[0] = 107
    Local label:String = "uart-" + node.number
    MarkReady(1)
    Local readable:Int = UARTReadableWithin(1, 400000)
    Local rootsValid:Int = node.number = 107 And values[0] = 107 And label = "uart-107"
    RecordRead(readable, rootsValid)
    If readable <> 0 Or Not rootsValid Then MarkFailed()
End Function

SleepMicroseconds(3000000)
Local failedStep:Int
Local workerStarted:Int
Local joined:Int
If Not UARTConfigurePins(1, 4, 5) Then failedStep = 1
If Not failedStep And Not GPIOPullUp(5) Then failedStep = 9
If Not failedStep And Not UARTInit(1, 9600) Then failedStep = 2
If Not failedStep Then
    workerStarted = StartManagedWorker(WaitJob)
    If Not workerStarted Then failedStep = 3
End If
If Not failedStep And Not WaitReady(1) Then failedStep = 4
Print "GC_STAGE2_UART_WAIT,phase=ready,failed_step=" + failedStep
If Not failedStep Then
    SleepMicroseconds(20000)
    Local before:UInt = CollectionCount()
    Local began:ULong = MonotonicMicroseconds()
    CollectObjects()
    If CollectionCount() <> before + 1 Or Not HeapValid() Then failedStep = 5
    If MonotonicMicroseconds() - began >= 300000 Then failedStep = 6
End If
Print "GC_STAGE2_UART_WAIT,phase=collected,failed_step=" + failedStep
If workerStarted Then
    For Local attempt:Int = 1 To 100
        joined = JoinManagedWorker()
        If joined Then Exit
    Next
    If Not failedStep And joined <> 1 Then failedStep = 7
End If
If Not failedStep And Failure() Then failedStep = 8
Print "GC_STAGE2_UART_WAIT,phase=joined,failed_step=" + failedStep + ..
    ",readable=" + ReadCount() + ",roots=" + ReadValue()
If Not workerStarted Or joined Then UARTDeinit(1)
While True
    If failedStep Then
        Print "GC_STAGE2_UART_WAIT,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_UART_WAIT,roots=pass,collection=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
