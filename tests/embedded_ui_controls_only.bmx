?
SuperStrict

' Build fixture proving controls can be used with physical input but no touch.

Framework BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.UI
Import Embedded.UI.Controls

Local frame:TDisplayBuffer = TDisplayBuffer.Create(96, 64, DisplayPixelFormatMono1)
Local ui:TUIContext = TUIContext.CreateDisplayOnlyWithBuffer(frame, Null, ..
	TUITheme.Dark(Spleen5x8Font()))
If Not ui Then RuntimeError "could not create controls-only UI"

Local page:TUIColumn = ui.Root()
page.SetPadding(2)
Local enabled:TUICheckBox = page.CheckBox("Enabled", True)
Local apply:TUIButton = page.Button("Apply")

If Not UIControlsAvailable() Then RuntimeError "control provider was not installed"
If Not ui.SetFocus(enabled) Then RuntimeError "could not focus checkbox"
If Not ui.ActivateFocused() Then RuntimeError "could not activate checkbox"
If enabled.Checked() Then RuntimeError "checkbox did not activate"
If Not ui.SetFocus(apply) Then RuntimeError "could not focus button"
If Not ui.Render() Then RuntimeError "controls-only UI did not render"

ui.Close()
Print "embedded UI controls-only: PASS"
?
