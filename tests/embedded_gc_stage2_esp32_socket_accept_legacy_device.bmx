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
    Function AcceptRaw:Int(socket:Int, addr:Byte Ptr, addrLen:Byte Ptr) = "accept_"
    Function CloseRaw(socket:Int) = "closesocket_"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function CollectionCount:UInt() = "bmx_embedded_collection_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
End Extern

Type TAcceptValue
    Field number:Int
End Type

Function AcceptJob() { nomangle }
    Local node:TAcceptValue = New TAcceptValue
    Local values:Int[] = New Int[1]
    node.number = 71
    values[0] = 71
    Local label:String = "accept-" + node.number
    MarkReady(1)
    Local accepted:Int = AcceptRaw(Int(CurrentJob()), Null, Null)
    If accepted >= 0 Then CloseRaw(accepted)
    If accepted < 0 Or node.number <> 71 Or values[0] <> 71 Or ..
            label <> "accept-71" Then MarkFailed()
End Function

SleepMicroseconds(3000000)
Print "GC_STAGE2_SOCKET_ACCEPT_LEGACY,phase=boot"
Local failedStep:Int
Local listener:TSocket = CreateTCPSocket()
Local client:TSocket
Local started:Int
Local joined:Int
If Not listener Then failedStep = 1
If Not failedStep And Not BindSocket(listener, 0) Then failedStep = 2
If Not failedStep And Not SocketListen(listener, 1) Then failedStep = 3
If Not failedStep Then
    SetJob(UInt(listener.Socket()))
    started = StartManagedWorker(AcceptJob)
    If Not started Then failedStep = 4
End If
If Not failedStep And Not WaitReady(1) Then failedStep = 5
Print "GC_STAGE2_SOCKET_ACCEPT_LEGACY,phase=ready,failed_step=" + failedStep
If Not failedStep Then
    SleepMicroseconds(20000)
    Local before:UInt = CollectionCount()
    Local began:ULong = MonotonicMicroseconds()
    CollectObjects()
    If CollectionCount() <> before + 1 Or Not HeapValid() Then failedStep = 6
    If MonotonicMicroseconds() - began >= 300000 Then failedStep = 7
End If
Print "GC_STAGE2_SOCKET_ACCEPT_LEGACY,phase=collected,failed_step=" + failedStep
If started Then
    Local hints:TAddrInfo = New TAddrInfo(AF_INET_, SOCK_STREAM_)
    Local addresses:TAddrInfo[] = AddrInfo("127.0.0.1", String(SocketLocalPort(listener)), hints)
    If Not addresses Or addresses.length = 0 Then
        failedStep = 8
    Else
        client = TSocket.Create(addresses[0])
        If Not client Or Not ConnectSocket(client, addresses[0]) Then failedStep = 9
    End If
    If Not failedStep Then
        For Local attempt:Int = 1 To 100
            joined = JoinManagedWorker()
            If joined Then Exit
        Next
        If joined <> 1 Then failedStep = 10
    End If
End If
If Not failedStep And Failure() Then failedStep = 11
Print "GC_STAGE2_SOCKET_ACCEPT_LEGACY,phase=joined,failed_step=" + failedStep
If Not started Or joined Then
    If client Then CloseSocket(client)
    If listener Then CloseSocket(listener)
End If
While True
    If failedStep Then
        Print "GC_STAGE2_SOCKET_ACCEPT_LEGACY,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_SOCKET_ACCEPT_LEGACY,roots=pass,collection=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
