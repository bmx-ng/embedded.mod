SuperStrict
Framework BRL.StandardIO
Import BRL.Socket
Import Embedded.Runtime.Worker
Import Embedded.System.Time
Import "embedded_gc_stage2_managed_api_device.c"
Import "embedded_gc_stage2_esp32_udp_sendto_device.c"

Extern "C"
    Function SetJob(job:UInt) = "bmx_stage2_api_set_job"
    Function CurrentJob:UInt() = "bmx_stage2_api_job"
    Function MarkReady(job:UInt) = "bmx_stage2_api_ready"
    Function WaitReady:Int(job:UInt) = "bmx_stage2_api_wait_ready"
    Function MarkFailed() = "bmx_stage2_api_failed"
    Function Failure:UInt() = "bmx_stage2_api_failure"
    Function SetBuffer(buffer:Byte Ptr) = "bmx_stage2_api_set_buffer"
    Function GetBuffer:Byte Ptr() = "bmx_stage2_api_get_buffer"
    Function SetPort(port:Int) = "bmx_stage2_sendto_set_port"
    Function GetPort:Int() = "bmx_stage2_sendto_get_port"
    Function LoopbackAddress:Byte Ptr() = "bmx_stage2_sendto_loopback_address"
    Function SendToRaw:Int(socket:Int, buffer:Byte Ptr, size:Int, flags:Int, ..
            destination:Byte Ptr, port:Int, family:Int) = "sendto_"
    Function SelectRaw:Int(readCount:Int, readSockets:Int Ptr, writeCount:Int, ..
            writeSockets:Int Ptr, errorCount:Int, errorSockets:Int Ptr, ..
            timeout:Int) = "select_"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function CollectionCount:UInt() = "bmx_embedded_collection_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
End Extern

Type TUdpValue
    Field number:Int
End Type

Function SendJob() { nomangle }
    Local node:TUdpValue = New TUdpValue
    Local values:Int[] = New Int[1]
    node.number = 101
    values[0] = 101
    Local label:String = "sendto-" + node.number
    Local destination:Byte Ptr = LoopbackAddress()
    Local payload:Byte Ptr = GetBuffer()
    Local sent:Int
    MarkReady(1)
    For Local attempt:Int = 0 Until 512
        If SendToRaw(Int(CurrentJob()), payload, 1, 0, ..
                destination, GetPort(), AF_INET_) = 1 Then sent :+ 1
    Next
    If sent = 0 Or payload[0] <> 120 Or node.number <> 101 Or ..
            values[0] <> 101 Or label <> "sendto-101" Then MarkFailed()
End Function

SleepMicroseconds(3000000)
Print "GC_STAGE2_UDP_SENDTO,phase=boot"
Local failedStep:Int
Local receiver:TSocket = CreateUDPSocket()
Local sender:TSocket = CreateUDPSocket()
Local outgoing:Byte Ptr = MemAlloc(1)
Local incoming:Byte Ptr = MemAlloc(1)
Local started:Int
Local joined:Int
If Not receiver Or Not sender Or Not outgoing Or Not incoming Then failedStep = 1
If Not failedStep And Not BindSocket(receiver, 0) Then failedStep = 2
If Not failedStep Then
    SetPort(SocketLocalPort(receiver))
    outgoing[0] = 120
    SetBuffer(outgoing)
    SetJob(UInt(sender.Socket()))
    started = StartManagedWorker(SendJob)
    If Not started Then failedStep = 3
End If
If Not failedStep And Not WaitReady(1) Then failedStep = 4
Print "GC_STAGE2_UDP_SENDTO,phase=ready,failed_step=" + failedStep
If Not failedStep Then
    Local before:UInt = CollectionCount()
    Local began:ULong = MonotonicMicroseconds()
    CollectObjects()
    If CollectionCount() <> before + 1 Or Not HeapValid() Then failedStep = 5
    If MonotonicMicroseconds() - began >= 300000 Then failedStep = 6
End If
Print "GC_STAGE2_UDP_SENDTO,phase=collected,failed_step=" + failedStep
If started Then
    For Local attempt:Int = 1 To 100
        joined = JoinManagedWorker()
        If joined Then Exit
    Next
    If joined <> 1 Then failedStep = 7
End If
If Not failedStep And Failure() Then failedStep = 8
If Not failedStep Then
    Local descriptor:Int = Int(receiver.Socket())
    If SelectRaw(1, Varptr descriptor, 0, Null, 0, Null, 1000) <> 1 Then
        failedStep = 9
    ElseIf receiver.Recv(incoming, Size_T(1)) <> 1 Or incoming[0] <> 120 Then
        failedStep = 10
    End If
End If
Print "GC_STAGE2_UDP_SENDTO,phase=joined,failed_step=" + failedStep
If Not started Or joined Then
    SetBuffer(Null)
    If outgoing Then MemFree(outgoing)
    If incoming Then MemFree(incoming)
    If sender Then CloseSocket(sender)
    If receiver Then CloseSocket(receiver)
End If
While True
    If failedStep Then
        Print "GC_STAGE2_UDP_SENDTO,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_UDP_SENDTO,raw=pass,roots=pass,collection=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
