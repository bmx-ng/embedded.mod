SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen5x8
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
passed :& frame.Pixel(5, 3) = 0 And frame.Pixel(3, 7) = 1
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

If passed Then
	Print "Embedded Graphics2D conformance test passed"
Else
	Print "Embedded Graphics2D conformance test failed"
End If
