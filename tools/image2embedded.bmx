' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.FileSystem
Import BRL.Pixmap
Import Image.PNG
Import Image.JPG
Import Image.BMP
Import Image.GIF
Import Image.TGA
Import Image.PNM
Import Image.Qoi
Import Image.WebP
Import Image.TIFF
Import Image.SVG

Const EBIHeaderSize:Int = 32
Const EBIFlagMask:Int = 1
Const EBIFormatIndexed1:Int = $101
Const EBIFormatIndexed2:Int = $102
Const EBIFormatIndexed4:Int = $104
Const EBIFormatIndexed8:Int = $108

Function Fail(message:String)
	Throw "image2embedded: " + message
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

Function ClampByte:Int(value:Int, name:String)
	If value < 0 Or value > 255 Then Fail(name + " must be between 0 and 255")
	Return value
End Function

Function PaletteIndex:Int(palette:UInt[], count:Int, color:UInt)
	For Local index:Int = 0 Until count
		If palette[index] = color Then Return index
	Next
	Return -1
End Function

Function IndexedCapacity:Int(format:Int)
	Select format
		Case EBIFormatIndexed1
			Return 2
		Case EBIFormatIndexed2
			Return 4
		Case EBIFormatIndexed4
			Return 16
		Case EBIFormatIndexed8
			Return 256
	End Select
	Return 0
End Function

Function IndexedBits:Int(format:Int)
	Local capacity:Int = IndexedCapacity(format)
	Select capacity
		Case 2
			Return 1
		Case 4
			Return 2
		Case 16
			Return 4
		Case 256
			Return 8
	End Select
	Return 0
End Function

If AppArgs.length < 3 Then
	Print "Usage: image2embedded <input-image> <output.ebi> [options]"
	Print "Options:"
	Print "  --format auto|mono1|indexed1|indexed2|indexed4|indexed8|rgb565|rgb888"
	Print "                                    Output pixel format (default: rgb565)"
	Print "  --threshold <0-255>           Mono1 luminance threshold (default: 128)"
	Print "  --mask auto|always|none       Transparency-mask policy (default: auto)"
	Print "  --alpha-threshold <0-255>     Minimum visible alpha (default: 128)"
	RuntimeError "Missing or invalid arguments"
End If

Local inputPath:String = AppArgs[1]
Local outputPath:String = AppArgs[2]
Local outputFormat:Int = 2
Local outputFormatName:String = "rgb565"
Local automaticFormat:Int
Local monoThreshold:Int = 128
Local alphaThreshold:Int = 128
Local maskPolicy:Int ' 0 auto, 1 always, 2 none

Local argument:Int = 3
While argument < AppArgs.length
	Local option:String = AppArgs[argument]
	If argument + 1 >= AppArgs.length Then Fail("missing value for '" + option + "'")
	Local value:String = AppArgs[argument + 1]
	Select option
		Case "--format"
			outputFormatName = value.ToLower()
			automaticFormat = False
			Select outputFormatName
				Case "auto"
					automaticFormat = True
				Case "mono1"
					outputFormat = 1
				Case "indexed1"
					outputFormat = EBIFormatIndexed1
				Case "indexed2"
					outputFormat = EBIFormatIndexed2
				Case "indexed4"
					outputFormat = EBIFormatIndexed4
				Case "indexed8"
					outputFormat = EBIFormatIndexed8
				Case "rgb565"
					outputFormat = 2
				Case "rgb888"
					outputFormat = 3
				Default
					Fail("unknown pixel format '" + value + "'")
			End Select
		Case "--threshold"
			monoThreshold = ClampByte(Int(value), "threshold")
		Case "--alpha-threshold"
			alphaThreshold = ClampByte(Int(value), "alpha threshold")
		Case "--mask"
			Select value.ToLower()
				Case "auto"
					maskPolicy = 0
				Case "always"
					maskPolicy = 1
				Case "none"
					maskPolicy = 2
				Default
					Fail("unknown mask policy '" + value + "'")
			End Select
		Default
			Fail("unknown option '" + option + "'")
	End Select
	argument :+ 2
Wend

Local pixmap:TPixmap = LoadPixmap(inputPath)
If Not pixmap Then Fail("could not load '" + inputPath + "'")
If pixmap.width <= 0 Or pixmap.height <= 0 Or pixmap.width > 65535 Or pixmap.height > 65535 Then ..
	Fail("image dimensions are outside the EBI1 range")

Local hasTransparency:Int
If maskPolicy <> 2 Then
	For Local y:Int = 0 Until pixmap.height
		For Local x:Int = 0 Until pixmap.width
			Local color:UInt = UInt(pixmap.ReadPixel(x, y))
			If ((color Shr 24) & $ff) < 255 Then
				hasTransparency = True
				Exit
			End If
		Next
		If hasTransparency Then Exit
	Next
End If
Local includeMask:Int = maskPolicy = 1 Or (maskPolicy = 0 And hasTransparency)

' Indexed images retain exact source colours. Auto selects the smallest exact
' palette and falls back to RGB565 when the source contains more than 256.
Local palette:UInt[]
Local paletteCount:Int
Local indexedCapacity:Int = IndexedCapacity(outputFormat)
If automaticFormat Or indexedCapacity Then
	Local scanCapacity:Int = indexedCapacity
	If automaticFormat Then scanCapacity = 256
	palette = New UInt[scanCapacity]
	Local tooManyColors:Int
	For Local y:Int = 0 Until pixmap.height
		For Local x:Int = 0 Until pixmap.width
			Local source:UInt = UInt(pixmap.ReadPixel(x, y))
			Local color:UInt = source & $ffffff
			If includeMask And ((source Shr 24) & $ff) < UInt(alphaThreshold) Then color = 0
			If PaletteIndex(palette, paletteCount, color) < 0 Then
				If paletteCount >= scanCapacity Then
					tooManyColors = True
					Exit
				End If
				palette[paletteCount] = color
				paletteCount :+ 1
			End If
		Next
		If tooManyColors Then Exit
	Next
	If tooManyColors Then
		If Not automaticFormat Then ..
			Fail(outputFormatName + " supports at most " + indexedCapacity + " exact colours")
		outputFormat = 2
		outputFormatName = "rgb565"
		palette = Null
		paletteCount = 0
	Else If automaticFormat Then
		If paletteCount <= 2 Then
			outputFormat = EBIFormatIndexed1
			outputFormatName = "indexed1"
		Else If paletteCount <= 4 Then
			outputFormat = EBIFormatIndexed2
			outputFormatName = "indexed2"
		Else If paletteCount <= 16 Then
			outputFormat = EBIFormatIndexed4
			outputFormatName = "indexed4"
		Else
			outputFormat = EBIFormatIndexed8
			outputFormatName = "indexed8"
		End If
	End If
End If

Local stride:Int
Select outputFormat
	Case 1
		stride = (pixmap.width + 7) / 8
	Case 2
		stride = pixmap.width * 2
	Case 3
		stride = pixmap.width * 3
	Case EBIFormatIndexed1, EBIFormatIndexed2, EBIFormatIndexed4, EBIFormatIndexed8
		stride = (pixmap.width * IndexedBits(outputFormat) + 7) / 8
End Select
Local pixels:Byte[] = New Byte[stride * pixmap.height]
Local maskStride:Int
Local mask:Byte[]
If includeMask Then
	maskStride = (pixmap.width + 7) / 8
	mask = New Byte[maskStride * pixmap.height]
End If

For Local y:Int = 0 Until pixmap.height
	For Local x:Int = 0 Until pixmap.width
		Local color:UInt = UInt(pixmap.ReadPixel(x, y))
		Local red:UInt = (color Shr 16) & $ff
		Local green:UInt = (color Shr 8) & $ff
		Local blue:UInt = color & $ff
		Local offset:Int
		Select outputFormat
			Case 1
				Local luminance:UInt = (red * 77 + green * 150 + blue * 29) Shr 8
				If luminance >= UInt(monoThreshold) Then ..
					pixels[y * stride + (x Shr 3)] :| Byte($80 Shr (x & 7))
			Case 2
				offset = y * stride + x * 2
				Local rgb565:UInt = ((red Shr 3) Shl 11) | ((green Shr 2) Shl 5) | (blue Shr 3)
				pixels[offset] = Byte(rgb565)
				pixels[offset + 1] = Byte(rgb565 Shr 8)
			Case 3
				offset = y * stride + x * 3
				pixels[offset] = Byte(red)
				pixels[offset + 1] = Byte(green)
				pixels[offset + 2] = Byte(blue)
			Case EBIFormatIndexed1, EBIFormatIndexed2, EBIFormatIndexed4, EBIFormatIndexed8
				Local paletteColor:UInt = color & $ffffff
				If includeMask And ((color Shr 24) & $ff) < UInt(alphaThreshold) Then paletteColor = 0
				Local paletteIndex:Int = PaletteIndex(palette, paletteCount, paletteColor)
				Local bits:Int = IndexedBits(outputFormat)
				Local bitOffset:Int = x * bits
				Local shift:Int = 8 - bits - (bitOffset & 7)
				pixels[y * stride + (bitOffset Shr 3)] :| Byte(paletteIndex Shl shift)
		End Select
		If includeMask And ((color Shr 24) & $ff) >= UInt(alphaThreshold) Then ..
			mask[y * maskStride + (x Shr 3)] :| Byte($80 Shr (x & 7))
	Next
Next

Local paletteBytes:Int = paletteCount * 3
Local pixelOffset:Int = EBIHeaderSize + paletteBytes
Local maskOffset:Int
If includeMask Then maskOffset = pixelOffset + pixels.length
Local output:TStream = WriteStream(outputPath)
If Not output Then Fail("could not create '" + outputPath + "'")
output.WriteString("EBI1")
WriteU16(output, 1)
WriteU16(output, includeMask * EBIFlagMask)
WriteU16(output, pixmap.width)
WriteU16(output, pixmap.height)
WriteU16(output, outputFormat)
WriteU16(output, 0)
WriteU32(output, stride)
WriteU32(output, pixelOffset)
WriteU32(output, maskStride)
WriteU32(output, maskOffset)
For Local index:Int = 0 Until paletteCount
	Local color:UInt = palette[index]
	output.WriteByte(Int((color Shr 16) & $ff))
	output.WriteByte(Int((color Shr 8) & $ff))
	output.WriteByte(Int(color & $ff))
Next
For Local byteValue:Byte = EachIn pixels
	output.WriteByte(Int(byteValue) & $ff)
Next
If includeMask Then
	For Local byteValue:Byte = EachIn mask
		output.WriteByte(Int(byteValue) & $ff)
	Next
End If
output.Close()

Local maskBytes:Int
If includeMask Then maskBytes = mask.length

Print "Generated " + outputPath
Print "  dimensions: " + pixmap.width + "x" + pixmap.height
Print "  format: " + outputFormatName
If paletteCount Then Print "  palette entries: " + paletteCount + " (" + paletteBytes + " bytes)"
Print "  transparency mask: " + includeMask
Print "  pixel bytes: " + pixels.length
If includeMask Then Print "  mask bytes: " + maskBytes
Print "  total bytes: " + (EBIHeaderSize + paletteBytes + pixels.length + maskBytes)
