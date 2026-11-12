SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Graphics2D

Type TTestDisplay Extends TDisplay
	Field presentations:Int

	Method Width:Int()
		Return 16
	End Method

	Method Height:Int()
		Return 16
	End Method

	Method PreferredPixelFormat:Int()
		Return DisplayPixelFormatMono1
	End Method

	Method PresentPixels:Int(pixels:Byte Ptr, stride:Int, format:Int, ..
			x:Int, y:Int, width:Int, height:Int)
		If pixels And stride = 2 And format = DisplayPixelFormatMono1 And ..
				x = 0 And y = 0 And width = 16 And height = 16 Then presentations :+ 1
		Return 1
	End Method

	Method SetEnabled:Int(enabled:Int)
		Return True
	End Method
End Type

Local passed:Int = True
Local frame:TDisplayBuffer = TDisplayBuffer.Create(16, 16, DisplayPixelFormatMono1)
Local display:TTestDisplay = New TTestDisplay
Local graphics:TEmbedded2DContext = TEmbedded2DContext.Create(frame, display)

graphics.SetViewport(2, 2, 8, 8)
graphics.SetColor(300, -1, 128)
passed :& graphics.Color() = $ff0080
graphics.SetColor(255, 255, 255)
graphics.FillRect(-10, -10, 30, 30)
passed :& frame.Pixel(2, 2) = 1 And frame.Pixel(9, 9) = 1
passed :& frame.Pixel(1, 2) = 0 And frame.Pixel(10, 9) = 0

graphics.SetClsColor(0, 0, 0)
graphics.Cls()
passed :& frame.Pixel(2, 2) = 0 And frame.Pixel(9, 9) = 0

graphics.SetOrigin(3, 3)
graphics.DrawLine(-10, 0, 20, 0)
passed :& frame.Pixel(2, 3) = 1 And frame.Pixel(9, 3) = 1
passed :& frame.Pixel(1, 3) = 0 And frame.Pixel(10, 3) = 0

frame.Clear()
graphics.SetOrigin(0, 0)
graphics.SetViewport(2, 2, 3, 5)
graphics.SetFont(Spleen5x8Font())
graphics.DrawText("A", 2, 2)
passed :& frame.Pixel(3, 3) = 1 And frame.Pixel(4, 3) = 1
passed :& frame.Pixel(5, 3) = 0 And frame.Pixel(3, 6) = 1 And frame.Pixel(3, 7) = 0
passed :& graphics.TextWidth("ABC") = 15 And graphics.FontHeight() = 8

graphics.ResetViewport()
passed :& graphics.Present() = 1 And display.presentations = 1

frame.Clear()
SetRenderTarget(frame, display)
SetFont(Spleen5x8Font())
SetColor 255, 255, 255
SetOrigin 1, 1
Plot 0, 0
DrawRect 2, 2, 4, 4
passed :& frame.Pixel(1, 1) = 1 And frame.Pixel(3, 3) = 1
passed :& frame.Pixel(6, 6) = 1 And Present() = 1

' Quarter-turns expose logical dimensions and rotate all drawing through the
' same integer coordinate mapping.
Local rotated:TDisplayBuffer = TDisplayBuffer.Create(10, 6, DisplayPixelFormatMono1)
Local rotatedGraphics:TEmbedded2DContext = TEmbedded2DContext.Create(rotated)
passed :& rotatedGraphics.SetRotation(90)
passed :& rotatedGraphics.Rotation() = 90 And rotatedGraphics.Width() = 6 And rotatedGraphics.Height() = 10
rotatedGraphics.Plot(0, 0)
rotatedGraphics.Plot(5, 9)
passed :& rotated.Pixel(9, 0) = 1 And rotated.Pixel(0, 5) = 1
rotatedGraphics.SetColor(255, 255, 255)
rotatedGraphics.FillRect(1, 2, 2, 3)
passed :& rotated.Pixel(5, 1) = 1 And rotated.Pixel(7, 2) = 1
rotated.Clear()
rotatedGraphics.SetFont(Spleen5x8Font())
rotatedGraphics.DrawText("A", 0, 0)
passed :& rotated.Pixel(8, 1) = 1 And rotated.Pixel(8, 2) = 1
rotated.Clear()
passed :& rotatedGraphics.SetRotation(180)
rotatedGraphics.Plot(0, 0)
rotatedGraphics.Plot(9, 5)
passed :& rotated.Pixel(9, 5) = 1 And rotated.Pixel(0, 0) = 1
rotated.Clear()
passed :& rotatedGraphics.SetRotation(-90) And rotatedGraphics.Rotation() = 270
rotatedGraphics.Plot(0, 0)
rotatedGraphics.Plot(5, 9)
passed :& rotated.Pixel(0, 5) = 1 And rotated.Pixel(9, 0) = 1
passed :& Not rotatedGraphics.SetRotation(45) And rotatedGraphics.Rotation() = 270

' Device orientation establishes rotation zero; drawing rotation remains relative.
passed :& display.SetOrientation(90)
rotatedGraphics.SetRotation(0)
rotatedGraphics.SetDisplay(display)
passed :& rotatedGraphics.Orientation() = 90 And rotatedGraphics.EffectiveRotation() = 90
passed :& rotatedGraphics.Width() = 6 And rotatedGraphics.Height() = 10
passed :& rotatedGraphics.SetDisplayOrientation(180)
passed :& display.Orientation() = 180 And rotatedGraphics.EffectiveRotation() = 180
passed :& rotatedGraphics.Width() = 10 And rotatedGraphics.Height() = 6
rotatedGraphics.SetRotation(90)
passed :& rotatedGraphics.EffectiveRotation() = 270

' The state stack is fixed-depth and restores all mutable drawing state.
Local stateFrame:TDisplayBuffer = TDisplayBuffer.Create(10, 6, DisplayPixelFormatMono1)
Local stateGraphics:TEmbedded2DContext = TEmbedded2DContext.Create(stateFrame)
stateGraphics.SetColorValue($123456)
stateGraphics.SetClsColorValue($654321)
stateGraphics.SetOrigin(2, 3)
stateGraphics.SetViewport(1, 1, 7, 4)
passed :& stateGraphics.PushState()
stateGraphics.SetColorValue($ffffff)
stateGraphics.SetClsColorValue(0)
stateGraphics.SetOrigin(0, 0)
stateGraphics.ResetViewport()
passed :& stateGraphics.PopState()
passed :& stateGraphics.Color() = $123456 And stateGraphics.ClsColor() = $654321
passed :& stateGraphics.OriginX() = 2 And stateGraphics.OriginY() = 3
passed :& stateGraphics.ViewportX() = 1 And stateGraphics.ViewportY() = 1
passed :& stateGraphics.ViewportWidth() = 7 And stateGraphics.ViewportHeight() = 4
passed :& Not stateGraphics.PopState()
For Local depth:Int = 0 Until EmbeddedGraphicsStateMaximum
	passed :& stateGraphics.PushState()
Next
passed :& Not stateGraphics.PushState() And stateGraphics.StateDepth() = EmbeddedGraphicsStateMaximum
For Local depth:Int = 0 Until EmbeddedGraphicsStateMaximum
	passed :& stateGraphics.PopState()
Next

' Local views translate and rotate into their parent without owning another buffer.
Local viewFrame:TDisplayBuffer = TDisplayBuffer.Create(10, 6, DisplayPixelFormatMono1)
Local viewGraphics:TEmbedded2DContext = TEmbedded2DContext.Create(viewFrame)
viewGraphics.SetColor(255, 255, 255)
passed :& viewGraphics.BeginView(2, 1, 4, 3)
passed :& viewGraphics.Width() = 4 And viewGraphics.Height() = 3 And viewGraphics.ViewDepth() = 1
viewGraphics.Plot(0, 0)
viewGraphics.Plot(3, 2)
passed :& viewFrame.Pixel(2, 1) = 1 And viewFrame.Pixel(5, 3) = 1
passed :& viewGraphics.EndView() And viewGraphics.Width() = 10 And viewGraphics.Height() = 6
passed :& Not viewGraphics.EndView()

viewFrame.Clear()
passed :& viewGraphics.BeginView(2, 1, 4, 3, 90)
passed :& viewGraphics.Width() = 3 And viewGraphics.Height() = 4
viewGraphics.Plot(0, 0)
viewGraphics.Plot(2, 3)
passed :& viewFrame.Pixel(5, 1) = 1 And viewFrame.Pixel(2, 3) = 1
passed :& Not viewGraphics.SetRotation(180)
passed :& viewGraphics.EndView()

viewFrame.Clear()
passed :& viewGraphics.BeginView(2, 1, 4, 3, 180)
viewGraphics.Plot(0, 0)
viewGraphics.Plot(3, 2)
passed :& viewFrame.Pixel(5, 3) = 1 And viewFrame.Pixel(2, 1) = 1
passed :& viewGraphics.EndView()

viewFrame.Clear()
passed :& viewGraphics.BeginView(2, 1, 4, 3, 270)
passed :& viewGraphics.Width() = 3 And viewGraphics.Height() = 4
viewGraphics.Plot(0, 0)
viewGraphics.Plot(2, 3)
passed :& viewFrame.Pixel(2, 3) = 1 And viewFrame.Pixel(5, 1) = 1
passed :& viewGraphics.EndView()

' Clearing a complete view affects only its parent rectangle.
viewFrame.Clear($ffffff)
viewGraphics.SetClsColor(0, 0, 0)
passed :& viewGraphics.BeginView(2, 1, 4, 3, 90)
viewGraphics.Cls()
passed :& viewGraphics.EndView()
passed :& viewFrame.Pixel(2, 1) = 0 And viewFrame.Pixel(5, 3) = 0
passed :& viewFrame.Pixel(1, 1) = 1 And viewFrame.Pixel(6, 3) = 1

' A nested view inherits the parent viewport as an exact local clip.
viewFrame.Clear()
passed :& viewGraphics.BeginView(1, 1, 6, 4)
viewGraphics.SetViewport(1, 1, 3, 2)
passed :& viewGraphics.BeginView(0, 0, 6, 4)
viewGraphics.SetColor(255, 255, 255)
viewGraphics.Plot(0, 0)
viewGraphics.Plot(1, 1)
viewGraphics.Plot(4, 3)
passed :& viewFrame.Pixel(1, 1) = 0 And viewFrame.Pixel(2, 2) = 1
passed :& viewFrame.Pixel(5, 4) = 0
passed :& viewGraphics.EndView() And viewGraphics.EndView()

If passed Then
	Print "Embedded Graphics2D conformance test passed"
Else
	Print "Embedded Graphics2D conformance test failed"
End If
