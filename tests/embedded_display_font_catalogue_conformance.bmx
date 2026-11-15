SuperStrict

Framework BRL.StandardIO
Import Embedded.Drivers.Display.Font
Import Embedded.Drivers.Display.Fonts.Anakron.Regular8x12
Import Embedded.Drivers.Display.Fonts.Cozette.Regular6x13
Import Embedded.Drivers.Display.Fonts.Scientifica.Regular
Import Embedded.Drivers.Display.Fonts.Scientifica.Bold
Import Embedded.Drivers.Display.Fonts.Scientifica.Italic
Import Embedded.Drivers.Display.Fonts.Tamzen.Regular5x9
Import Embedded.Drivers.Display.Fonts.Tamzen.Bold5x9
Import Embedded.Drivers.Display.Fonts.Tamzen.Regular6x12
Import Embedded.Drivers.Display.Fonts.Tamzen.Bold6x12
Import Embedded.Drivers.Display.Fonts.Tamzen.Regular7x13
Import Embedded.Drivers.Display.Fonts.Tamzen.Bold7x13
Import Embedded.Drivers.Display.Fonts.Tamzen.Regular7x14
Import Embedded.Drivers.Display.Fonts.Tamzen.Bold7x14
Import Embedded.Drivers.Display.Fonts.Tamzen.Regular8x15
Import Embedded.Drivers.Display.Fonts.Tamzen.Bold8x15
Import Embedded.Drivers.Display.Fonts.Tamzen.Regular8x16
Import Embedded.Drivers.Display.Fonts.Tamzen.Bold8x16
Import Embedded.Drivers.Display.Fonts.Tamzen.Regular10x20
Import Embedded.Drivers.Display.Fonts.Tamzen.Bold10x20
Import Embedded.Drivers.Display.Fonts.Terminus.Regular6x12
Import Embedded.Drivers.Display.Fonts.Terminus.Regular8x14
Import Embedded.Drivers.Display.Fonts.Terminus.Bold8x14
Import Embedded.Drivers.Display.Fonts.Terminus.Regular8x16
Import Embedded.Drivers.Display.Fonts.Terminus.Bold8x16
Import Embedded.Drivers.Display.Fonts.Terminus.Regular10x18
Import Embedded.Drivers.Display.Fonts.Terminus.Bold10x18
Import Embedded.Drivers.Display.Fonts.Terminus.Regular10x20
Import Embedded.Drivers.Display.Fonts.Terminus.Bold10x20
Import Embedded.Drivers.Display.Fonts.Terminus.Regular11x22
Import Embedded.Drivers.Display.Fonts.Terminus.Bold11x22
Import Embedded.Drivers.Display.Fonts.Terminus.Regular12x24
Import Embedded.Drivers.Display.Fonts.Terminus.Bold12x24
Import Embedded.Drivers.Display.Fonts.Terminus.Regular14x28
Import Embedded.Drivers.Display.Fonts.Terminus.Bold14x28
Import Embedded.Drivers.Display.Fonts.Terminus.Regular16x32
Import Embedded.Drivers.Display.Fonts.Terminus.Bold16x32

Function CheckFont(font:TBitmapFont, lineHeight:Int, minimumGlyphs:Int, name:String)
	If Not font Then RuntimeError name + " did not load"
	If font.LineHeight() <> lineHeight Then RuntimeError name + " has the wrong line height"
	If font.GlyphCount() < minimumGlyphs Then RuntimeError name + " is missing glyphs"
	If Not font.HasGlyph(Asc("A")) Or Not font.HasGlyph(Asc("?")) Then ..
		RuntimeError name + " is missing basic glyphs"
End Function

CheckFont Anakron8x12Font(), 12, 2000, "ANAKRON 8x12"
CheckFont Cozette6x13Font(), 13, 6000, "Cozette 6x13"
CheckFont ScientificaFont(), 11, 900, "Scientifica regular"
CheckFont ScientificaBoldFont(), 11, 900, "Scientifica bold"
CheckFont ScientificaItalicFont(), 11, 900, "Scientifica italic"

CheckFont Tamzen5x9Font(), 9, 180, "Tamzen 5x9 regular"
CheckFont Tamzen5x9BoldFont(), 9, 180, "Tamzen 5x9 bold"
CheckFont Tamzen6x12Font(), 12, 180, "Tamzen 6x12 regular"
CheckFont Tamzen6x12BoldFont(), 12, 180, "Tamzen 6x12 bold"
CheckFont Tamzen7x13Font(), 13, 180, "Tamzen 7x13 regular"
CheckFont Tamzen7x13BoldFont(), 13, 180, "Tamzen 7x13 bold"
CheckFont Tamzen7x14Font(), 14, 180, "Tamzen 7x14 regular"
CheckFont Tamzen7x14BoldFont(), 14, 180, "Tamzen 7x14 bold"
CheckFont Tamzen8x15Font(), 15, 180, "Tamzen 8x15 regular"
CheckFont Tamzen8x15BoldFont(), 15, 180, "Tamzen 8x15 bold"
CheckFont Tamzen8x16Font(), 16, 180, "Tamzen 8x16 regular"
CheckFont Tamzen8x16BoldFont(), 16, 180, "Tamzen 8x16 bold"
CheckFont Tamzen10x20Font(), 20, 180, "Tamzen 10x20 regular"
CheckFont Tamzen10x20BoldFont(), 20, 180, "Tamzen 10x20 bold"

CheckFont Terminus6x12Font(), 12, 1300, "Terminus 6x12 regular"
CheckFont Terminus8x14Font(), 14, 1300, "Terminus 8x14 regular"
CheckFont Terminus8x14BoldFont(), 14, 1300, "Terminus 8x14 bold"
CheckFont Terminus8x16Font(), 16, 1300, "Terminus 8x16 regular"
CheckFont Terminus8x16BoldFont(), 16, 1300, "Terminus 8x16 bold"
CheckFont Terminus10x18Font(), 18, 1300, "Terminus 10x18 regular"
CheckFont Terminus10x18BoldFont(), 18, 1300, "Terminus 10x18 bold"
CheckFont Terminus10x20Font(), 20, 1300, "Terminus 10x20 regular"
CheckFont Terminus10x20BoldFont(), 20, 1300, "Terminus 10x20 bold"
CheckFont Terminus11x22Font(), 22, 1300, "Terminus 11x22 regular"
CheckFont Terminus11x22BoldFont(), 22, 1300, "Terminus 11x22 bold"
CheckFont Terminus12x24Font(), 24, 1300, "Terminus 12x24 regular"
CheckFont Terminus12x24BoldFont(), 24, 1300, "Terminus 12x24 bold"
CheckFont Terminus14x28Font(), 28, 1300, "Terminus 14x28 regular"
CheckFont Terminus14x28BoldFont(), 28, 1300, "Terminus 14x28 bold"
CheckFont Terminus16x32Font(), 32, 1300, "Terminus 16x32 regular"
CheckFont Terminus16x32BoldFont(), 32, 1300, "Terminus 16x32 bold"

' Exercise the non-ASCII lookup path repeatedly. These calls populate and then
' reuse the font's fixed Unicode cache rather than taking the ASCII shortcut.
Local cyrillicFont:TBitmapFont = Terminus6x12Font()
For Local repeat:Int = 0 Until 32
	If Not cyrillicFont.HasGlyph($0410) Or Not cyrillicFont.HasGlyph($044F) Then ..
		RuntimeError "Terminus 6x12 is missing Cyrillic glyphs"
Next

Print "embedded bitmap-font catalogue conformance: PASS"
