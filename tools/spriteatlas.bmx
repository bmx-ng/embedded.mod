' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.FileSystem
Import BRL.Pixmap
Import BRL.RectPacker
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

Type TAtlasInput
	Field name:String
	Field path:String
	Field pixels:TPixmap
	Field trimX:Int
	Field trimY:Int
	Field trimWidth:Int
	Field trimHeight:Int
	Field packedX:Int
	Field packedY:Int
	Field fullyTransparent:Int
End Type

Type TAtlasAnimation
	Field name:String
	Field frameNames:String[]
	Field durations:Int[]
End Type

Function Fail(message:String)
	Throw "spriteatlas: " + message
End Function

Function ParseInteger:Int(value:String, name:String, minimum:Int, maximum:Int)
	If Not value Then Fail("missing " + name)
	For Local index:Int = 0 Until value.Length
		If value[index] < Asc("0") Or value[index] > Asc("9") Then Fail("invalid " + name + " '" + value + "'")
	Next
	Local number:Long = Long(value)
	If number < minimum Or number > maximum Then ..
		Fail(name + " must be between " + minimum + " and " + maximum)
	Return Int(number)
End Function

Function Identifier:String(value:String)
	Local result:String
	For Local index:Int = 0 Until value.Length
		Local character:Int = value[index]
		If (character >= Asc("a") And character <= Asc("z")) Or ..
				(character >= Asc("A") And character <= Asc("Z")) Or ..
				(character >= Asc("0") And character <= Asc("9")) Or character = Asc("_") Then
			result :+ Chr(character)
		Else
			result :+ "_"
		End If
	Next
	If Not result Then Return "_"
	If result[0] >= Asc("0") And result[0] <= Asc("9") Then result = "_" + result
	Return result
End Function

Function ExportIdentifier:String(value:String)
	Local result:String = Identifier(value)
	Return result[..1].ToUpper() + result[1..]
End Function

Function FindInput:Int(inputs:TAtlasInput[], name:String)
	For Local index:Int = 0 Until inputs.Length
		If inputs[index].name = name Then Return index
	Next
	Return -1
End Function

Function AddInput:TAtlasInput[](inputs:TAtlasInput[], specification:String)
	Local separator:Int = specification.Find("=")
	If separator <= 0 Or separator = specification.Length - 1 Then ..
		Fail("frame must use name=source-image")
	Local name:String = specification[..separator]
	Local path:String = specification[separator + 1..]
	If FindInput(inputs, name) >= 0 Then Fail("duplicate frame name '" + name + "'")
	Local identifierName:String = ExportIdentifier(name).ToLower()
	For Local input:TAtlasInput = EachIn inputs
		If ExportIdentifier(input.name).ToLower() = identifierName Then ..
			Fail("frame names '" + input.name + "' and '" + name + "' produce the same identifier")
	Next
	Local input:TAtlasInput = New TAtlasInput
	input.name = name
	input.path = path
	input.pixels = LoadPixmap(path)
	If Not input.pixels Then Fail("could not load '" + path + "'")
	If input.pixels.width <= 0 Or input.pixels.height <= 0 Or ..
			input.pixels.width > 65535 Or input.pixels.height > 65535 Then ..
		Fail("frame '" + name + "' has unsupported dimensions")
	inputs = inputs[..inputs.Length + 1]
	inputs[inputs.Length - 1] = input
	Return inputs
End Function

Function AddAnimation:TAtlasAnimation[](animations:TAtlasAnimation[], specification:String)
	Local separator:Int = specification.Find("=")
	If separator <= 0 Or separator = specification.Length - 1 Then ..
		Fail("animation must use name=frame:milliseconds,...")
	Local animation:TAtlasAnimation = New TAtlasAnimation
	animation.name = specification[..separator]
	For Local existing:TAtlasAnimation = EachIn animations
		If existing.name = animation.name Then Fail("duplicate animation name '" + animation.name + "'")
		If ExportIdentifier(existing.name).ToLower() = ExportIdentifier(animation.name).ToLower() Then ..
			Fail("animation names produce the same identifier")
	Next
	Local entries:String[] = specification[separator + 1..].Split(",")
	If Not entries.Length Then Fail("animation '" + animation.name + "' has no frames")
	animation.frameNames = New String[entries.Length]
	animation.durations = New Int[entries.Length]
	For Local index:Int = 0 Until entries.Length
		Local durationSeparator:Int = entries[index].FindLast(":")
		If durationSeparator <= 0 Or durationSeparator = entries[index].Length - 1 Then ..
			Fail("animation frames must use frame:milliseconds")
		animation.frameNames[index] = entries[index][..durationSeparator]
		animation.durations[index] = ParseInteger(entries[index][durationSeparator + 1..], ..
			"frame duration", 1, $7fffffff)
	Next
	animations = animations[..animations.Length + 1]
	animations[animations.Length - 1] = animation
	Return animations
End Function

Function PrepareTrim(input:TAtlasInput, trim:Int, alphaThreshold:Int)
	If Not trim Then
		input.trimWidth = input.pixels.width
		input.trimHeight = input.pixels.height
		Return
	End If
	Local left:Int = input.pixels.width
	Local top:Int = input.pixels.height
	Local right:Int = -1
	Local bottom:Int = -1
	For Local y:Int = 0 Until input.pixels.height
		For Local x:Int = 0 Until input.pixels.width
			Local alpha:Int = Int((UInt(input.pixels.ReadPixel(x, y)) Shr 24) & $ff)
			If alpha >= alphaThreshold Then
				If x < left Then left = x
				If x > right Then right = x
				If y < top Then top = y
				If y > bottom Then bottom = y
			End If
		Next
	Next
	If right < left Or bottom < top Then
		' A transparent placeholder keeps the runtime frame representation simple.
		input.fullyTransparent = True
		input.trimX = 0
		input.trimY = 0
		input.trimWidth = 1
		input.trimHeight = 1
	Else
		input.trimX = left
		input.trimY = top
		input.trimWidth = right - left + 1
		input.trimHeight = bottom - top + 1
	End If
End Function

Function WriteGeneratedSource(path:String, assetFile:String, symbol:String, ..
		inputs:TAtlasInput[], animations:TAtlasAnimation[])
	Local output:TStream = WriteStream(path)
	If Not output Then Fail("could not create '" + path + "'")
	output.WriteLine("' Generated by Embedded spriteatlas; edit the source assets instead.")
	output.WriteLine("' The application must import Embedded.Graphics2D.Sprite and Incbin ~q" + assetFile + "~q.")
	output.WriteLine("")
	For Local index:Int = 0 Until inputs.Length
		output.WriteLine("Const " + symbol + "Frame" + ExportIdentifier(inputs[index].name) + ":Int = " + index)
	Next
	output.WriteLine("")
	output.WriteLine("Private")
	output.WriteLine("Global _" + symbol + "Sheet:TEmbeddedSpriteSheet")
	For Local animation:TAtlasAnimation = EachIn animations
		output.WriteLine("Global _" + symbol + ExportIdentifier(animation.name) + ":TEmbeddedSpriteAnimation")
	Next
	output.WriteLine("")
	output.WriteLine("Public")
	output.WriteLine("Function " + symbol + "SpriteSheet:TEmbeddedSpriteSheet()")
	output.WriteLine("~tIf Not _" + symbol + "Sheet Then")
	output.WriteLine("~t~tLocal image:TEmbeddedImage = TEmbeddedImage.Create(IncbinPtr(~q" + ..
		assetFile + "~q), IncbinLen(~q" + assetFile + "~q))")
	output.WriteLine("~t~tIf Not image Then Return Null")
	output.WriteLine("~t~tLocal frames:TEmbeddedSpriteFrame[] = New TEmbeddedSpriteFrame[" + inputs.Length + "]")
	For Local index:Int = 0 Until inputs.Length
		Local input:TAtlasInput = inputs[index]
		output.WriteLine("~t~tframes[" + index + "] = TEmbeddedSpriteFrame.Create(" + ..
			input.packedX + ", " + input.packedY + ", " + input.trimWidth + ", " + ..
			input.trimHeight + ", " + input.pixels.width + ", " + input.pixels.height + ..
			", " + input.trimX + ", " + input.trimY + ")")
	Next
	output.WriteLine("~t~t_" + symbol + "Sheet = TEmbeddedSpriteSheet.Create(image, frames)")
	output.WriteLine("~tEnd If")
	output.WriteLine("~tReturn _" + symbol + "Sheet")
	output.WriteLine("End Function")
	For Local animation:TAtlasAnimation = EachIn animations
		Local animationSymbol:String = symbol + ExportIdentifier(animation.name)
		Local indices:String
		Local durations:String
		For Local index:Int = 0 Until animation.frameNames.Length
			If index Then indices :+ ", "; durations :+ ", "
			indices :+ FindInput(inputs, animation.frameNames[index])
			durations :+ animation.durations[index]
		Next
		output.WriteLine("")
		output.WriteLine("Function " + animationSymbol + "Animation:TEmbeddedSpriteAnimation()")
		output.WriteLine("~tIf Not _" + animationSymbol + " Then _" + animationSymbol + ..
			" = TEmbeddedSpriteAnimation.Create(" + symbol + "SpriteSheet(), [" + ..
			indices + "], [" + durations + "])")
		output.WriteLine("~tReturn _" + animationSymbol)
		output.WriteLine("End Function")
	Next
	output.Close()
End Function

' Resolve relative source and output paths from the directory in which the tool was invoked.
If Not ChangeDir(LaunchDir) Then Fail("could not use launch directory '" + LaunchDir + "'")

If AppArgs.Length < 3 Then
	Print "Usage: spriteatlas <output-base> [options] name=image ..."
	Print "Options:"
	Print "  --symbol <identifier>         Generated function prefix (default: Sprites)"
	Print "  --page-size <1-65535>         Maximum square page size (default: 256)"
	Print "  --padding <0-64>              Empty pixels around packed frames (default: 0)"
	Print "  --trim true|false             Remove transparent borders (default: true)"
	Print "  --alpha-threshold <1-255>     Visible-alpha threshold (default: 1)"
	Print "  --animation name=frame:ms,... Add a named timed animation"
	Print "Output: <output-base>.png and <output-base>.bmx; convert PNG to .ebi with image2embedded."
	RuntimeError "Missing or invalid arguments"
End If

Local outputBase:String = AppArgs[1]
Local symbol:String = "Sprites"
Local pageSize:Int = 256
Local padding:Int
Local trim:Int = True
Local alphaThreshold:Int = 1
Local inputs:TAtlasInput[] = New TAtlasInput[0]
Local animations:TAtlasAnimation[] = New TAtlasAnimation[0]

Local argument:Int = 2
While argument < AppArgs.Length
	Local option:String = AppArgs[argument]
	If option.StartsWith("--") Then
		If argument + 1 >= AppArgs.Length Then Fail("missing value for '" + option + "'")
		Local value:String = AppArgs[argument + 1]
		Select option
			Case "--symbol"
				symbol = Identifier(value)
				If symbol <> value Then Fail("symbol must be a BlitzMax identifier")
			Case "--page-size"
				pageSize = ParseInteger(value, "page size", 1, 65535)
			Case "--padding"
				padding = ParseInteger(value, "padding", 0, 64)
			Case "--alpha-threshold"
				alphaThreshold = ParseInteger(value, "alpha threshold", 1, 255)
			Case "--trim"
				Select value.ToLower()
					Case "true", "yes", "1"
						trim = True
					Case "false", "no", "0"
						trim = False
					Default
						Fail("trim must be true or false")
				End Select
			Case "--animation"
				animations = AddAnimation(animations, value)
			Default
				Fail("unknown option '" + option + "'")
		End Select
		argument :+ 2
	Else
		inputs = AddInput(inputs, option)
		argument :+ 1
	End If
Wend

If Not outputBase Then Fail("output base is empty")
If Not inputs.Length Then Fail("at least one frame is required")
For Local animation:TAtlasAnimation = EachIn animations
	For Local name:String = EachIn animation.frameNames
		If FindInput(inputs, name) < 0 Then ..
			Fail("animation '" + animation.name + "' references unknown frame '" + name + "'")
	Next
Next

Local packer:TRectPacker = New TRectPacker
packer.maxWidth = pageSize
packer.maxHeight = pageSize
packer.maxSheets = 1
packer.powerOfTwo = False
packer.allowRotate = False
For Local index:Int = 0 Until inputs.Length
	PrepareTrim(inputs[index], trim, alphaThreshold)
	Local packedWidth:Long = Long(inputs[index].trimWidth) + padding * 2
	Local packedHeight:Long = Long(inputs[index].trimHeight) + padding * 2
	If packedWidth > pageSize Or packedHeight > pageSize Then ..
		Fail("frame '" + inputs[index].name + "' exceeds the configured page size")
	packer.Add(Int(packedWidth), Int(packedHeight), index)
Next

Local sheets:TPackedSheet[] = packer.Pack()
If sheets.Length <> 1 Or sheets[0].rects.Length <> inputs.Length Then ..
	Fail("frames do not fit one page; increase --page-size or split the atlas")
Local sheet:TPackedSheet = sheets[0]
Local atlas:TPixmap = CreatePixmap(sheet.width, sheet.height, PF_RGBA8888)
atlas.ClearPixels(0)
For Local rectangle:SPackedRect = EachIn sheet.rects
	If rectangle.rotated Then Fail("rectangle packer unexpectedly rotated a frame")
	Local input:TAtlasInput = inputs[rectangle.id]
	input.packedX = rectangle.x + padding
	input.packedY = rectangle.y + padding
	If Not input.fullyTransparent Then
		For Local y:Int = 0 Until input.trimHeight
			For Local x:Int = 0 Until input.trimWidth
				Local pixel:UInt = UInt(input.pixels.ReadPixel(input.trimX + x, input.trimY + y))
				atlas.WritePixel(input.packedX + x, input.packedY + y, Int(pixel))
			Next
		Next
	End If
Next

Local pngPath:String = outputBase + ".png"
Local sourcePath:String = outputBase + ".bmx"
If Not SavePixmapPNG(atlas, pngPath) Then Fail("could not create '" + pngPath + "'")
WriteGeneratedSource(sourcePath, outputBase + ".ebi", symbol, inputs, animations)

Print "Generated " + pngPath
Print "  dimensions: " + atlas.width + "x" + atlas.height
Print "  frames: " + inputs.Length
Print "  animations: " + animations.Length
Print "  trim: " + trim
Print "  padding: " + padding
Print "Generated " + sourcePath
Print "Next: image2embedded " + pngPath + " " + outputBase + ..
	".ebi --format auto --mask auto --alpha-threshold " + alphaThreshold
