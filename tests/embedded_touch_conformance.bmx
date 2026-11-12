SuperStrict

Framework BRL.StandardIO
Import BRL.Event
Import BRL.System
Import BRL.SystemDefault
Import Embedded.Drivers.Touch

Type TFakeTouch Extends TTouchDevice
	Field count:Int
	Field ids:Int[TouchMaximumContacts]
	Field xs:Int[TouchMaximumContacts]
	Field ys:Int[TouchMaximumContacts]

	Method Width:Int() Override
		Return 101
	End Method

	Method Height:Int() Override
		Return 51
	End Method

	Method PollContacts:Int() Override
		Return count
	End Method

	Method ContactId:Int(index:Int) Override
		Return ids[index]
	End Method

	Method ContactX:Int(index:Int) Override
		Return xs[index]
	End Method

	Method ContactY:Int(index:Int) Override
		Return ys[index]
	End Method
End Type

Global capturedId:Int
Global capturedData:Int
Global capturedX:Int
Global capturedY:Int
Global capturedCount:Int

Function CaptureTouch:Object(hookId:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If event And (event.id = EVENT_TOUCHDOWN Or event.id = EVENT_TOUCHMOVE Or ..
		event.id = EVENT_TOUCHUP) Then
		capturedId = event.id
		capturedData = event.data
		capturedX = event.x
		capturedY = event.y
		capturedCount :+ 1
	End If
	Return data
End Function

Function Check(condition:Int, message:String)
	If Not condition Then RuntimeError message
End Function

AddHook EmitEventHook, CaptureTouch
Local touch:TFakeTouch = New TFakeTouch
Check touch.StartEvents(), "could not register fake touch device"

touch.count = 1
touch.ids[0] = 7
touch.xs[0] = 50
touch.ys[0] = 25
PollSystem
Check capturedId = EVENT_TOUCHDOWN, "missing touch down"
Check capturedData = 7, "wrong contact id"
Check capturedX = 5000 And capturedY = 5000, "wrong normalized midpoint"

touch.xs[0] = 100
touch.ys[0] = 50
PollSystem
Check capturedId = EVENT_TOUCHMOVE, "missing touch move"
Check capturedX = 10000 And capturedY = 10000, "wrong normalized edge"

touch.count = 0
PollSystem
Check capturedId = EVENT_TOUCHUP, "missing touch up"
Check capturedData = 7, "wrong released contact id"
Check capturedCount = 3, "unexpected event count"

touch.StopEvents()
Print "embedded touch conformance: PASS"
