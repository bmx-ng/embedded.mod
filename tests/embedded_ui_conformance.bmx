SuperStrict

Framework BRL.StandardIO
Import BRL.Event
Import BRL.System
Import BRL.SystemDefault
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Drivers.Touch
Import Embedded.UI

Type TFakeTouch Extends TTouchDevice
	Field count:Int
	Field x:Int
	Field y:Int

	Method Width:Int() Override
		Return 160
	End Method

	Method Height:Int() Override
		Return 80
	End Method

	Method PollContacts:Int() Override
		Return count
	End Method

	Method ContactId:Int(index:Int) Override
		Return 3
	End Method

	Method ContactX:Int(index:Int) Override
		Return x
	End Method

	Method ContactY:Int(index:Int) Override
		Return y
	End Method
End Type

Global callbackCount:Int
Global actionCount:Int
Global actionSource:Object

Function Clicked(button:TUIButton)
	callbackCount :+ 1
End Function

Function CaptureAction:Object(hookId:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If event And event.id = EVENT_UIACTION Then
		actionCount :+ 1
		actionSource = event.source
	End If
	Return data
End Function

Function Check(condition:Int, message:String)
	If Not condition Then RuntimeError message
End Function

AddHook EmitEventHook, CaptureAction
Local frame:TDisplayBuffer = TDisplayBuffer.Create(160, 80, DisplayPixelFormatRGB565)
Local touch:TFakeTouch = New TFakeTouch
Check(touch.StartEvents(), "could not start fake touch")
Local ui:TUIContext = TUIContext.CreateWithBuffer(frame, Null, touch, ..
	TUITheme.Dark(Spleen5x8Font()))
Check(ui <> Null, "could not create UI")

Local page:TUIColumn = ui.Root()
page.SetPadding(6)
page.SetGap(4)
Local title:TUILabel = page.Label("Network")
Local row:TUIRow = page.Row()
row.SetGap(5)
Local cancel:TUIButton = row.Button("Cancel")
Local connect:TUIButton = row.Button("Connect")
cancel.SetGrow(1)
connect.SetGrow(2)
connect.OnClick(Clicked)

Check(ui.Render(), "initial UI did not render")
Check(title.X() = 6 And title.Y() = 6, "column padding was not applied")
Check(row.X() = 6 And row.Width() = 148, "row did not stretch")
Check(cancel.Width() > 0 And Abs(connect.Width() - cancel.Width() * 2) <= 1, "weighted row growth failed")
Check(ui.HitTest(connect.X() + 1, connect.Y() + 1) = connect, "button hit test failed")
Check(ui.HitTest(0, 0) = Null, "container should not be clickable")

touch.count = 1
touch.x = connect.X() + connect.Width() / 2
touch.y = connect.Y() + connect.Height() / 2
PollSystem()
Check(connect.Pressed(), "touch down did not press button")
Check(ui.Render(), "pressed state was not invalidated")

touch.count = 0
PollSystem()
Check(Not connect.Pressed(), "touch up did not release button")
Check(callbackCount = 1, "click callback was not invoked")
Check(actionCount = 1 And actionSource = connect, "semantic action event was not emitted")
Check(ui.Render(), "released state was not invalidated")

connect.SetEnabled(False)
ui.Render()
touch.count = 1
PollSystem()
touch.count = 0
PollSystem()
Check(callbackCount = 1 And actionCount = 1, "disabled button accepted input")

ui.Close()
touch.StopEvents()
Print "embedded UI conformance: PASS"
