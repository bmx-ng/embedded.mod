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
Global selectionChangeCount:Int
Global selectionEventSource:Object
Global selectionEventIndex:Int
Global selectionCallbackCount:Int
Global radioCallbackCount:Int
Global stepperCallbackCount:Int
Global segmentCallbackCount:Int
Global dialogCallbackCount:Int
Global dialogCallbackResult:Int

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

Function SelectionChanged(list:TUIList)
	selectionCallbackCount :+ 1
End Function

Function RadioChanged(group:TUIRadioGroup)
	radioCallbackCount :+ 1
End Function

Function StepperChanged(stepper:TUIStepper)
	stepperCallbackCount :+ 1
End Function

Function SegmentChanged(control:TUISegmentedControl)
	segmentCallbackCount :+ 1
End Function

Function DialogClosed(dialog:TUIDialog, result:Int)
	dialogCallbackCount :+ 1
	dialogCallbackResult = result
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
	Else If event And event.id = EVENT_UISELECTIONCHANGED Then
		selectionChangeCount :+ 1
		selectionEventSource = event.source
		selectionEventIndex = event.data
	End If
	Return data
End Function

Function Check(condition:Int, message:String)
	If Not condition Then RuntimeError message
End Function

Function RunTabTests(touch:TFakeTouch)
	Local navigationFrame:TDisplayBuffer = TDisplayBuffer.Create(240, 180, DisplayPixelFormatMono1)
	Local navigationUI:TUIContext = TUIContext.CreateWithBuffer(navigationFrame, Null, touch, ..
		TUITheme.Dark(Spleen5x8Font()))
	Check(navigationUI <> Null, "could not create tab UI")
	navigationUI.Theme().screen.background = 0
	Local navigationPage:TUIColumn = navigationUI.Root()
	navigationPage.SetPadding(4)
	navigationPage.SetGap(4)
	Local tabs:TUITabView = navigationPage.TabView()
	tabs.SetHeight(76)
	Local generalPage:TUITabPage = tabs.Page("General")
	generalPage.SetPadding(3)
	generalPage.Label("General settings")
	Local networkPage:TUITabPage = tabs.Page("Network")
	networkPage.SetPadding(3)
	networkPage.Label("Network settings")
	Local navigationSelectionStart:Int = selectionChangeCount
	Check(navigationUI.Render(), "tab UI did not render")
	Check(tabs.SelectedIndex() = 0 And generalPage.Visible() And Not networkPage.Visible(), ..
		"tab view did not begin on its first page")
	Check(navigationUI.SetFocus(tabs.TabButtonAt(1)), "second tab could not receive focus")
	Check(navigationUI.ActivateFocused(), "focused tab did not activate")
	Check(tabs.SelectedIndex() = 1 And Not generalPage.Visible() And networkPage.Visible(), ..
		"tab activation did not switch retained pages")
	Check(selectionChangeCount = navigationSelectionStart + 1 And ..
		selectionEventSource = tabs And selectionEventIndex = 1, ..
		"tab selection did not emit its semantic event")
	navigationUI.Close()
End Function

Function RunComboTests(touch:TFakeTouch)
	' Combo boxes use a focus-trapping popup and outside dismissal must not leak
	' the same touch sequence to a control underneath.
	Local navigationFrame:TDisplayBuffer = TDisplayBuffer.Create(240, 180, DisplayPixelFormatMono1)
	Local navigationUI:TUIContext = TUIContext.CreateWithBuffer(navigationFrame, Null, touch, ..
		TUITheme.Dark(Spleen5x8Font()))
	Check(navigationUI <> Null, "could not create combo UI")
	Local navigationPage:TUIColumn = navigationUI.Root()
	navigationPage.SetPadding(4)
	navigationPage.SetGap(4)
	Local underlying:TUIButton = navigationPage.Button("Underlying action")
	Local combo:TUIComboBox = navigationPage.ComboBox()
	combo.AddItem("Automatic")
	combo.AddItem("Station")
	combo.AddItem("Access point")
	combo.SetSelectedIndex(1)
	Local navigationSelectionStart:Int = selectionChangeCount
	Check(navigationUI.Render(), "combo UI did not render")
	Check(navigationUI.SetFocus(combo), "combo box could not receive focus")
	Check(navigationUI.ActivateFocused() And navigationUI.OverlayVisible(), ..
		"combo box did not open its popup")
	Local comboPopup:TUIPopupMenu = combo.ActivePopup()
	Check(comboPopup And navigationUI.ActiveOverlay() = comboPopup, ..
		"combo popup was not installed as the active overlay")
	Check(navigationUI.FocusedWidget() = comboPopup.ItemAt(1), ..
		"combo popup did not focus its current selection")
	Check(navigationUI.FocusNext() And navigationUI.FocusedWidget() = comboPopup.ItemAt(2), ..
		"overlay focus did not remain inside the popup")
	Check(navigationUI.ActivateFocused(), "focused combo item did not activate")
	Check(Not navigationUI.OverlayVisible() And navigationUI.FocusedWidget() = combo And ..
		combo.SelectedIndex() = 2, "combo selection did not close and restore focus")
	Check(selectionChangeCount = navigationSelectionStart + 1 And ..
		selectionEventSource = combo And selectionEventIndex = 2, ..
		"combo selection did not emit its semantic event")

	' An outside press dismisses the popup and is consumed.
	Check(navigationUI.ActivateFocused() And navigationUI.OverlayVisible(), ..
		"combo popup could not be reopened")
	touch.x = underlying.X() + underlying.Width() / 2
	touch.y = underlying.Y() + underlying.Height() / 2
	touch.count = 1
	PollSystem()
	Check(Not navigationUI.OverlayVisible(), "outside touch did not dismiss popup")
	touch.count = 0
	PollSystem()
	PollSystem()
	Check(Not underlying.Pressed(), ..
		"outside dismissal leaked input to the underlying UI")
	navigationUI.Close()
End Function

Function RunPopupMenuTests(touch:TFakeTouch)
	Local navigationFrame:TDisplayBuffer = TDisplayBuffer.Create(240, 180, DisplayPixelFormatMono1)
	Local navigationUI:TUIContext = TUIContext.CreateWithBuffer(navigationFrame, Null, touch, ..
		TUITheme.Dark(Spleen5x8Font()))
	Check(navigationUI <> Null, "could not create popup menu UI")
	Local menu:TUIPopupMenu = navigationUI.PopupMenu()
	menu.Item("Copy")
	menu.Item("Rename")
	menu.Item("Delete")
	menu.OnSelectionChanged(SelectionChanged)
	Local menuCallbackStart:Int = selectionCallbackCount
	Check(navigationUI.ShowOverlay(menu, 80, 30, 100), "popup menu could not be shown")
	Check(navigationUI.FocusedWidget() = menu.ItemAt(0), "popup menu did not focus its first item")
	Check(navigationUI.ActivateFocused(), "popup menu item did not activate")
	Check(Not navigationUI.OverlayVisible() And menu.SelectedIndex() = 0 And ..
		selectionCallbackCount = menuCallbackStart + 1, ..
		"popup menu selection did not notify and dismiss")
	navigationUI.Close()
End Function

Function RunChoiceWidgetTests(touch:TFakeTouch)
	Local choiceFrame:TDisplayBuffer = TDisplayBuffer.Create(240, 180, DisplayPixelFormatMono1)
	Local choiceUI:TUIContext = TUIContext.CreateWithBuffer(choiceFrame, Null, touch, ..
		TUITheme.Dark(Spleen5x8Font()))
	Check(choiceUI <> Null, "could not create choice widget UI")
	Local page:TUIColumn = choiceUI.Root()
	Local radios:TUIRadioGroup = page.RadioGroup()
	radios.Option("Low")
	radios.Option("Medium")
	radios.Option("High")
	radios.OnSelectionChanged(RadioChanged)
	Local stepper:TUIStepper = page.Stepper(0, 10, 4, 2)
	stepper.OnChange(StepperChanged)
	Local segments:TUISegmentedControl = page.SegmentedControl()
	segments.AddItem("One")
	segments.AddItem("Two")
	segments.AddItem("Three")
	segments.OnSelectionChanged(SegmentChanged)
	Check(choiceUI.Render(), "choice widget UI did not render")

	Local selectionStart:Int = selectionChangeCount
	Check(choiceUI.SetFocus(radios.OptionAt(1)), "radio option could not receive focus")
	Check(choiceUI.ActivateFocused() And radios.SelectedIndex() = 1, "radio option did not select")
	Check(radioCallbackCount = 1 And selectionChangeCount = selectionStart + 1 And ..
		selectionEventSource = radios And selectionEventIndex = 1, "radio selection did not notify")
	Check(choiceUI.AdjustFocused(1) And radios.SelectedIndex() = 2 And ..
		choiceUI.FocusedWidget() = radios.OptionAt(2), "radio focus adjustment did not select and move")

	Local valueStart:Int = valueEventCount
	Check(choiceUI.SetFocus(stepper), "stepper could not receive focus")
	Check(choiceUI.AdjustFocused(1) And stepper.Value() = 6, "stepper did not apply its step")
	stepper._ActivateAt(stepper.X())
	Check(stepper.Value() = 4 And stepperCallbackCount = 2 And ..
		valueEventCount = valueStart + 2 And valueEventSource = stepper, "stepper did not notify both changes")

	selectionStart = selectionChangeCount
	Check(choiceUI.SetFocus(segments), "segmented control could not receive focus")
	segments._ActivateAt(segments.X() + segments.Width() * 5 / 6)
	Check(segments.SelectedIndex() = 2 And segmentCallbackCount = 1 And ..
		selectionChangeCount = selectionStart + 1 And selectionEventSource = segments, ..
		"segmented control did not select its touched segment")
	Check(choiceUI.AdjustFocused(-1) And segments.SelectedIndex() = 1, ..
		"segmented control did not adjust through focus")
	choiceUI.Close()
End Function

Function RunDialogTests(touch:TFakeTouch)
	Local dialogFrame:TDisplayBuffer = TDisplayBuffer.Create(240, 180, DisplayPixelFormatMono1)
	Local dialogUI:TUIContext = TUIContext.CreateWithBuffer(dialogFrame, Null, touch, ..
		TUITheme.Dark(Spleen5x8Font()))
	Check(dialogUI <> Null, "could not create dialog UI")
	Local opener:TUIButton = dialogUI.Root().Button("Open")
	Check(dialogUI.Render() And dialogUI.SetFocus(opener), "dialog opener could not receive focus")
	Local dialog:TUIDialog = dialogUI.Dialog("Apply changes?", "The device will restart.")
	dialog.Action("Cancel", 0)
	Local accept:TUIDialogAction = dialog.Action("Apply", 1)
	dialog.OnResult(DialogClosed)
	Local actionStart:Int = actionCount
	Check(dialog.Show(180) And dialogUI.ActiveOverlay() = dialog, "modal dialog did not open")
	Check(dialogUI.FocusedWidget() <> opener, "modal dialog did not trap focus")
	Check(dialogUI.SetFocus(accept) And dialogUI.ActivateFocused(), "dialog action did not activate")
	Check(Not dialogUI.OverlayVisible() And dialogUI.FocusedWidget() = opener, ..
		"dialog did not dismiss and restore focus")
	Check(dialog.Result() = 1 And dialogCallbackCount = 1 And dialogCallbackResult = 1, ..
		"dialog did not report its result")
	Check(actionCount >= actionStart + 1 And actionSource = dialog, "dialog did not emit its result event")
	dialogUI.Close()
End Function

Function RunWrappedLabelTests(touch:TFakeTouch)
	Local textFrame:TDisplayBuffer = TDisplayBuffer.Create(120, 80, DisplayPixelFormatMono1)
	Local textUI:TUIContext = TUIContext.CreateWithBuffer(textFrame, Null, touch, ..
		TUITheme.Dark(Spleen5x8Font()))
	Check(textUI <> Null, "could not create wrapped label UI")
	Local label:TUILabel = textUI.Root().Label("A retained label wraps at available words")
	label.SetWordWrap(True)
	Check(textUI.Render(), "wrapped label UI did not render")
	Check(label.Height() >= Spleen5x8Font().LineHeight() * 2, "label did not wrap to multiple lines")
	textUI.Close()
End Function

Function RunDecimalStepperTests(touch:TFakeTouch)
	Local decimalFrame:TDisplayBuffer = TDisplayBuffer.Create(160, 60, DisplayPixelFormatMono1)
	Local decimalUI:TUIContext = TUIContext.CreateWithBuffer(decimalFrame, Null, touch, ..
		TUITheme.Dark(Spleen5x8Font()))
	Check(decimalUI <> Null, "could not create decimal stepper UI")
	Local stepper:TUIStepper = decimalUI.Root().DecimalStepper(-1.0, 1.0, 0.0, 0.25, 2)
	stepper.OnChange(StepperChanged)
	Check(decimalUI.Render() And stepper.ValueText() = "0.00", "decimal stepper did not format zero")
	Local callbackStart:Int = stepperCallbackCount
	stepper._ActivateAt(stepper.X() + stepper.Width() - 1)
	Check(stepper.DecimalValue() = 0.25 And stepper.ValueText() = "0.25", ..
		"decimal stepper did not apply its fractional step")
	stepper.SetDecimalValue(-0.5)
	Check(stepper.ValueText() = "-0.50" And stepperCallbackCount = callbackStart + 1, ..
		"decimal stepper programmatic value or notification semantics were incorrect")
	decimalUI.Close()
End Function

Function RunToastTests(toastUI:TUIContext, toastFrame:TDisplayBuffer, focused:TUIWidget)
	' Reuse the primary fixture: the embedded collector deliberately retains
	' closed fixtures until its next collection, while this suite uses a small
	' 64 KiB heap to expose accidental allocation growth.
	toastUI.SetToastVisibleLimit(1)
	Check(toastUI.SetFocus(focused), "toast test control could not receive focus")

	Local first:TUIToast = toastUI.Toast("Saved successfully", 100, UIToastSuccess)
	Check(first <> Null And toastUI.ActiveToast() = first, "toast did not become active")
	Check(first.Message() = "Saved successfully" And first.Kind() = UIToastSuccess And ..
		Not first.Persistent(), "toast properties were not retained")
	Check(toastUI.FocusedWidget() = focused And toastUI.HitTest(first.X() + 1, first.Y() + 1) <> first, ..
		"toast stole focus or touch input")
	Local second:TUIToast = toastUI.Toast("Check the network configuration before retrying", ..
		0, UIToastWarning)
	Check(second <> Null And second.Persistent() And toastUI.PendingToastCount() = 1, ..
		"persistent toast was not queued")
	toastUI._UpdateToast(UInt(MilliSecs()) + 200)
	Check(toastUI.ActiveToast() = second And toastUI.PendingToastCount() = 0, ..
		"timed toast did not advance its queue")
	toastUI._UpdateToast(UInt(MilliSecs()) + 10000)
	Check(toastUI.ActiveToast() = second, "persistent toast expired")

	Local queued:TUIToast = toastUI.Toast("Queued", 100, UIToastInfo)
	Check(toastUI.DismissToast(queued) And toastUI.PendingToastCount() = 0, ..
		"specific queued toast could not be dismissed")
	For Local index:Int = 0 Until UIToastQueueMaximum
		Check(toastUI.Toast("Queue " + index, 100, UIToastInfo) <> Null, ..
			"toast queue rejected an available slot")
	Next
	Check(toastUI.Toast("Overflow", 100, UIToastError) = Null, "toast queue exceeded its bound")
	Check(toastUI.DismissToast() And toastUI.ActiveToast() <> second And ..
		toastUI.PendingToastCount() = UIToastQueueMaximum - 1, "toast dismissal did not advance FIFO order")
	toastUI.ClearToasts()
	Check(toastUI.ActiveToast() = Null And toastUI.PendingToastCount() = 0, ..
		"toast queue did not clear")

	toastUI.SetToastVisibleLimit(3)
	toastUI.SetToastPlacement(UIToastBottomRight)
	toastUI.SetToastGap(5)
	Local stackFirst:TUIToast = toastUI.Toast("First", 0, UIToastInfo)
	Local stackSecond:TUIToast = toastUI.Toast("Second", 0, UIToastSuccess)
	Local stackThird:TUIToast = toastUI.Toast("Third", 0, UIToastWarning)
	Check(toastUI.VisibleToastCount() = 3 And toastUI.PendingToastCount() = 0, ..
		"toast stack did not expose its configured visible count")
	Check(stackFirst.Y() < stackSecond.Y() And stackSecond.Y() < stackThird.Y() And ..
		stackThird.X() + stackThird.Width() = toastFrame.Width() - toastUI.ToastMargin(), ..
		"bottom-right toast stack was not anchored or ordered correctly")
	Local firstYBefore:Int = stackFirst.Y()
	Check(toastUI.DismissToast(stackSecond) And toastUI.VisibleToastCount() = 2, ..
		"toast stack did not dismiss a selected notification")
	toastUI.Render()
	Check(stackFirst.Y() > firstYBefore And stackFirst.Y() < stackThird.Y(), ..
		"toast stack did not reflow after dismissal")
	toastUI.ClearToasts()

	Local overlayToast:TUIToast = toastUI.Toast("Visible over dialog", 0, UIToastInfo)
	Local dialog:TUIDialog = toastUI.Dialog("Modal", "Toast remains independent")
	dialog.Action("Close", 0)
	Check(dialog.Show(140) And toastUI.ActiveOverlay() = dialog And ..
		toastUI.ActiveToast() = overlayToast, "toast did not coexist with a modal overlay")
	Check(toastUI.Render(), "toast and modal overlay did not render together")
	dialog.Close()
	toastUI.ClearToasts()
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
Local multiline:TUILabel = page.Label("First~nSecond")

Check(ui.Render(), "initial UI did not render")
Check(multiline.Height() = multiline.DefaultStyle().font.LineHeight() * ..
	multiline.DefaultStyle().fontScale * 2, "multiline label did not reserve both lines")
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

RunToastTests(ui, frame, cancel)

ui.Close()

' Scrolling clips a natural-height child list into a fixed viewport. Selection
' remains semantic and focus traversal keeps off-screen items visible.
Local scrollFrame:TDisplayBuffer = TDisplayBuffer.Create(160, 100, DisplayPixelFormatMono1)
Local scrollUI:TUIContext = TUIContext.CreateWithBuffer(scrollFrame, Null, touch, ..
	TUITheme.Dark(Spleen5x8Font()))
Check(scrollUI <> Null, "could not create scrolling UI")
scrollUI.Theme().screen.background = 0
Local scrollPage:TUIColumn = scrollUI.Root()
Local list:TUIList = scrollPage.List()
list.SetHeight(72)
list.SetAlign(UIAlignStart)
list.OnSelectionChanged(SelectionChanged)
For Local itemIndex:Int = 0 Until 8
	list.Item("Item " + itemIndex)
Next
list.SetSelectedIndex(1)
Check(scrollUI.Render(), "scrolling UI did not render")
Check(list.ContentHeight() > list.Height() And list.MaxScrollY() > 0, ..
	"list content did not overflow its viewport")
Check(list.SelectedIndex() = 1 And selectionChangeCount = 0, ..
	"programmatic list selection emitted a user event")

list.SetScrollY(10000)
scrollUI.Render()
Check(list.ScrollY() = list.MaxScrollY(), "list scroll position was not clamped")
list.SetScrollY(0)
scrollUI.Render()
Local lastItem:TUIListItem = list.ItemAt(7)
Check(scrollUI.SetFocus(lastItem), "off-screen list item could not receive focus")
Check(list.ScrollY() > 0 And lastItem.Y() + lastItem.Height() <= list.Y() + list.Height(), ..
	"focused list item was not scrolled into view")
Check(scrollUI.ActivateFocused(), "focused list item did not activate")
Check(list.SelectedIndex() = 7 And selectionCallbackCount = 1, ..
	"focused list selection did not invoke its callback")
Check(selectionChangeCount = 1 And selectionEventSource = list And selectionEventIndex = 7, ..
	"list selection event was not emitted")
Check(scrollUI.AdjustFocused(-1) And list.SelectedIndex() = 6 And ..
	scrollUI.FocusedWidget() = list.ItemAt(6), "list selection did not adjust through focus")

' Boundary navigation retains the list focus instead of leaving it on the
' button or other control which initiated the move.
list.SetSelectedIndex(0)
Check(scrollUI.SetFocus(list.ItemAt(0)), "first list item could not receive focus")
Check(Not list.MoveSelection(-1) And scrollUI.FocusedWidget() = list.ItemAt(0), ..
	"list lost focus when moving before its first item")
list.SetSelectedIndex(7)
Check(scrollUI.SetFocus(list.ItemAt(7)), "last list item could not receive focus")
Check(Not list.MoveSelection(1) And scrollUI.FocusedWidget() = list.ItemAt(7), ..
	"list lost focus when moving after its last item")

' Momentum is optional and advances from the measured drag velocity without
' requiring floating-point arithmetic.
list.SetScrollY(0)
scrollUI.Render()
Check(Not list.MomentumEnabled(), "list momentum was not disabled by default")
list.SetMomentumEnabled(True)
Check(list.MomentumEnabled(), "list momentum could not be enabled")
list._BeginDrag(1000)
list._DragBy(20, 1020)
list._EndDrag(1020)
Local scrollBeforeMomentum:Int = list.ScrollY()
list._UpdateMomentum(1070)
Check(list.ScrollY() > scrollBeforeMomentum, "list momentum did not continue a released drag")
list.SetMomentumEnabled(False)
Check(Not list.MomentumEnabled(), "list momentum could not be disabled")

' A drag beginning on an item scrolls instead of selecting it on release.
list.SetScrollY(0)
scrollUI.Render()
Local selectionBeforeDrag:Int = list.SelectedIndex()
touch.x = list.X() + list.Width() / 2
touch.y = list.ItemAt(2).Y() + list.ItemAt(2).Height() / 2
touch.count = 1
PollSystem()
touch.y :- 28
PollSystem()
Check(list.ScrollY() > 0, "touch drag did not scroll the list")
touch.count = 0
PollSystem()
PollSystem()
Check(list.SelectedIndex() = selectionBeforeDrag, "scroll gesture activated a list item")

scrollUI.Close()
RunTabTests(touch)
RunComboTests(touch)
RunPopupMenuTests(touch)
RunChoiceWidgetTests(touch)
RunDialogTests(touch)
RunWrappedLabelTests(touch)
RunDecimalStepperTests(touch)
touch.StopEvents()
Print "embedded UI conformance: PASS"
