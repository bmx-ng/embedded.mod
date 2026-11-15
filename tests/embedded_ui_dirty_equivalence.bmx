SuperStrict

' Dirty-region rendering must be byte-identical to a forced full redraw.

Framework BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Runtime.Memory
Import Embedded.UI

Function Check(value:Int, message:String)
	If Not value Then RuntimeError message
End Function

Type TRenderFixture
	Field frame:TDisplayBuffer
	Field ui:TUIContext
	Field label:TUILabel
	Field status:TUIStatusIndicator
	Field progress:TUIProgressBar

	Function Create:TRenderFixture(format:Int)
		Local fixture:TRenderFixture = New TRenderFixture
		fixture.frame = TDisplayBuffer.Create(96, 64, format)
		fixture.ui = TUIContext.CreateDisplayOnlyWithBuffer(fixture.frame, Null, ..
			TUITheme.Dark(Spleen5x8Font()))
		If Not fixture.ui Then Return Null
		Local page:TUIColumn = fixture.ui.Root()
		page.SetPadding(3)
		page.SetGap(3)
		fixture.label = page.Label("Ready")
		fixture.status = page.StatusIndicator("Offline", False)
		fixture.progress = page.ProgressBar(0, 100, 20)
		fixture.progress.SetGrow(1)
		Return fixture
	End Function

	Method Close()
		If ui Then ui.Close()
		ui = Null
		frame = Null
		label = Null
		status = Null
		progress = Null
	End Method
End Type

Function CheckBuffers(dirty:TDisplayBuffer, complete:TDisplayBuffer, phase:String)
	Check(dirty.Size() = complete.Size(), phase + ": framebuffer sizes differ")
	Local dirtyPixels:Byte Ptr = dirty.Pixels()
	Local completePixels:Byte Ptr = complete.Pixels()
	For Local index:Int = 0 Until dirty.Size()
		Check(dirtyPixels[index] = completePixels[index], ..
			phase + ": dirty rendering differs at byte " + index)
	Next
End Function

Function RenderPhase(dirty:TRenderFixture, complete:TRenderFixture, phase:String)
	Check(dirty.ui.Render(), phase + ": dirty render did not repaint")
	complete.ui.InvalidateAll()
	Check(complete.ui.Render(), phase + ": complete render did not repaint")
	CheckBuffers(dirty.frame, complete.frame, phase)
End Function

Function RunFormat(format:Int, name:String)
	Local dirty:TRenderFixture = TRenderFixture.Create(format)
	Local complete:TRenderFixture = TRenderFixture.Create(format)
	Check(dirty <> Null And complete <> Null, name + ": could not create fixtures")
	RenderPhase(dirty, complete, name + " initial")

	dirty.label.SetText("Busy")
	complete.label.SetText("Busy")
	dirty.status.SetText("Online")
	complete.status.SetText("Online")
	dirty.status.SetActive(True)
	complete.status.SetActive(True)
	dirty.progress.SetValue(75)
	complete.progress.SetValue(75)
	RenderPhase(dirty, complete, name + " values")

	dirty.label.SetVisible(False)
	complete.label.SetVisible(False)
	dirty.status.SetText("Up")
	complete.status.SetText("Up")
	RenderPhase(dirty, complete, name + " reflow")

	dirty.label.SetText("Stable")
	complete.label.SetText("Stable")
	dirty.label.SetVisible(True)
	complete.label.SetVisible(True)
	dirty.progress.SetValue(5)
	complete.progress.SetValue(5)
	RenderPhase(dirty, complete, name + " restore")

	dirty.Close()
	complete.Close()
End Function

RunFormat(DisplayPixelFormatMono1, "mono1")
CollectObjects()
RunFormat(DisplayPixelFormatRGB565, "rgb565")
Print "embedded UI dirty equivalence: PASS"
