SuperStrict

Framework BRL.StandardIO
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Drivers.Display.Fonts.Spleen.Size6x12
Import Embedded.Drivers.Display.Fonts.Spleen.Size8x16
Import Embedded.Drivers.Display.Fonts.Spleen.Size12x24
Import Embedded.Drivers.Display.Fonts.Spleen.Size16x32
Import Embedded.Drivers.Display.Fonts.Spleen.Size32x64

Function CheckFont(font:TBitmapFont, lineHeight:Int, minimumGlyphs:Int, name:String)
	If Not font Then RuntimeError name + " did not load"
	If font.LineHeight() <> lineHeight Then RuntimeError name + " has the wrong line height"
	If font.GlyphCount() < minimumGlyphs Then RuntimeError name + " is missing glyphs"
	If Not font.HasGlyph(Asc("A")) Or Not font.HasGlyph(Asc("?")) Then ..
		RuntimeError name + " is missing basic glyphs"
End Function

CheckFont Spleen5x8Font(), 8, 400, "Spleen 5x8"
CheckFont Spleen6x12Font(), 12, 500, "Spleen 6x12"
CheckFont Spleen8x16Font(), 16, 900, "Spleen 8x16"
CheckFont Spleen12x24Font(), 24, 900, "Spleen 12x24"
CheckFont Spleen16x32Font(), 32, 900, "Spleen 16x32"
CheckFont Spleen32x64Font(), 64, 900, "Spleen 32x64"

Print "embedded Spleen font-family conformance: PASS"
