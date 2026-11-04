SuperStrict
Framework BRL.EventQueue
Import Embedded.Runtime.Events
Import Embedded.System.Time
Import BRL.StandardIO
Import "embedded_gc_stage2_callbacks_device.c"

Const CallbackCount:Int = 10000
Global CallbackEventId:Int = AllocUserEventId("Stage2Callback")
Global received:Int
Global mismatch:Int
Global expectedSource:Object

Extern "C"
    Function StartCallbacks:Int(token:UInt) = "bmx_embedded_gc_stage2_callbacks_start"
    Function AckCallback(index:UInt) = "bmx_embedded_gc_stage2_callbacks_ack"
    Function WorkerDone:Int() = "bmx_embedded_gc_stage2_callbacks_done"
    Function WorkerFailed:UInt() = "bmx_embedded_gc_stage2_callbacks_failed"
    Function JoinCallbacks:Int() = "bmx_embedded_gc_stage2_callbacks_join"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
End Extern

Type TCallbackSource
End Type

Type TCallbackPayload
    Field value:Int
End Type

Function CaptureCallback:Object(hookId:Int, data:Object, context:Object)
    Local event:TEvent = TEvent(data)
    If event And event.id = CallbackEventId
        received :+ 1
        If event.source <> expectedSource Or event.data <> received Or ..
                event.mods <> (received ~ $5a5a) Or ..
                event.x <> received + 7 Or event.y <> received + 11 Then mismatch = 1
        Local payload:TCallbackPayload = New TCallbackPayload
        payload.value = received
        If payload.value <> received Then mismatch = 2
        payload = Null
        If (received & 63) = 0
            CollectObjects()
            If Not HeapValid() Then mismatch = 3
        End If
        AckCallback(UInt(received))
    End If
    Return data
End Function

SleepMicroseconds(3000000)
AddHook EmitEventHook, CaptureCallback
Local source:TCallbackSource = New TCallbackSource
expectedSource = source
Local token:UInt = RegisterEmbeddedEventSource(source, CallbackEventId, True)
Local failedStep:Int
If token = 0 Or Not StartCallbacks(token) Then failedStep = 1
Local idle:UInt
While Not failedStep And received < CallbackCount
    Local before:Int = received
    PollSystem()
    Local polled:Int = PollEvent()
    If polled <> 0 And polled <> CallbackEventId Then failedStep = 2
    If mismatch Then failedStep = 3
    If WorkerFailed() Then failedStep = 4
    If before = received
        idle :+ 1
        If idle = 10000000 Then failedStep = 5
        If WorkerDone() And EmbeddedDeferredEventPending() = 0 Then failedStep = 6
    Else
        idle = 0
    End If
Wend
If Not failedStep And JoinCallbacks() <> 1 Then failedStep = 7
If Not failedStep And (EmbeddedDeferredEventPending() Or EmbeddedDeferredEventDropped()) Then failedStep = 8
If Not failedStep And Not ReleaseEmbeddedEventSource(token) Then failedStep = 9
While True
    If failedStep Then
        Print "GC_STAGE2_CALLBACKS,failed_step=" + failedStep + ",received=" + received
    Else
        Print "GC_STAGE2_CALLBACKS,format=1,callbacks=10000,managed=pass,collection=pass,dropped=0,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
