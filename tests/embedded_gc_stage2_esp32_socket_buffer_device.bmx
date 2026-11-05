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
    Function RecordRead(count:Int, value:Int) = "bmx_stage2_api_record_read"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function CollectionCount:UInt() = "bmx_embedded_collection_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
End Extern

Type TSocketValue
    Field number:Int
End Type

Function ReadJob() { nomangle }
    Local node:TSocketValue = New TSocketValue
    Local values:Int[] = New Int[1]
    node.number = 53
    values[0] = 53
    Local label:String = "socket-" + node.number
    Local buffer:Byte Ptr = GetBuffer()
    MarkReady(1)
    Local count:Int = Int(recv_(Int(CurrentJob()), buffer, 1, 0))
    RecordRead(count, Int(buffer[0]))
    If count <> 1 Or buffer[0] <> 120 Or node.number <> 53 Or ..
            values[0] <> 53 Or label <> "socket-53" Then MarkFailed()
End Function

SleepMicroseconds(3000000)
Print "GC_STAGE2_SOCKET_BUFFER,phase=boot"
Local failedStep:Int
Local listener:TSocket = CreateTCPSocket()
Local client:TSocket
Local server:TSocket
Local incoming:Byte Ptr = MemAlloc(1)
Local outgoing:Byte Ptr = MemAlloc(1)
Local started:Int
Local joined:Int
If Not listener Or Not incoming Or Not outgoing Then failedStep = 1
If Not failedStep And Not BindSocket(listener, 0) Then failedStep = 2
If Not failedStep And Not SocketListen(listener, 1) Then failedStep = 3
Local addresses:TAddrInfo[]
If Not failedStep Then
    Local hints:TAddrInfo = New TAddrInfo(AF_INET_, SOCK_STREAM_)
    addresses = AddrInfo("127.0.0.1", String(SocketLocalPort(listener)), hints)
    If Not addresses Or addresses.length = 0 Then failedStep = 4
End If
If Not failedStep Then
    client = TSocket.Create(addresses[0])
    If Not client Or Not ConnectSocket(client, addresses[0]) Then failedStep = 5
End If
If Not failedStep Then
    server = SocketAccept(listener, 1000)
    If Not server Then failedStep = 6
End If
If Not failedStep Then
    SetBuffer(incoming)
    SetJob(UInt(server.Socket()))
    started = StartManagedWorker(ReadJob)
    If Not started Then failedStep = 7
End If
If Not failedStep And Not WaitReady(1) Then failedStep = 8
Print "GC_STAGE2_SOCKET_BUFFER,phase=ready,failed_step=" + failedStep
If Not failedStep Then
    SleepMicroseconds(20000)
    Local before:UInt = CollectionCount()
    Local began:ULong = MonotonicMicroseconds()
    CollectObjects()
    If CollectionCount() <> before + 1 Or Not HeapValid() Then failedStep = 9
    If MonotonicMicroseconds() - began >= 300000 Then failedStep = 10
End If
Print "GC_STAGE2_SOCKET_BUFFER,phase=collected,failed_step=" + failedStep
If started Then
    outgoing[0] = 120
    If client.Send(outgoing, 1) <> 1 Then failedStep = 11
    For Local attempt:Int = 1 To 100
        joined = JoinManagedWorker()
        If joined Then Exit
    Next
    If Not failedStep And joined <> 1 Then failedStep = 12
End If
If Not failedStep And Failure() Then failedStep = 13
Print "GC_STAGE2_SOCKET_BUFFER,phase=joined,failed_step=" + failedStep
If Not started Or joined Then
    SetBuffer(Null)
    If incoming Then MemFree(incoming)
    If outgoing Then MemFree(outgoing)
    If server Then CloseSocket(server)
    If client Then CloseSocket(client)
    If listener Then CloseSocket(listener)
End If
While True
    If failedStep Then
        Print "GC_STAGE2_SOCKET_BUFFER,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_SOCKET_BUFFER,raw=pass,roots=pass,collection=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
