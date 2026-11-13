?
SuperStrict

' Small build fixture proving that a passive UI has no touch dependency.

Framework BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.UI

Local frame:TDisplayBuffer = TDisplayBuffer.Create(96, 64, DisplayPixelFormatMono1)
Local ui:TUIContext = TUIContext.CreateDisplayOnlyWithBuffer(frame, Null, ..
	TUITheme.Dark(Spleen5x8Font()))
If Not ui Then RuntimeError "could not create display-only UI"

Local page:TUIColumn = ui.Root()
page.SetPadding(2)
Local card:TUICard = page.Card("Sensor")
card.Label("Temperature")
card.ProgressBar(-20, 60, 21)

If Not ui.Render() Then RuntimeError "display-only UI did not render"
ui.Close()
Print "embedded UI display-only: PASS"
?
