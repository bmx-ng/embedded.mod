SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Graphics2D

Type TTestDisplay Extends TDisplay
	Field presentations:Int
	Field discardPresentations:Int
	Field result:Int = 1
	Field lastX:Int
	Field lastY:Int
	Field lastWidth:Int
	Field lastHeight:Int

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
				x >= 0 And y >= 0 And width > 0 And height > 0 And ..
				x + width <= 16 And y + height <= 16 Then
			presentations :+ 1
			lastX = x
			lastY = y
			lastWidth = width
			lastHeight = height
		End If
		Return result
	End Method

	Method PresentPixelsDiscard:Int(pixels:Byte Ptr, stride:Int, format:Int)
		discardPresentations :+ 1
		Return PresentPixels(pixels, stride, format, 0, 0, Width(), Height())
	End Method

	Method SetEnabled:Int(enabled:Int)
		Return True
	End Method
End Type

Local passed:Int = True
Local frame:TDisplayBuffer = TDisplayBuffer.Create(16, 16, DisplayPixelFormatMono1)
Local display:TTestDisplay = New TTestDisplay
Local graphics:TEmbedded2DContext = TEmbedded2DContext.Create(frame, display)

' Packed Mono1 spans preserve the unmodified edge bits for both set and clear.
frame.FillRect(3, 1, 10, 2, $ffffff)
passed :& frame.Pixel(2, 1) = 0 And frame.Pixel(3, 1) = 1 And frame.Pixel(12, 2) = 1
passed :& frame.Pixel(13, 2) = 0
frame.Clear($ffffff)
frame.FillRect(3, 1, 10, 2, 0)
passed :& frame.Pixel(2, 1) = 1 And frame.Pixel(3, 1) = 0 And frame.Pixel(12, 2) = 0
passed :& frame.Pixel(13, 2) = 1
frame.Clear()

' Native arbitrary lines preserve Bresenham coverage and silently clip endpoints.
frame.DrawLine(-2, -2, 4, 4)
passed :& frame.Pixel(0, 0) = 1 And frame.Pixel(1, 1) = 1 And frame.Pixel(4, 4) = 1
passed :& frame.Pixel(0, 1) = 0 And frame.Pixel(5, 5) = 0
frame.DrawLine(4, 4, 0, 0, 0)
passed :& frame.Pixel(0, 0) = 0 And frame.Pixel(2, 2) = 0 And frame.Pixel(4, 4) = 0

' Native polylines join all supplied points while applying one shared clip.
Local polyX:Int[] = New Int[3]
Local polyY:Int[] = New Int[3]
polyX[0] = -2; polyY[0] = 2
polyX[1] = 4; polyY[1] = 2
polyX[2] = 4; polyY[2] = 6
frame.DrawPolyline(Varptr polyX[0], Varptr polyY[0], 3, 0, 0, 1, 1, 5, 5)
passed :& frame.Pixel(1, 2) And frame.Pixel(4, 2) And frame.Pixel(4, 5)
passed :& Not frame.Pixel(0, 2) And Not frame.Pixel(4, 6)
frame.Clear()

' Packed transparent masks support scaled drawing with destination clipping.
Local maskBits:Byte[] = New Byte[1]
maskBits[0] = $a0
frame.DrawMono1Mask(Varptr maskBits[0], 1, 3, 1, 0, 0, 2, 1, 1, 4, 1)
passed :& Not frame.Pixel(0, 0) And Not frame.Pixel(1, 0)
passed :& frame.Pixel(1, 1) And Not frame.Pixel(2, 1) And Not frame.Pixel(3, 1)
passed :& frame.Pixel(4, 1) And Not frame.Pixel(5, 1)
frame.Clear()

' Packed circle outlines retain midpoint geometry and destination clipping.
frame.DrawCircle(4, 4, 3, 2, 2, 5, 5)
passed :& frame.Pixel(4, 1) = 0 And frame.Pixel(4, 2) = 0
passed :& frame.Pixel(4, 7) = 0 And frame.Pixel(1, 4) = 0
passed :& frame.Pixel(7, 4) = 0 And frame.Pixel(6, 6)
frame.Clear()

' Packed filled circles retain span geometry and destination clipping.
frame.FillCircle(4, 4, 3, 2, 2, 5, 5)
passed :& frame.Pixel(4, 2) And frame.Pixel(2, 4) And frame.Pixel(6, 4)
passed :& frame.Pixel(4, 6) And frame.Pixel(2, 2) And frame.Pixel(6, 2)
passed :& Not frame.Pixel(1, 4) And Not frame.Pixel(7, 4)
frame.Clear()

' Native arcs draw inward from their outer radius and respect destination clipping.
frame.DrawArc(8, 8, 5, 180, 90, 2, 0, 0, 16, 16)
passed :& frame.Pixel(3, 8) And frame.Pixel(4, 8)
passed :& frame.Pixel(8, 3) And frame.Pixel(8, 4)
passed :& Not frame.Pixel(13, 8) And Not frame.Pixel(8, 13)
frame.Clear()

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
rotatedGraphics.DrawArc(3, 5, 2, 0, 90, 1)
passed :& rotated.Pixel(4, 5) And rotated.Pixel(2, 3)
passed :& Not rotated.Pixel(4, 1)
rotated.Clear()
polyX[0] = 0; polyY[0] = 0
polyX[1] = 2; polyY[1] = 0
polyX[2] = 2; polyY[2] = 2
rotatedGraphics.DrawPolyline(polyX, polyY)
passed :& rotated.Pixel(9, 0) And rotated.Pixel(9, 2) And rotated.Pixel(7, 2)
passed :& Not rotated.Pixel(7, 0)
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

' Common UI primitives use integer, allocation-free rasterisation and the same
' clipping and transform path as the original line and rectangle operations.
Local shapeFrame:TDisplayBuffer = TDisplayBuffer.Create(24, 20, DisplayPixelFormatMono1)
Local shapeGraphics:TEmbedded2DContext = TEmbedded2DContext.Create(shapeFrame)
shapeGraphics.SetColor(255, 255, 255)
shapeGraphics.DrawCircle(5, 5, 3)
passed :& shapeFrame.Pixel(8, 5) = 1 And shapeFrame.Pixel(5, 2) = 1
passed :& shapeFrame.Pixel(5, 5) = 0
shapeFrame.Clear()
shapeGraphics.FillCircle(5, 5, 3)
passed :& shapeFrame.Pixel(5, 5) = 1 And shapeFrame.Pixel(5, 2) = 1
passed :& shapeFrame.Pixel(2, 2) = 0
shapeFrame.Clear()
shapeGraphics.DrawEllipse(8, 5, 5, 2)
passed :& shapeFrame.Pixel(3, 5) = 1 And shapeFrame.Pixel(13, 5) = 1
passed :& shapeFrame.Pixel(8, 3) = 1 And shapeFrame.Pixel(8, 7) = 1
shapeFrame.Clear()
shapeGraphics.FillEllipse(8, 5, 5, 2)
passed :& shapeFrame.Pixel(8, 5) = 1 And shapeFrame.Pixel(4, 5) = 1
passed :& shapeFrame.Pixel(3, 3) = 0
shapeFrame.Clear()
shapeGraphics.FillTriangle(2, 2, 10, 2, 6, 9)
passed :& shapeFrame.Pixel(6, 2) = 1 And shapeFrame.Pixel(6, 6) = 1
passed :& shapeFrame.Pixel(1, 2) = 0 And shapeFrame.Pixel(2, 8) = 0
shapeFrame.Clear()
shapeGraphics.DrawTriangle(2, 2, 10, 2, 6, 9)
passed :& shapeFrame.Pixel(6, 2) = 1 And shapeFrame.Pixel(6, 9) = 1
passed :& shapeFrame.Pixel(6, 5) = 0
shapeFrame.Clear()
shapeGraphics.FillRoundRect(2, 2, 12, 8, 3)
passed :& shapeFrame.Pixel(2, 2) = 0 And shapeFrame.Pixel(13, 2) = 0
passed :& shapeFrame.Pixel(5, 2) = 1 And shapeFrame.Pixel(2, 5) = 1
' Both centre rows must join the rounded halves. A missing lower centre row
' leaves the bottom of short badges looking like a detached strip.
passed :& shapeFrame.Pixel(7, 5) = 1 And shapeFrame.Pixel(2, 6) = 1
passed :& shapeFrame.Pixel(7, 6) = 1
shapeFrame.Clear()
shapeGraphics.DrawRoundRect(2, 2, 12, 8, 3)
passed :& shapeFrame.Pixel(5, 2) = 1 And shapeFrame.Pixel(2, 5) = 1
passed :& shapeFrame.Pixel(7, 5) = 0

' Wrapped text measurement, alignment, and ellipsis share the font's native
' glyph advances without constructing substrings while drawing.
Local textFrame:TDisplayBuffer = TDisplayBuffer.Create(40, 32, DisplayPixelFormatMono1)
Local textGraphics:TEmbedded2DContext = TEmbedded2DContext.Create(textFrame)
textGraphics.SetFont(Spleen5x8Font())
textGraphics.SetColor(255, 255, 255)
Local measuredWidth:Int
Local measuredHeight:Int
passed :& textGraphics.TextBoxSize("ONE TWO THREE", 25, measuredWidth, measuredHeight) = 3
passed :& measuredWidth = 25 And measuredHeight = 24
passed :& textGraphics.DrawTextBox("A A A", 0, 0, 5, 24) = 3
passed :& textFrame.Pixel(1, 1) = 1 And textFrame.Pixel(1, 9) = 1
passed :& textFrame.Pixel(1, 17) = 1
textFrame.Clear()
passed :& textGraphics.DrawTextBox("A", 0, 0, 15, 8, TextAlignCenter) = 1
passed :& textFrame.Pixel(6, 1) = 1 And textFrame.Pixel(1, 1) = 0
textFrame.Clear()
passed :& textGraphics.DrawTextBox("A", 0, 0, 15, 8, TextAlignRight) = 1
passed :& textFrame.Pixel(11, 1) = 1 And textFrame.Pixel(6, 1) = 0
textFrame.Clear()
passed :& textGraphics.DrawTextBox("AAAA", 0, 0, 15, 8, TextAlignLeft, 1, True) = 1
passed :& textFrame.Pixel(1, 1) = 0

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

' Input conversion follows the exact drawing transform, including origin,
' viewport clipping, nested quarter turns, and root display rotation.
Local screenX:Int
Local screenY:Int
Local localX:Int
Local localY:Int
viewGraphics.SetOrigin(1, 1)
viewGraphics.ViewToScreen(2, 1, screenX, screenY)
passed :& screenX = 3 And screenY = 2
viewGraphics.ScreenToView(screenX, screenY, localX, localY)
passed :& localX = 2 And localY = 1
viewGraphics.SetOrigin(0, 0)

passed :& viewGraphics.BeginView(2, 1, 4, 3, 90)
viewGraphics.ViewToScreen(0, 0, screenX, screenY)
passed :& screenX = 5 And screenY = 1
viewGraphics.ScreenToView(2, 3, localX, localY)
passed :& localX = 2 And localY = 3
passed :& viewGraphics.PointInView(2, 3)
passed :& Not viewGraphics.PointInView(1, 3)
viewGraphics.SetViewport(1, 1, 1, 2)
passed :& viewGraphics.PointInView(4, 2)
passed :& Not viewGraphics.PointInView(5, 1)
passed :& viewGraphics.EndView()

passed :& viewGraphics.SetRotation(90)
viewGraphics.ViewToScreen(2, 3, screenX, screenY)
passed :& screenX = 6 And screenY = 2
viewGraphics.ScreenToView(screenX, screenY, localX, localY)
passed :& localX = 2 And localY = 3
passed :& viewGraphics.BeginView(1, 2, 3, 2, 270)
viewGraphics.ViewToScreen(0, 0, screenX, screenY)
passed :& screenX = 6 And screenY = 1
viewGraphics.ScreenToView(screenX, screenY, localX, localY)
passed :& localX = 0 And localY = 0
passed :& viewGraphics.EndView()
passed :& viewGraphics.SetRotation(0)

viewFrame.Clear()
passed :& viewGraphics.BeginView(2, 1, 4, 3, 90)
viewGraphics.FillCircle(1, 1, 1)
passed :& viewFrame.Pixel(4, 2) = 1 And viewFrame.Pixel(5, 2) = 1
passed :& viewGraphics.EndView()

' Dirty tracking accumulates conservative physical framebuffer bounds while
' respecting viewport clipping, root rotation, and nested view transforms.
Local dirtyFrame:TDisplayBuffer = TDisplayBuffer.Create(16, 16, DisplayPixelFormatMono1)
Local dirtyDisplay:TTestDisplay = New TTestDisplay
Local dirtyGraphics:TEmbedded2DContext = TEmbedded2DContext.Create(dirtyFrame, dirtyDisplay)
Local dirtyX:Int
Local dirtyY:Int
Local dirtyWidth:Int
Local dirtyHeight:Int
passed :& Not dirtyGraphics.DirtyTracking()
dirtyGraphics.SetDirtyTracking(True)
passed :& dirtyGraphics.DirtyTracking()
passed :& Not dirtyGraphics.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
dirtyGraphics.SetViewport(2, 3, 5, 4)
dirtyGraphics.FillRect(-20, -20, 40, 40)
passed :& dirtyGraphics.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 2 And dirtyY = 3 And dirtyWidth = 5 And dirtyHeight = 4
passed :& dirtyGraphics.PresentDirty() = 1 And dirtyDisplay.presentations = 1
passed :& dirtyDisplay.lastX = 2 And dirtyDisplay.lastY = 3
passed :& dirtyDisplay.lastWidth = 5 And dirtyDisplay.lastHeight = 4
passed :& Not dirtyGraphics.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyGraphics.PresentDirty() = 1 And dirtyDisplay.presentations = 1

dirtyGraphics.ResetViewport()
dirtyGraphics.Plot(4, 5)
dirtyGraphics.Plot(7, 9)
passed :& dirtyGraphics.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 4 And dirtyY = 5 And dirtyWidth = 4 And dirtyHeight = 5
passed :& dirtyGraphics.DirtyRegionCount() = 2
passed :& dirtyGraphics.DirtyRegion(0, dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 4 And dirtyY = 5 And dirtyWidth = 1 And dirtyHeight = 1
passed :& dirtyGraphics.DirtyRegion(1, dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 7 And dirtyY = 9 And dirtyWidth = 1 And dirtyHeight = 1
dirtyGraphics.ResetDirty()
dirtyGraphics.InvalidateRect(6, 7, 3, 2)
passed :& dirtyGraphics.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 6 And dirtyY = 7 And dirtyWidth = 3 And dirtyHeight = 2
dirtyDisplay.result = DisplayErrorGeneric
passed :& dirtyGraphics.PresentDirty() = DisplayErrorGeneric
passed :& dirtyGraphics.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 6 And dirtyY = 7 And dirtyWidth = 3 And dirtyHeight = 2
dirtyDisplay.result = 1
passed :& dirtyGraphics.Present() = 1 And dirtyDisplay.presentations = 3
passed :& dirtyDisplay.lastX = 0 And dirtyDisplay.lastY = 0
passed :& dirtyDisplay.lastWidth = 16 And dirtyDisplay.lastHeight = 16
passed :& Not dirtyGraphics.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
dirtyGraphics.Plot(1, 1)
passed :& dirtyGraphics.PresentDiscard() = 1 And dirtyDisplay.presentations = 4
passed :& dirtyDisplay.discardPresentations = 1
passed :& Not dirtyGraphics.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)

' Distant changes remain separate and are submitted through one logical
' presentation. Touching changes merge, while excessive fragmentation falls
' back to one complete-frame rectangle without allocating.
Local regionFrame:TDisplayBuffer = TDisplayBuffer.Create(16, 16, DisplayPixelFormatMono1)
Local regionDisplay:TTestDisplay = New TTestDisplay
Local regionGraphics:TEmbedded2DContext = TEmbedded2DContext.Create(regionFrame, regionDisplay)
regionGraphics.SetDirtyTracking(True)
regionGraphics.InvalidateRect(1, 1, 2, 2)
regionGraphics.InvalidateRect(12, 12, 2, 2)
passed :& regionGraphics.DirtyRegionCount() = 2
passed :& regionGraphics.PresentDirty() = 1 And regionDisplay.presentations = 2
passed :& regionDisplay.lastX = 12 And regionDisplay.lastY = 12
passed :& regionDisplay.lastWidth = 2 And regionDisplay.lastHeight = 2
regionGraphics.InvalidateRect(1, 1, 2, 2)
regionGraphics.InvalidateRect(3, 1, 2, 2)
passed :& regionGraphics.DirtyRegionCount() = 1
passed :& regionGraphics.DirtyRegion(0, dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 1 And dirtyY = 1 And dirtyWidth = 4 And dirtyHeight = 2
regionGraphics.ResetDirty()
regionGraphics.InvalidateRect(0, 0, 1, 1)
regionGraphics.InvalidateRect(3, 0, 1, 1)
regionGraphics.InvalidateRect(6, 0, 1, 1)
regionGraphics.InvalidateRect(9, 0, 1, 1)
regionGraphics.InvalidateRect(12, 0, 1, 1)
regionGraphics.InvalidateRect(0, 3, 1, 1)
regionGraphics.InvalidateRect(3, 3, 1, 1)
regionGraphics.InvalidateRect(6, 3, 1, 1)
regionGraphics.InvalidateRect(9, 3, 1, 1)
passed :& regionGraphics.DirtyRegionCount() = 1
passed :& regionGraphics.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 0 And dirtyY = 0 And dirtyWidth = 16 And dirtyHeight = 16

Local dirtyRotatedFrame:TDisplayBuffer = TDisplayBuffer.Create(10, 6, DisplayPixelFormatMono1)
Local dirtyRotated:TEmbedded2DContext = TEmbedded2DContext.Create(dirtyRotatedFrame)
dirtyRotated.SetDirtyTracking(True)
passed :& dirtyRotated.SetRotation(90)
dirtyRotated.FillRect(1, 2, 2, 3)
passed :& dirtyRotated.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 5 And dirtyY = 1 And dirtyWidth = 3 And dirtyHeight = 2
dirtyRotated.ResetDirty()
passed :& dirtyRotated.SetRotation(0)
passed :& dirtyRotated.BeginView(2, 1, 4, 3, 90)
dirtyRotated.FillRect(0, 0, 2, 1)
passed :& dirtyRotated.DirtyRect(dirtyX, dirtyY, dirtyWidth, dirtyHeight)
passed :& dirtyX = 5 And dirtyY = 1 And dirtyWidth = 1 And dirtyHeight = 2
passed :& dirtyRotated.EndView()

If passed Then
	Print "Embedded Graphics2D conformance test passed"
Else
	Print "Embedded Graphics2D conformance test failed"
End If
