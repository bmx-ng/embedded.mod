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
		Return 240
	End Method

	Method Height:Int() Override
		Return 180
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
Global valueEventCount:Int
Global valueEventSource:Object
Global valueEventData:Int
Global checkChangeCount:Int
Global switchChangeCount:Int
Global sliderChangeCount:Int

Function Clicked(button:TUIButton)
	callbackCount :+ 1
End Function

Function CheckChanged(checkBox:TUICheckBox)
	checkChangeCount :+ 1
End Function

Function SwitchChanged(switchControl:TUISwitch)
	switchChangeCount :+ 1
End Function

Function SliderChanged(slider:TUISlider)
	sliderChangeCount :+ 1
End Function

Function CaptureAction:Object(hookId:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If event And event.id = EVENT_UIACTION Then
		actionCount :+ 1
		actionSource = event.source
	Else If event And event.id = EVENT_UIVALUECHANGED Then
		valueEventCount :+ 1
		valueEventSource = event.source
		valueEventData = event.data
	End If
	Return data
End Function

Function Check(condition:Int, message:String)
	If Not condition Then RuntimeError message
End Function

AddHook EmitEventHook, CaptureAction
Local frame:TDisplayBuffer = TDisplayBuffer.Create(240, 180, DisplayPixelFormatMono1)
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
Local checkBox:TUICheckBox = page.CheckBox("Remember", False)
checkBox.OnChange(CheckChanged)
Local switchControl:TUISwitch = page.Switch(False)
switchControl.OnChange(SwitchChanged)
Local slider:TUISlider = page.Slider(10, 50, 10)
slider.OnChange(SliderChanged)
Local progress:TUIProgressBar = page.ProgressBar(0, 200, 50)

Check(ui.Render(), "initial UI did not render")
Check(title.X() = 6 And title.Y() = 6, "column padding was not applied")
Check(row.X() = 6 And row.Width() = 228, "row did not stretch")
Check(cancel.Width() > 0 And Abs(connect.Width() - cancel.Width() * 2) <= 1, "weighted row growth failed")
Check(ui.HitTest(connect.X() + 1, connect.Y() + 1) = connect, "button hit test failed")
Check(ui.HitTest(0, 0) = Null, "container should not be clickable")

touch.count = 1
touch.x = connect.X() + connect.Width() / 2
touch.y = connect.Y() + connect.Height() / 2
PollSystem()
Check(connect.Pressed(), "touch down did not press button")
Check(ui.Render(), "pressed state was not invalidated")

' A single missed controller sample must not manufacture an early release.
touch.count = 0
PollSystem()
Check(connect.Pressed(), "single-sample touch dropout released the button")
Check(callbackCount = 0 And actionCount = 0, "touch dropout activated the button")
touch.count = 1
PollSystem()
Check(connect.Pressed(), "returning contact did not retain capture")

touch.count = 0
PollSystem()
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
PollSystem()
Check(callbackCount = 1 And actionCount = 1, "disabled button accepted input")

touch.x = checkBox.X() + 2
touch.y = checkBox.Y() + checkBox.Height() / 2
touch.count = 1
PollSystem()
touch.count = 0
PollSystem()
PollSystem()
Check(checkBox.Checked(), "checkbox did not toggle")
Check(checkChangeCount = 1, "checkbox callback was not invoked")
Check(valueEventCount = 1 And valueEventSource = checkBox And valueEventData = 1, ..
	"checkbox value event was not emitted")

touch.x = switchControl.X() + switchControl.Width() / 2
touch.y = switchControl.Y() + switchControl.Height() / 2
touch.count = 1
PollSystem()
touch.count = 0
PollSystem()
PollSystem()
Check(switchControl.Value(), "switch did not toggle")
Check(switchChangeCount = 1, "switch callback was not invoked")
Check(valueEventCount = 2 And valueEventSource = switchControl And valueEventData = 1, ..
	"switch value event was not emitted")

touch.x = slider.X() + slider.Width() / 4
touch.y = slider.Y() + slider.Height() / 2
touch.count = 1
PollSystem()
Local sliderChangesBeforeMove:Int = sliderChangeCount
touch.x = slider.X() + slider.Width() * 3 / 4
PollSystem()
touch.count = 0
PollSystem()
PollSystem()
Check(slider.Value() > 30 And slider.Value() < 50, "slider did not track touch position")
Check(sliderChangeCount > sliderChangesBeforeMove, "slider callback did not track movement")
Check(valueEventSource = slider And valueEventData = slider.Value(), "slider value event was not emitted")

progress.SetValue(250)
Check(progress.Value() = 200, "progress value was not clamped to its range")
progress.SetRange(20, 80)
Check(progress.Value() = 80, "range change did not clamp the progress value")
Check(ui.Render(), "value control changes were not invalidated")

ui.Close()
touch.StopEvents()
Print "embedded UI conformance: PASS"
