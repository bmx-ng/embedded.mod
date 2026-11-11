SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Font
Import Embedded.Drivers.Display.Fonts.Spleen5x8

Local passed:Int = True
Local font:TBitmapFont = Spleen5x8Font()
passed :& font <> Null
passed :& font.GlyphCount() = 472
passed :& font.Ascent() = 7 And font.Descent() = 1 And font.LineHeight() = 8
passed :& font.HasGlyph(Asc("A"))
passed :& font.HasGlyph($00e4)
passed :& font.HasGlyph($2500)
passed :& font.TextWidth("ABC") = 15
passed :& font.TextWidth("AB~nCDEF") = 20

Local frame:TDisplayBuffer = TDisplayBuffer.Create(20, 16, DisplayPixelFormatMono1)
font.DrawText(frame, "A", 0, 0)
passed :& frame.Pixel(1, 1) = 1 And frame.Pixel(2, 1) = 1
passed :& frame.Pixel(0, 2) = 1 And frame.Pixel(3, 2) = 1
passed :& frame.Pixel(0, 1) = 0 And frame.Pixel(4, 2) = 0

frame.Clear()
font.DrawText(frame, "A", 0, 0, $ffffff, 2)
passed :& frame.Pixel(2, 2) = 1 And frame.Pixel(5, 3) = 1
passed :& frame.Pixel(0, 2) = 0

If passed Then
	Print "Embedded display font conformance test passed"
Else
	Print "Embedded display font conformance test failed"
End If
