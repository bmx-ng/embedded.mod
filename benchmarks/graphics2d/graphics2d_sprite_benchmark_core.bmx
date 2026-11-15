' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Image
Import Embedded.Graphics2D
Import Embedded.Graphics2D.Sprite
Import Embedded.System.Time

Const SpriteBenchmarkFormat:Int = 1
Const SpriteBenchmarkSamples:Int = 7
Const SpriteBenchmarkWarmups:Int = 2
Const SpriteBenchmarkCaseCount:Int = 13

?pico
Const SpriteBenchmarkPlatform:String = "pico"
?esp32
Const SpriteBenchmarkPlatform:String = "esp32"
?esp8266
Const SpriteBenchmarkPlatform:String = "esp8266"
?nrf52
Const SpriteBenchmarkPlatform:String = "nrf52"
?

Function SpriteBenchmarkHousekeeping()
	Delay 10
End Function

Type TGraphics2DSpriteBenchmark
	Field frame:TDisplayBuffer
	Field graphics:TEmbedded2DContext
	Field opaqueData:Byte[]
	Field maskedData:Byte[]
	Field opaqueImage:TEmbeddedImage
	Field maskedImage:TEmbeddedImage
	Field opaqueSheet:TEmbeddedSpriteSheet
	Field maskedSheet:TEmbeddedSpriteSheet
	Field animation:TEmbeddedSpriteAnimation
	Field player:TEmbeddedSpritePlayer
	Field samples:ULong[] = New ULong[SpriteBenchmarkSamples]
	Field checksums:UInt[] = New UInt[SpriteBenchmarkSamples]
	Field resultValue:UInt
	Field pixelFormatName:String

	Function Create:TGraphics2DSpriteBenchmark(width:Int, height:Int, pixelFormat:Int)
		If width < 64 Or height < 64 Then Return Null
		Local benchmark:TGraphics2DSpriteBenchmark = New TGraphics2DSpriteBenchmark
		benchmark.frame = TDisplayBuffer.Create(width, height, pixelFormat)
		If Not benchmark.frame Then Return Null
		benchmark.graphics = TEmbedded2DContext.Create(benchmark.frame)
		If Not benchmark.graphics Then Return Null
		benchmark.graphics.SetDirtyTracking(False)
		benchmark.opaqueData = CreateSpriteBenchmarkAtlas(False)
		benchmark.maskedData = CreateSpriteBenchmarkAtlas(True)
		benchmark.opaqueImage = TEmbeddedImage.Create(Varptr benchmark.opaqueData[0], ..
			benchmark.opaqueData.Length)
		benchmark.maskedImage = TEmbeddedImage.Create(Varptr benchmark.maskedData[0], ..
			benchmark.maskedData.Length)
		If Not benchmark.opaqueImage Or Not benchmark.maskedImage Then Return Null
		benchmark.opaqueSheet = TEmbeddedSpriteSheet.CreateGrid(benchmark.opaqueImage, 16, 16, ..
			0, 4, 0, 0, 8, 8)
		benchmark.maskedSheet = TEmbeddedSpriteSheet.CreateGrid(benchmark.maskedImage, 16, 16, ..
			0, 4, 0, 0, 8, 8)
		If Not benchmark.opaqueSheet Or Not benchmark.maskedSheet Then Return Null
		benchmark.animation = TEmbeddedSpriteAnimation.Create(benchmark.maskedSheet, ..
			[0, 1, 2, 3], [37, 71, 113, 59])
		benchmark.player = TEmbeddedSpritePlayer.Create(benchmark.animation)
		If Not benchmark.animation Or Not benchmark.player Then Return Null
		Select pixelFormat
			Case DisplayPixelFormatRGB565
				benchmark.pixelFormatName = "rgb565"
			Case DisplayPixelFormatMono1
				benchmark.pixelFormatName = "mono1"
			Case DisplayPixelFormatRGB888
				benchmark.pixelFormatName = "rgb888"
			Default
				benchmark.pixelFormatName = "unknown"
		End Select
		Return benchmark
	End Function

	Method Run()
		Print "G2D_SPRITE_BENCH,format=" + SpriteBenchmarkFormat + ",kind=meta" + ..
			",platform=" + SpriteBenchmarkPlatform + ",width=" + frame.Width() + ..
			",height=" + frame.Height() + ",pixel_format=" + pixelFormatName + ..
			",samples=" + SpriteBenchmarkSamples
		SpriteBenchmarkHousekeeping()
		For Local caseId:Int = 0 Until SpriteBenchmarkCaseCount
			RunCase(caseId)
		Next
	End Method

	Method RunCase(caseId:Int)
		Local iterations:Int = CaseIterations(caseId)
		For Local warmup:Int = 0 Until SpriteBenchmarkWarmups
			PrepareCase()
			ExecuteCase(caseId, iterations)
		Next

		Local best:ULong = $ffffffffffffffff:ULong
		Local total:ULong
		For Local sample:Int = 0 Until SpriteBenchmarkSamples
			PrepareCase()
			Local started:ULong = MonotonicMicroseconds()
			ExecuteCase(caseId, iterations)
			Local elapsed:ULong = MonotonicMicroseconds() - started
			Local checksum:UInt = ResultChecksum()
			samples[sample] = elapsed
			checksums[sample] = checksum
			total :+ elapsed
			If elapsed < best Then best = elapsed
			SpriteBenchmarkHousekeeping()
		Next
		For Local sample:Int = 1 Until SpriteBenchmarkSamples
			If checksums[sample] <> checksums[0] Then ..
				RuntimeError "Sprite benchmark checksum changed between samples"
		Next
		For Local sample:Int = 0 Until SpriteBenchmarkSamples
			Print "G2D_SPRITE_BENCH,format=" + SpriteBenchmarkFormat + ",kind=sample" + ..
				",platform=" + SpriteBenchmarkPlatform + ",width=" + frame.Width() + ..
				",height=" + frame.Height() + ",pixel_format=" + pixelFormatName + ..
				",case=" + CaseName(caseId) + ",sample=" + sample + ..
				",iterations=" + iterations + ",us=" + samples[sample] + ..
				",checksum=" + checksums[0]
		Next
		Print "G2D_SPRITE_BENCH,format=" + SpriteBenchmarkFormat + ",kind=summary" + ..
			",platform=" + SpriteBenchmarkPlatform + ",width=" + frame.Width() + ..
			",height=" + frame.Height() + ",pixel_format=" + pixelFormatName + ..
			",case=" + CaseName(caseId) + ",iterations=" + iterations + ..
			",best_us=" + best + ",mean_us=" + (total / SpriteBenchmarkSamples) + ..
			",checksum=" + checksums[0]
		SpriteBenchmarkHousekeeping()
	End Method

	Method PrepareCase()
		frame.Clear($18304a)
		graphics.SetRotation(GraphicsRotation0)
		graphics.SetOrigin(0, 0)
		graphics.ResetViewport()
		graphics.SetColorValue($ffffff)
		player.Reset()
		resultValue = 0
	End Method

	Method ExecuteCase(caseId:Int, iterations:Int)
		Local width:Int = frame.Width()
		Local height:Int = frame.Height()
		Select caseId
			Case 0
				For Local index:Int = 0 Until iterations
					opaqueSheet.Draw(graphics, index & 3, 8 + (index * 13) Mod (width - 16), ..
						8 + (index * 7) Mod (height - 16))
				Next
			Case 1
				For Local index:Int = 0 Until iterations
					opaqueSheet.Draw(graphics, index & 3, 8 + (index * 13) Mod (width - 16), ..
						8 + (index * 7) Mod (height - 16), ImageFlipX)
				Next
			Case 2
				graphics.SetColorValue($70d0ff)
				For Local index:Int = 0 Until iterations
					opaqueSheet.Draw(graphics, index & 3, 8 + (index * 13) Mod (width - 16), ..
						8 + (index * 7) Mod (height - 16))
				Next
			Case 3
				For Local index:Int = 0 Until iterations
					opaqueSheet.Draw(graphics, index & 3, 8 + (index * 13) Mod (width - 16), ..
						8 + (index * 7) Mod (height - 16), 0, 128)
				Next
			Case 4
				For Local index:Int = 0 Until iterations
					maskedSheet.Draw(graphics, index & 3, 8 + (index * 13) Mod (width - 16), ..
						8 + (index * 7) Mod (height - 16))
				Next
			Case 5
				For Local index:Int = 0 Until iterations
					maskedSheet.Draw(graphics, index & 3, 8 + (index * 13) Mod (width - 16), ..
						8 + (index * 7) Mod (height - 16), ImageFlipX)
				Next
			Case 6
				graphics.SetColorValue($70d0ff)
				For Local index:Int = 0 Until iterations
					maskedSheet.Draw(graphics, index & 3, 8 + (index * 13) Mod (width - 16), ..
						8 + (index * 7) Mod (height - 16))
				Next
			Case 7
				For Local index:Int = 0 Until iterations
					maskedSheet.Draw(graphics, index & 3, 8 + (index * 13) Mod (width - 16), ..
						8 + (index * 7) Mod (height - 16), 0, 128)
				Next
			Case 8
				For Local index:Int = 0 Until iterations
					resultValue :+ UInt(animation.FrameAtTime(Long(index) * 43, True) + 1)
				Next
			Case 9
				For Local index:Int = 0 Until iterations
					player.Advance((index & 15) + 1)
					resultValue :+ UInt(player.CurrentFrame() + 1)
				Next
			Case 10
				For Local pass:Int = 0 Until iterations
					For Local sprite:Int = 0 Until 24
						opaqueSheet.Draw(graphics, (sprite + pass) & 3, ..
							12 + (sprite Mod 8) * 18, 12 + (sprite / 8) * 24)
					Next
				Next
			Case 11
				For Local pass:Int = 0 Until iterations
					For Local sprite:Int = 0 Until 24
						maskedSheet.Draw(graphics, (sprite + pass) & 3, ..
							12 + (sprite Mod 8) * 18, 12 + (sprite / 8) * 24)
					Next
				Next
			Case 12
				For Local index:Int = 0 Until iterations
					player.Advance(17)
					player.Draw(graphics, 8 + (index * 13) Mod (width - 16), ..
						8 + (index * 7) Mod (height - 16))
				Next
		End Select
	End Method

	Method ResultChecksum:UInt()
		Local pixels:Byte Ptr = frame.Pixels()
		Local checksum:UInt = $811c9dc5:UInt
		For Local index:Int = 0 Until frame.Size()
			checksum :~ UInt(pixels[index])
			checksum :* 16777619
		Next
		checksum :~ resultValue
		checksum :* 16777619
		Return checksum
	End Method

	Method CaseName:String(caseId:Int)
		Select caseId
			Case 0 Return "sheet_opaque_16x16"
			Case 1 Return "sheet_flip_x_16x16"
			Case 2 Return "sheet_tinted_16x16"
			Case 3 Return "sheet_alpha_16x16"
			Case 4 Return "masked_opaque_16x16"
			Case 5 Return "masked_flip_x_16x16"
			Case 6 Return "masked_tinted_16x16"
			Case 7 Return "masked_alpha_16x16"
			Case 8 Return "animation_frame_lookup"
			Case 9 Return "player_advance_lookup"
			Case 10 Return "scene_24_opaque"
			Case 11 Return "scene_24_masked"
			Case 12 Return "player_animated_draw"
		End Select
		Return "unknown"
	End Method

	Method CaseIterations:Int(caseId:Int)
		Local iterations:Int = 512
		Select caseId
			Case 8, 9 iterations = 8192
			Case 10, 11 iterations = 64
		End Select
		If frame.Format() = DisplayPixelFormatMono1 Then
			If caseId = 10 Or caseId = 11 Then Return 1
			If caseId <> 8 And caseId <> 9 Then Return 8
		End If
		Return iterations
	End Method
End Type

Function CreateSpriteBenchmarkAtlas:Byte[](masked:Int)
	Const width:Int = 64
	Const height:Int = 16
	Const headerSize:Int = 32
	Local pixelBytes:Int = width * height * 2
	Local maskStride:Int
	Local maskOffset:Int
	If masked Then
		maskStride = width / 8
		maskOffset = headerSize + pixelBytes
	End If
	Local data:Byte[] = New Byte[headerSize + pixelBytes + maskStride * height]
	data[0] = Asc("E"); data[1] = Asc("B"); data[2] = Asc("I"); data[3] = Asc("1")
	PutSpriteBenchmarkU16(data, 4, EmbeddedImageVersion)
	If masked Then PutSpriteBenchmarkU16(data, 6, EmbeddedImageFlagMask)
	PutSpriteBenchmarkU16(data, 8, width)
	PutSpriteBenchmarkU16(data, 10, height)
	PutSpriteBenchmarkU16(data, 12, DisplayPixelFormatRGB565)
	PutSpriteBenchmarkU16(data, 14, EmbeddedImageEncodingRaw)
	PutSpriteBenchmarkU32(data, 16, width * 2)
	PutSpriteBenchmarkU32(data, 20, headerSize)
	PutSpriteBenchmarkU32(data, 24, maskStride)
	PutSpriteBenchmarkU32(data, 28, maskOffset)
	For Local y:Int = 0 Until height
		For Local x:Int = 0 Until width
			Local frame:Int = x / 16
			Local localX:Int = x & 15
			Local red:UInt = UInt((localX * 13 + frame * 47) & 255)
			Local green:UInt = UInt((y * 15 + frame * 31) & 255)
			Local blue:UInt = UInt(((localX ~ y) * 17 + frame * 23) & 255)
			Local rgb565:UInt = ((red Shr 3) Shl 11) | ((green Shr 2) Shl 5) | (blue Shr 3)
			Local offset:Int = headerSize + (y * width + x) * 2
			data[offset] = Byte(rgb565)
			data[offset + 1] = Byte(rgb565 Shr 8)
			If masked Then
				Local dx:Int = localX - 7
				Local dy:Int = y - 7
				If dx * dx + dy * dy <= 55 Or ((localX + y + frame) Mod 7 = 0) Then
					Local maskByte:Int = maskOffset + y * maskStride + x / 8
					data[maskByte] :| Byte($80 Shr (x & 7))
				End If
			End If
		Next
	Next
	Return data
End Function

Function PutSpriteBenchmarkU16(data:Byte[], offset:Int, value:Int)
	data[offset] = Byte(value)
	data[offset + 1] = Byte(value Shr 8)
End Function

Function PutSpriteBenchmarkU32(data:Byte[], offset:Int, value:Int)
	data[offset] = Byte(value)
	data[offset + 1] = Byte(value Shr 8)
	data[offset + 2] = Byte(value Shr 16)
	data[offset + 3] = Byte(value Shr 24)
End Function
