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
Global focusChangeCount:Int
Global focusEventSource:Object

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
	Else If event And event.id = EVENT_UIFOCUSCHANGED Then
		focusChangeCount :+ 1
		focusEventSource = event.source
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
ui.Theme().screen.background = 0

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
Local controlRow:TUIRow = page.Row()
controlRow.SetGap(10)
controlRow.SetHeight(40)
Local checkBox:TUICheckBox = controlRow.CheckBox("Remember", False)
checkBox.OnChange(CheckChanged)
Local switchControl:TUISwitch = controlRow.Switch(False)
switchControl.OnChange(SwitchChanged)
Local slider:TUISlider = page.Slider(10, 50, 10)
slider.OnChange(SliderChanged)
Local progress:TUIProgressBar = page.ProgressBar(0, 200, 50)

Check(ui.Render(), "initial UI did not render")
Check(title.X() = 6 And title.Y() = 6, "column padding was not applied")
Check(row.X() = 6 And row.Width() = 228, "row did not stretch")
Check(cancel.Width() > 0 And Abs(connect.Width() - cancel.Width() * 2) <= 1, "weighted row growth failed")
Local checkStyle:TUIStyle = checkBox.DefaultStyle()
Local checkGap:Int = Max(checkStyle.fontScale * 4, 6)
Local checkContentRight:Int = checkBox.X() + checkStyle.paddingLeft + ..
	16 * checkStyle.fontScale + checkGap + ..
	checkStyle.font.TextWidth(checkBox.Text(), checkStyle.fontScale)
Local checkFocusRight:Int = checkBox.X() + checkBox.Width() - ui.Theme().focusInset - ..
	ui.Theme().focusWidth
Check(checkFocusRight >= checkContentRight + checkStyle.fontScale * 2, ..
	"checkbox focus outline does not clear its label")
Local checkOverflow:Int
For Local overflowY:Int = checkBox.Y() Until checkBox.Y() + checkBox.Height()
	For Local overflowX:Int = checkBox.X() + checkBox.Width() Until switchControl.X()
		If frame.Pixel(overflowX, overflowY) Then checkOverflow = True
	Next
Next
Check(Not checkOverflow, "vertically stretched checkbox label escaped its bounds")
Check(ui.HitTest(connect.X() + 1, connect.Y() + 1) = connect, "button hit test failed")
Check(ui.HitTest(0, 0) = Null, "container should not be clickable")

Check(ui.FocusedWidget() = Null, "UI unexpectedly began with focus")
Check(ui.FocusNext() And ui.FocusedWidget() = cancel, "next focus did not select first control")
Check(ui.FocusNext() And ui.FocusedWidget() = connect, "next focus did not advance")
Check(ui.FocusPrevious() And ui.FocusedWidget() = cancel, "previous focus did not move backwards")
Check(ui.SetFocus(connect) And focusEventSource = connect And focusChangeCount = 4, ..
	"explicit focus did not emit semantic focus events")
Check(ui.ActivateFocused(), "focused button did not activate")
Check(callbackCount = 1 And actionCount = 1, "focused activation did not use button semantics")
callbackCount = 0
actionCount = 0
actionSource = Null
Check(ui.Render(), "focus changes were not invalidated")

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
Check(ui.FocusedWidget() = Null, "disabling the focused control did not release focus")
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
Local sliderValueBeforeAdjust:Int = slider.Value()
Check(ui.SetFocus(slider), "slider could not receive focus")
Check(ui.AdjustFocused(2) And slider.Value() = sliderValueBeforeAdjust + 2, ..
	"focused slider did not respond to adjustment")
Check(ui.FocusPrevious() And ui.FocusedWidget() = switchControl, ..
	"focus traversal did not skip the disabled button")
Check(ui.ActivateFocused() And Not switchControl.Value(), ..
	"focused switch did not activate")

progress.SetValue(250)
Check(progress.Value() = 200, "progress value was not clamped to its range")
progress.SetRange(20, 80)
Check(progress.Value() = 80, "range change did not clamp the progress value")
Check(ui.Render(), "value control changes were not invalidated")

ui.Close()
touch.StopEvents()
Print "embedded UI conformance: PASS"
