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

Function NextCodePoint:Int(text:String, index:Int Var)
	If index >= text.length Then Return -1
	Local first:Int = text[index]
	index :+ 1
	If first >= $d800 And first <= $dbff And index < text.length Then
		Local second:Int = text[index]
		If second >= $dc00 And second <= $dfff Then
			index :+ 1
			Return $10000 + ((first - $d800) Shl 10) + (second - $dc00)
		End If
	End If
	If first >= $d800 And first <= $dfff Then Return $fffd
	Return first
End Function

' Some desktop runtimes expose UTF-8 command-line bytes as one character per
' byte. Decode that representation, while leaving native Unicode arguments and
' legacy single-byte arguments untouched.
Function DecodeUTF8Argument:String(text:String)
	Local hasSequence:Int
	Local index:Int
	While index < text.length
		Local first:Int = text[index]
		If first > 255 Then Return text
		If first < $80 Then
			index :+ 1
			Continue
		End If
		Local count:Int
		If first >= $c2 And first <= $df Then
			count = 2
		Else If first >= $e0 And first <= $ef Then
			count = 3
		Else If first >= $f0 And first <= $f4 Then
			count = 4
		Else
			Return text
		End If
		If index + count > text.length Then Return text
		For Local continuation:Int = 1 Until count
			Local value:Int = text[index + continuation]
			If value < $80 Or value > $bf Then Return text
		Next
		If count = 3 Then
			Local second:Int = text[index + 1]
			If first = $e0 And second < $a0 Then Return text
			If first = $ed And second >= $a0 Then Return text
		Else If count = 4 Then
			Local second:Int = text[index + 1]
			If first = $f0 And second < $90 Then Return text
			If first = $f4 And second >= $90 Then Return text
		End If
		hasSequence = True
		index :+ count
	Wend
	If Not hasSequence Then Return text
	Local encoded:Byte[] = New Byte[text.length + 1]
	For index = 0 Until text.length
		encoded[index] = Byte(text[index])
	Next
	Return String.FromUTF8String(Varptr encoded[0])
End Function

Function AddCharacters:Int[](codePoints:Int[], text:String)
	Local index:Int
	While index < text.length
		Local codePoint:Int = NextCodePoint(text, index)
		Local found:Int
		For Local existing:Int = EachIn codePoints
			If existing = codePoint Then
				found = True
				Exit
			End If
		Next
		If Not found Then
			codePoints = codePoints[..codePoints.length + 1]
			codePoints[codePoints.length - 1] = codePoint
		End If
	Wend
	Return codePoints
End Function

Function CharacterSelected:Int(codePoint:Int, codePoints:Int[])
	For Local selected:Int = EachIn codePoints
		If selected = codePoint Then Return True
	Next
	Return False
End Function

Function ManifestRelativePath:String(baseDirectory:String, path:String)
	path = path.Trim()
	If path.StartsWith("/") Or path.StartsWith("\\") Or ..
			(path.length > 1 And path[1] = Asc(":")) Then Return RealPath(path)
	Return RealPath(baseDirectory + "/" + path)
End Function

Type TFontSelection
	Field ranges:String
	Field codePoints:Int[]
	Field dependencies:String[]
	Field enabled:Int
	Field fallbackCodePoint:Int
	Field hasFallback:Int

	Method AddDependency(path:String)
		path = RealPath(path)
		For Local existing:String = EachIn dependencies
			If existing = path Then Return
		Next
		dependencies = dependencies[..dependencies.length + 1]
		dependencies[dependencies.length - 1] = path
	End Method

	Method AddRanges(value:String)
		If ranges.length Then ranges :+ ","
		ranges :+ value.Trim()
		enabled = True
	End Method

	Method AddText(value:String)
		codePoints = AddCharacters(codePoints, value)
		enabled = True
	End Method

	Method SetFallback(value:String)
		fallbackCodePoint = ParseHex(value)
		hasFallback = True
	End Method

	Method AddTextFile(path:String)
		path = RealPath(path)
		If FileType(path) <> FILETYPE_FILE Then Fail("could not read character file '" + path + "'")
		AddText(LoadText(path))
		AddDependency(path)
	End Method

	Method AddManifest(path:String)
		path = RealPath(path)
		If FileType(path) <> FILETYPE_FILE Then Fail("could not read font manifest '" + path + "'")
		enabled = True
		AddDependency(path)
		Local baseDirectory:String = ExtractDir(path)
		Local lines:String[] = LoadText(path).Replace("~r", "").Split("~n")
		For Local lineIndex:Int = 0 Until lines.length
			Local line:String = lines[lineIndex]
			Local trimmed:String = line.Trim()
			If Not trimmed.length Or trimmed.StartsWith("#") Then Continue
			Local separator:Int = line.Find("=")
			If separator < 0 Then Fail("expected key=value at " + path + ":" + (lineIndex + 1))
			Local key:String = line[..separator].Trim().ToLower()
			Local value:String = line[separator + 1..].Trim()
			Select key
				Case "ranges"
					AddRanges(value)
				Case "chars"
					AddText(value)
				Case "chars-file"
					AddTextFile(ManifestRelativePath(baseDirectory, value))
				Case "fallback"
					SetFallback(value)
				Default
					Fail("unknown manifest key '" + key + "' at " + path + ":" + (lineIndex + 1))
			End Select
		Next
	End Method
End Type

Function AddGlyph:TBdfGlyph[](glyphs:TBdfGlyph[], glyph:TBdfGlyph)
	If Not glyph Or glyph.codePoint < 0 Then Return glyphs
	' BDF permits a zero-sized bitmap for blank glyphs such as space. A missing
	' bitmap is only malformed when the glyph declares visible dimensions.
	If Not glyph.bitmap And (glyph.width > 0 Or glyph.height > 0) Then Return glyphs
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

If AppArgs.length < 3 Then
	Print "Usage: bdf2embeddedfont <input.bdf> <output.ebf> [options]"
	Print "       bdf2embeddedfont <input.bdf> <output.ebf> [hex-ranges]"
	Print "Options:"
	Print "  --ranges <list>      Include hexadecimal ranges, such as 0020-007e,00a0-00ff"
	Print "  --chars <text>       Include every Unicode character occurring in text"
	Print "  --chars-file <path>  Include every Unicode character occurring in a UTF-8 file"
	Print "  --fallback <hex>     Use and retain this code point for missing glyphs"
	Print "  --manifest <path>    Read ranges, chars, and chars-file entries from a manifest"
	Print "  --if-needed          Do nothing when the output is newer than every input"
	Print "Selection options may be repeated and are combined. The BDF default glyph is always included."
	RuntimeError "Missing or invalid arguments"
End If

ChangeDir LaunchDir
Local inputPath:String = AppArgs[1]
Local outputPath:String = AppArgs[2]
Local selection:TFontSelection = New TFontSelection
selection.AddDependency(inputPath)
Local ifNeeded:Int
Local argument:Int = 3
While argument < AppArgs.length
	Local option:String = AppArgs[argument]
	If Not option.StartsWith("--") Then
		If AppArgs.length <> 4 Then Fail("hexadecimal ranges must be the only optional argument")
		selection.AddRanges(option)
		argument :+ 1
		Continue
	End If
	If option = "--if-needed" Then
		ifNeeded = True
		argument :+ 1
		Continue
	End If
	If argument + 1 >= AppArgs.length Then Fail("missing value for '" + option + "'")
	Select option
		Case "--ranges"
			selection.AddRanges(AppArgs[argument + 1])
		Case "--chars"
			selection.AddText(DecodeUTF8Argument(AppArgs[argument + 1]))
		Case "--chars-file"
			selection.AddTextFile(AppArgs[argument + 1])
		Case "--fallback"
			selection.SetFallback(AppArgs[argument + 1])
		Case "--manifest"
			selection.AddManifest(AppArgs[argument + 1])
		Default
			Fail("unknown option '" + option + "'")
	End Select
	argument :+ 2
Wend

If ifNeeded And FileType(outputPath) = FILETYPE_FILE Then
	Local outputTime:Long = FileTime(outputPath)
	Local current:Int = outputTime > 0
	For Local dependency:String = EachIn selection.dependencies
		If FileTime(dependency) > outputTime Then
			current = False
			Exit
		End If
	Next
	If current Then
		Print "Up to date: " + outputPath
		End
	End If
End If

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
		Local retainedDefault:Int = defaultCodePoint
		If selection.hasFallback Then retainedDefault = selection.fallbackCodePoint
		If current And (Not selection.enabled Or ..
				(selection.ranges.length And CodePointSelected(current.codePoint, selection.ranges)) Or ..
				CharacterSelected(current.codePoint, selection.codePoints) Or ..
				current.codePoint = retainedDefault) Then glyphs = AddGlyph(glyphs, current)
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
If selection.hasFallback Then defaultCodePoint = selection.fallbackCodePoint
Local hasDefaultGlyph:Int
For Local glyph:TBdfGlyph = EachIn glyphs
	If glyph.codePoint = defaultCodePoint Then
		hasDefaultGlyph = True
		Exit
	End If
Next
If Not hasDefaultGlyph Then Fail("fallback glyph " + defaultCodePoint + " is not present in the BDF")

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
