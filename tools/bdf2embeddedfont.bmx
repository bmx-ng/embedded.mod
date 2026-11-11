' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.FileSystem

Const FontRecordSize:Int = 16
Const FontHeaderSize:Int = 32

Type TBdfGlyph
	Field codePoint:Int = -1
	Field width:Int
	Field height:Int
	Field xOffset:Int
	Field yOffset:Int
	Field advance:Int
	Field stride:Int
	Field bitmap:Byte[]
	Field bitmapOffset:Int
End Type

Function Fail(message:String)
	Throw "bdf2embeddedfont: " + message
End Function

Function Fields:String[](line:String)
	Local raw:String[] = line.Trim().Split(" ")
	Local result:String[]
	For Local field:String = EachIn raw
		If Not field.length Then Continue
		result = result[..result.length + 1]
		result[result.length - 1] = field
	Next
	Return result
End Function

Function HexDigit:Int(character:Int)
	If character >= Asc("0") And character <= Asc("9") Then Return character - Asc("0")
	If character >= Asc("a") And character <= Asc("f") Then Return character - Asc("a") + 10
	If character >= Asc("A") And character <= Asc("F") Then Return character - Asc("A") + 10
	Return -1
End Function

Function ParseHex:Int(value:String)
	value = value.Trim()
	If value.StartsWith("0x") Or value.StartsWith("0X") Then value = value[2..]
	If value.StartsWith("$") Then value = value[1..]
	If Not value.length Then Fail("empty hexadecimal value")
	Local result:Int
	For Local index:Int = 0 Until value.length
		Local digit:Int = HexDigit(value[index])
		If digit < 0 Then Fail("invalid hexadecimal value '" + value + "'")
		result = (result Shl 4) | digit
	Next
	Return result
End Function

Function CodePointSelected:Int(codePoint:Int, ranges:String)
	If Not ranges.length Then Return True
	For Local item:String = EachIn ranges.Split(",")
		item = item.Trim()
		If Not item.length Then Continue
		Local separator:Int = item.Find("-")
		If separator < 0 Then
			If codePoint = ParseHex(item) Then Return True
		Else
			Local first:Int = ParseHex(item[..separator])
			Local last:Int = ParseHex(item[separator + 1..])
			If first > last Then Fail("reversed range '" + item + "'")
			If codePoint >= first And codePoint <= last Then Return True
		End If
	Next
	Return False
End Function

Function AddGlyph:TBdfGlyph[](glyphs:TBdfGlyph[], glyph:TBdfGlyph)
	If Not glyph Or glyph.codePoint < 0 Or Not glyph.bitmap Then Return glyphs
	glyphs = glyphs[..glyphs.length + 1]
	glyphs[glyphs.length - 1] = glyph
	Return glyphs
End Function

Function SortGlyphs(glyphs:TBdfGlyph[])
	For Local index:Int = 1 Until glyphs.length
		Local value:TBdfGlyph = glyphs[index]
		Local position:Int = index
		While position > 0 And glyphs[position - 1].codePoint > value.codePoint
			glyphs[position] = glyphs[position - 1]
			position :- 1
		Wend
		glyphs[position] = value
	Next
	For Local index:Int = 1 Until glyphs.length
		If glyphs[index - 1].codePoint = glyphs[index].codePoint Then ..
			Fail("duplicate encoding " + glyphs[index].codePoint)
	Next
End Function

Function WriteU16(stream:TStream, value:Int)
	stream.WriteByte(value & $ff)
	stream.WriteByte((value Shr 8) & $ff)
End Function

Function WriteU32(stream:TStream, value:Int)
	stream.WriteByte(value & $ff)
	stream.WriteByte((value Shr 8) & $ff)
	stream.WriteByte((value Shr 16) & $ff)
	stream.WriteByte((value Shr 24) & $ff)
End Function

Function WriteS8(stream:TStream, value:Int)
	If value < -128 Or value > 127 Then Fail("glyph offset is outside the EBF1 range")
	stream.WriteByte(value & $ff)
End Function

If AppArgs.length < 3 Or AppArgs.length > 4 Then
	Print "Usage: bdf2embeddedfont <input.bdf> <output.ebf> [hex-ranges]"
	Print "Example ranges: 0020-007e,00a0-00ff"
	RuntimeError "Missing or invalid arguments"
End If

ChangeDir LaunchDir
Local inputPath:String = AppArgs[1]
Local outputPath:String = AppArgs[2]
Local ranges:String
If AppArgs.length = 4 Then ranges = AppArgs[3]

Local source:String = LoadText(inputPath).Replace("~r", "")
If Not source.length Then Fail("could not read '" + inputPath + "'")
Local lines:String[] = source.Split("~n")
Local glyphs:TBdfGlyph[]
Local current:TBdfGlyph
Local ascent:Int = -1
Local descent:Int = -1
Local defaultCodePoint:Int = 32

For Local lineIndex:Int = 0 Until lines.length
	Local line:String = lines[lineIndex].Trim()
	If line.StartsWith("FONT_ASCENT ") Then
		ascent = Int(line[12..].Trim())
	Else If line.StartsWith("FONT_DESCENT ") Then
		descent = Int(line[13..].Trim())
	Else If line.StartsWith("DEFAULT_CHAR ") Then
		defaultCodePoint = Int(line[13..].Trim())
	Else If line.StartsWith("STARTCHAR") Then
		current = New TBdfGlyph
	Else If line = "ENDCHAR" Then
		If current And (CodePointSelected(current.codePoint, ranges) Or ..
				current.codePoint = defaultCodePoint) Then glyphs = AddGlyph(glyphs, current)
		current = Null
	Else If current
		Local fields:String[] = Fields(line)
		If fields.length = 0 Then Continue
		Select fields[0]
			Case "ENCODING"
				If fields.length >= 2 Then current.codePoint = Int(fields[1])
			Case "DWIDTH"
				If fields.length >= 2 Then current.advance = Int(fields[1])
			Case "BBX"
				If fields.length < 5 Then Fail("invalid BBX at line " + (lineIndex + 1))
				current.width = Int(fields[1])
				current.height = Int(fields[2])
				current.xOffset = Int(fields[3])
				current.yOffset = Int(fields[4])
				current.stride = (current.width + 7) / 8
			Case "BITMAP"
				If current.width < 0 Or current.height < 0 Or current.stride < 0 Then ..
					Fail("BITMAP before BBX at line " + (lineIndex + 1))
				current.bitmap = New Byte[current.stride * current.height]
				For Local row:Int = 0 Until current.height
					lineIndex :+ 1
					If lineIndex >= lines.length Then Fail("truncated bitmap")
					Local encoded:String = lines[lineIndex].Trim()
					If encoded.length < current.stride * 2 Then Fail("short bitmap row at line " + (lineIndex + 1))
					For Local column:Int = 0 Until current.stride
						Local high:Int = HexDigit(encoded[column * 2])
						Local low:Int = HexDigit(encoded[column * 2 + 1])
						If high < 0 Or low < 0 Then Fail("invalid bitmap row at line " + (lineIndex + 1))
						current.bitmap[row * current.stride + column] = Byte((high Shl 4) | low)
					Next
				Next
		End Select
	End If
Next

If ascent < 0 Or descent < 0 Then Fail("BDF font has no ascent/descent properties")
If glyphs.length = 0 Then Fail("no glyphs selected")
SortGlyphs(glyphs)

Local bitmapSize:Int
For Local glyph:TBdfGlyph = EachIn glyphs
	If glyph.width > 255 Or glyph.height > 255 Or glyph.advance < 0 Or glyph.advance > 255 Or ..
		glyph.stride > 255 Or glyph.bitmap.length > 65535 Then Fail("glyph " + glyph.codePoint + " exceeds EBF1 limits")
	glyph.bitmapOffset = bitmapSize
	bitmapSize :+ glyph.bitmap.length
Next

Local output:TStream = WriteStream(outputPath)
If Not output Then Fail("could not create '" + outputPath + "'")
output.WriteString("EBF1")
WriteU16(output, 1)
WriteU16(output, 0)
WriteU32(output, glyphs.length)
WriteU16(output, ascent)
WriteU16(output, descent)
WriteU16(output, ascent + descent)
WriteU16(output, FontRecordSize)
WriteU32(output, defaultCodePoint)
WriteU32(output, FontHeaderSize)
WriteU32(output, FontHeaderSize + glyphs.length * FontRecordSize)

For Local glyph:TBdfGlyph = EachIn glyphs
	WriteU32(output, glyph.codePoint)
	WriteU32(output, glyph.bitmapOffset)
	output.WriteByte(glyph.width)
	output.WriteByte(glyph.height)
	WriteS8(output, glyph.xOffset)
	WriteS8(output, glyph.yOffset)
	output.WriteByte(glyph.advance)
	output.WriteByte(glyph.stride)
	WriteU16(output, glyph.bitmap.length)
Next
For Local glyph:TBdfGlyph = EachIn glyphs
	For Local value:Byte = EachIn glyph.bitmap
		output.WriteByte(Int(value) & $ff)
	Next
Next
output.Close()

Print "Generated " + outputPath
Print "  glyphs: " + glyphs.length
Print "  ascent/descent: " + ascent + "/" + descent
Print "  bitmap bytes: " + bitmapSize
Print "  total bytes: " + (FontHeaderSize + glyphs.length * FontRecordSize + bitmapSize)
