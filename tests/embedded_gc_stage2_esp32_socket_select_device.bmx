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
    Function SelectRaw:Int(readCount:Int, readSockets:Int Ptr, writeCount:Int, ..
            writeSockets:Int Ptr, errorCount:Int, errorSockets:Int Ptr, ..
            timeout:Int) = "select_"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function CollectionCount:UInt() = "bmx_embedded_collection_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
End Extern

Type TSelectValue
    Field number:Int
End Type

Function SelectJob() { nomangle }
    Local node:TSelectValue = New TSelectValue
    Local values:Int[] = New Int[1]
    node.number = 83
    values[0] = 83
    Local label:String = "select-" + node.number
    Local socket:Int = Int(CurrentJob())
    MarkReady(1)
    Local selected:Int = SelectRaw(1, Varptr socket, 0, Null, 0, Null, 1000)
    If selected <> 1 Or socket <> Int(CurrentJob()) Or node.number <> 83 Or ..
            values[0] <> 83 Or label <> "select-83" Then MarkFailed()
End Function

SleepMicroseconds(3000000)
Print "GC_STAGE2_SOCKET_SELECT,phase=boot"
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
    started = StartManagedWorker(SelectJob)
    If Not started Then failedStep = 4
End If
If Not failedStep And Not WaitReady(1) Then failedStep = 5
Print "GC_STAGE2_SOCKET_SELECT,phase=ready,failed_step=" + failedStep
If Not failedStep Then
    SleepMicroseconds(20000)
    Local before:UInt = CollectionCount()
    Local began:ULong = MonotonicMicroseconds()
    CollectObjects()
    If CollectionCount() <> before + 1 Or Not HeapValid() Then failedStep = 6
    If MonotonicMicroseconds() - began >= 300000 Then failedStep = 7
End If
Print "GC_STAGE2_SOCKET_SELECT,phase=collected,failed_step=" + failedStep
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
Print "GC_STAGE2_SOCKET_SELECT,phase=joined,failed_step=" + failedStep
If Not started Or joined Then
    If client Then CloseSocket(client)
    If listener Then CloseSocket(listener)
End If
While True
    If failedStep Then
        Print "GC_STAGE2_SOCKET_SELECT,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_SOCKET_SELECT,roots=pass,collection=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
