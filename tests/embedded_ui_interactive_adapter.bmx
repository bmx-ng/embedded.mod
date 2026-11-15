?
SuperStrict

' Companion build fixture measuring the optional touch adapter overhead.

Framework BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Drivers.Touch
Import Embedded.UI
Import Embedded.UI.Interactive

Type TFixtureTouch Extends TTouchDevice
	Method Width:Int() Override
		Return 96
	End Method

	Method Height:Int() Override
		Return 64
	End Method

	Method PollContacts:Int() Override
		Return 0
	End Method

	Method ContactId:Int(index:Int) Override
		Return -1
	End Method

	Method ContactX:Int(index:Int) Override
		Return 0
	End Method

	Method ContactY:Int(index:Int) Override
		Return 0
	End Method
End Type

Local frame:TDisplayBuffer = TDisplayBuffer.Create(96, 64, DisplayPixelFormatMono1)
Local touch:TFixtureTouch = New TFixtureTouch
Local ui:TUIContext = TUITouchInput.CreateContextWithBuffer(frame, Null, touch, ..
	TUITheme.Dark(Spleen5x8Font()))
If Not ui Then RuntimeError "could not create interactive UI"

Local page:TUIColumn = ui.Root()
page.SetPadding(2)
Local card:TUICard = page.Card("Sensor")
card.Label("Temperature")
card.ProgressBar(-20, 60, 21)
card.Button("Refresh")

If Not ui.Render() Then RuntimeError "interactive UI did not render"
ui.Close()
Print "embedded UI interactive adapter: PASS"
?
