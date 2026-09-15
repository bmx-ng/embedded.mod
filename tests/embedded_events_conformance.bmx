SuperStrict

Framework BRL.EventQueue
Import Embedded.Runtime.Events
Import BRL.StandardIO

Global EVENT_EMBEDDED_TEST:Int = AllocUserEventId("EmbeddedTest")
Global expectedSource:Object
Global receivedCount:Int
Global receivedSourceMatches:Int
Global receivedData:Int
Global receivedMods:Int
Global receivedX:Int
Global receivedY:Int

Extern "C"
	Function PostEmbeddedEvent:Int(token:UInt, eventData:UInt, eventMods:UInt, eventX:UInt, eventY:UInt) = "bmx_embedded_event_post_ex"
End Extern

Type TEmbeddedEventSource
End Type

Function CaptureEmbeddedEvent:Object(hookId:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If event And event.id = EVENT_EMBEDDED_TEST
		receivedCount :+ 1
		receivedSourceMatches = event.source = expectedSource
		receivedData = event.data
		receivedMods = event.mods
		receivedX = event.x
		receivedY = event.y
	End If
	Return data
End Function

AddHook EmitEventHook, CaptureEmbeddedEvent

Local source:TEmbeddedEventSource = New TEmbeddedEventSource
expectedSource = source
Local token:UInt = RegisterEmbeddedEventSource(source, EVENT_EMBEDDED_TEST, True)
If token = 0 Then RuntimeError "Embedded event source registration failed"

Local droppedBefore:UInt = EmbeddedDeferredEventDropped()
If Not PostEmbeddedEvent(token, 17, 23, 31, 47) Then RuntimeError "Embedded event post failed"
If EmbeddedDeferredEventPending() <> 1 Then RuntimeError "Embedded event pending count failed"

PollSystem()
If EmbeddedDeferredEventPending() <> 0 Then RuntimeError "Embedded event dispatch did not drain queue"
If receivedCount <> 1 Then RuntimeError "Embedded event id mismatch"
If Not receivedSourceMatches Then RuntimeError "Embedded event source mismatch"
If receivedData <> 17 Or receivedMods <> 23 Or receivedX <> 31 Or receivedY <> 47 Then ..
	RuntimeError "Embedded event payload mismatch"
If PollEvent() <> EVENT_EMBEDDED_TEST Or EventSource() <> source Then RuntimeError "BRL event queue dispatch mismatch"
If EmbeddedDeferredEventDropped() <> droppedBefore Then RuntimeError "Embedded event was unexpectedly dropped"

If Not ReleaseEmbeddedEventSource(token) Then RuntimeError "Embedded event source release failed"
If ReleaseEmbeddedEventSource(token) Then RuntimeError "Stale embedded event token was accepted"

Local oneShotSource:TEmbeddedEventSource = New TEmbeddedEventSource
expectedSource = oneShotSource
receivedCount = 0
Local oneShotToken:UInt = RegisterEmbeddedEventSource(oneShotSource, EVENT_EMBEDDED_TEST)
If oneShotToken = 0 Then RuntimeError "One-shot embedded event registration failed"
If Not PostEmbeddedEvent(oneShotToken, 99, 0, 0, 0) Then RuntimeError "One-shot embedded event post failed"
PollSystem()
If receivedCount <> 1 Or receivedData <> 99 Or Not receivedSourceMatches Then RuntimeError "One-shot embedded event mismatch"
If PollEvent() <> EVENT_EMBEDDED_TEST Or EventData() <> 99 Then RuntimeError "One-shot BRL event queue mismatch"
If ReleaseEmbeddedEventSource(oneShotToken) Then RuntimeError "One-shot embedded event source remained registered"

Print "Embedded events conformance test passed"
