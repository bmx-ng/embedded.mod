SuperStrict
Framework BRL.StandardIO
Import BRL.Socket
Import Embedded.Runtime.Worker
Import Embedded.System.Time
Import "embedded_gc_stage2_managed_api_device.c"

Extern "C"
    Function SetJob(job:UInt) = "bmx_stage2_api_set_job"
    Function CurrentJob:UInt() = "bmx_stage2_api_job"
    Function MarkReady(job:UInt) = "bmx_stage2_api_ready"
    Function WaitReady:Int(job:UInt) = "bmx_stage2_api_wait_ready"
    Function MarkFailed() = "bmx_stage2_api_failed"
    Function Failure:UInt() = "bmx_stage2_api_failure"
    Function SetBuffer(buffer:Byte Ptr) = "bmx_stage2_api_set_buffer"
    Function GetBuffer:Byte Ptr() = "bmx_stage2_api_get_buffer"
    Function ReceiveFrom:Int(socket:Int, buffer:Byte Ptr, size:Int, flags:Int, ..
            senderIp:Int Var, senderPort:Int Var) = "recvfrom_"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function CollectionCount:UInt() = "bmx_embedded_collection_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
End Extern

Type TUdpValue
    Field number:Int
End Type

Function ReceiveJob() { nomangle }
    Local node:TUdpValue = New TUdpValue
    Local values:Int[] = New Int[1]
    node.number = 97
    values[0] = 97
    Local label:String = "udp-" + node.number
    Local buffer:Byte Ptr = GetBuffer()
    Local senderIp:Int
    Local senderPort:Int
    MarkReady(1)
    Local count:Int = ReceiveFrom(Int(CurrentJob()), buffer, 1, 0, senderIp, senderPort)
    If count <> 1 Or buffer[0] <> 120 Or senderIp = 0 Or senderPort = 0 Or ..
            node.number <> 97 Or values[0] <> 97 Or label <> "udp-97" Then MarkFailed()
End Function

SleepMicroseconds(3000000)
Print "GC_STAGE2_UDP_RECVFROM,phase=boot"
Local failedStep:Int
Local receiver:TSocket = CreateUDPSocket()
Local sender:TSocket
Local incoming:Byte Ptr = MemAlloc(1)
Local outgoing:Byte Ptr = MemAlloc(1)
Local started:Int
Local joined:Int
If Not receiver Or Not incoming Or Not outgoing Then failedStep = 1
If Not failedStep And Not BindSocket(receiver, 0) Then failedStep = 2
If Not failedStep Then
    Local hints:TAddrInfo = New TAddrInfo(AF_INET_, SOCK_DGRAM_)
    Local addresses:TAddrInfo[] = AddrInfo("127.0.0.1", String(SocketLocalPort(receiver)), hints)
    If Not addresses Or addresses.length = 0 Then
        failedStep = 3
    Else
        sender = TSocket.Create(addresses[0])
        If Not sender Or Not ConnectSocket(sender, addresses[0]) Then failedStep = 4
    End If
End If
If Not failedStep Then
    SetBuffer(incoming)
    SetJob(UInt(receiver.Socket()))
    started = StartManagedWorker(ReceiveJob)
    If Not started Then failedStep = 5
End If
If Not failedStep And Not WaitReady(1) Then failedStep = 6
Print "GC_STAGE2_UDP_RECVFROM,phase=ready,failed_step=" + failedStep
If Not failedStep Then
    SleepMicroseconds(20000)
    Local before:UInt = CollectionCount()
    Local began:ULong = MonotonicMicroseconds()
    CollectObjects()
    If CollectionCount() <> before + 1 Or Not HeapValid() Then failedStep = 7
    If MonotonicMicroseconds() - began >= 300000 Then failedStep = 8
End If
Print "GC_STAGE2_UDP_RECVFROM,phase=collected,failed_step=" + failedStep
If started Then
    outgoing[0] = 120
    If sender.Send(outgoing, Size_T(1)) <> 1 Then failedStep = 9
    If Not failedStep Then
        For Local attempt:Int = 1 To 100
            joined = JoinManagedWorker()
            If joined Then Exit
        Next
        If joined <> 1 Then failedStep = 10
    End If
End If
If Not failedStep And Failure() Then failedStep = 11
Print "GC_STAGE2_UDP_RECVFROM,phase=joined,failed_step=" + failedStep
If Not started Or joined Then
    SetBuffer(Null)
    If incoming Then MemFree(incoming)
    If outgoing Then MemFree(outgoing)
    If sender Then CloseSocket(sender)
    If receiver Then CloseSocket(receiver)
End If
While True
    If failedStep Then
        Print "GC_STAGE2_UDP_RECVFROM,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_UDP_RECVFROM,raw=pass,roots=pass,collection=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
