' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Drivers.Display.Image
Import Embedded.Graphics2D
Import Embedded.System.Time

Const GraphicsBenchmarkFormat:Int = 1
Const GraphicsBenchmarkSamples:Int = 7
Const GraphicsBenchmarkWarmups:Int = 2
Const GraphicsBenchmarkCaseCount:Int = 19
Const GraphicsBenchmarkPresentSamples:Int = 5

Function BenchmarkHousekeeping()
	' A long uninterrupted benchmark can starve an embedded platform's idle task.
	' Keep the cooperative yield outside timed sections.
	Delay 10
End Function

?pico
Const GraphicsBenchmarkPlatform:String = "pico"
?esp32
Const GraphicsBenchmarkPlatform:String = "esp32"
?esp8266
Const GraphicsBenchmarkPlatform:String = "esp8266"
?nrf52
Const GraphicsBenchmarkPlatform:String = "nrf52"
?

Type TGraphics2DBenchmark
	Field frame:TDisplayBuffer
	Field graphics:TEmbedded2DContext
	Field imageData:Byte[]
	Field image:TEmbeddedImage
	Field samples:ULong[] = New ULong[GraphicsBenchmarkSamples]
	Field checksums:UInt[] = New UInt[GraphicsBenchmarkSamples]
	Field renderSamples:ULong[] = New ULong[GraphicsBenchmarkCaseCount * GraphicsBenchmarkSamples]
	Field renderBest:ULong[] = New ULong[GraphicsBenchmarkCaseCount]
	Field renderMean:ULong[] = New ULong[GraphicsBenchmarkCaseCount]
	Field renderChecksums:UInt[] = New UInt[GraphicsBenchmarkCaseCount]
	Field renderIterations:Int[] = New Int[GraphicsBenchmarkCaseCount]
	Field presentX:Int[] = New Int[2]
	Field presentY:Int[] = New Int[2]
	Field presentWidth:Int[] = New Int[2]
	Field presentHeight:Int[] = New Int[2]
	Field pixelFormatName:String

	Function Create:TGraphics2DBenchmark(width:Int, height:Int, pixelFormat:Int)
		If width < 64 Or height < 64 Then Return Null
		Local frame:TDisplayBuffer = TDisplayBuffer.Create(width, height, pixelFormat)
		If Not frame Then Return Null
		Return CreateWithBuffer(frame)
	End Function

	Function CreateWithBuffer:TGraphics2DBenchmark(frame:TDisplayBuffer)
		If Not frame Or frame.Width() < 64 Or frame.Height() < 64 Then Return Null
		Local benchmark:TGraphics2DBenchmark = New TGraphics2DBenchmark
		benchmark.frame = frame
		benchmark.graphics = TEmbedded2DContext.Create(frame)
		If Not benchmark.graphics Then Return Null
		benchmark.graphics.SetDirtyTracking(False)
		benchmark.graphics.SetFont(Spleen5x8Font())
		benchmark.imageData = CreateBenchmarkImageData()
		benchmark.image = TEmbeddedImage.Create(Varptr benchmark.imageData[0], benchmark.imageData.length)
		If Not benchmark.image Then Return Null
		Select frame.Format()
			Case DisplayPixelFormatMono1
				benchmark.pixelFormatName = "mono1"
			Case DisplayPixelFormatRGB565
				benchmark.pixelFormatName = "rgb565"
			Case DisplayPixelFormatRGB888
				benchmark.pixelFormatName = "rgb888"
			Default
				benchmark.pixelFormatName = "unknown"
		End Select
		Return benchmark
	End Function

	Method RunRenderSuite()
		Print "G2D_BENCH,format=" + GraphicsBenchmarkFormat + ",kind=meta,phase=render" + ..
			",platform=" + GraphicsBenchmarkPlatform + ..
			",width=" + frame.Width() + ",height=" + frame.Height() + ..
			",pixel_format=" + pixelFormatName + ",samples=" + GraphicsBenchmarkSamples
		BenchmarkHousekeeping()
		For Local caseId:Int = 0 Until GraphicsBenchmarkCaseCount
			RunRenderCase(caseId)
		Next
		PrintRenderResults()
	End Method

	Method PrintRenderResults()
		For Local caseId:Int = 0 Until GraphicsBenchmarkCaseCount
			Local iterations:Int = renderIterations[caseId]
			For Local sample:Int = 0 Until GraphicsBenchmarkSamples
				Print "G2D_BENCH,format=" + GraphicsBenchmarkFormat + ",kind=sample,phase=render" + ..
					",platform=" + GraphicsBenchmarkPlatform + ",width=" + frame.Width() + ..
					",height=" + frame.Height() + ",pixel_format=" + pixelFormatName + ..
					",case=" + CaseName(caseId) + ..
					",sample=" + sample + ",iterations=" + iterations + ..
					",nominal_pixels=" + CaseNominalPixels(caseId, iterations) + ..
					",us=" + renderSamples[caseId * GraphicsBenchmarkSamples + sample] + ..
					",checksum=" + renderChecksums[caseId]
				BenchmarkHousekeeping()
			Next
			Print "G2D_BENCH,format=" + GraphicsBenchmarkFormat + ",kind=summary,phase=render" + ..
				",platform=" + GraphicsBenchmarkPlatform + ",width=" + frame.Width() + ..
				",height=" + frame.Height() + ",pixel_format=" + pixelFormatName + ..
				",case=" + CaseName(caseId) + ..
				",iterations=" + iterations + ",nominal_pixels=" + ..
				CaseNominalPixels(caseId, iterations) + ..
				",best_us=" + renderBest[caseId] + ",mean_us=" + renderMean[caseId] + ..
				",checksum=" + renderChecksums[caseId]
			BenchmarkHousekeeping()
		Next
	End Method

	Method RunPresentationSuite(display:TDisplay)
		If Not display Or frame.Width() < display.Width() Or frame.Height() < display.Height() Then ..
			RuntimeError "Presentation benchmark requires a matching display buffer"
		PreparePresentation()
		Print "G2D_BENCH,format=" + GraphicsBenchmarkFormat + ",kind=meta,phase=present" + ..
			",platform=" + GraphicsBenchmarkPlatform + ..
			",width=" + display.Width() + ",height=" + display.Height() + ..
			",pixel_format=" + pixelFormatName + ",samples=" + GraphicsBenchmarkPresentSamples + ..
			",capabilities=" + display.Capabilities()
		For Local caseId:Int = 0 Until 4
			RunPresentationCase(display, caseId)
		Next
	End Method

	Method RunPresentationCase(display:TDisplay, caseId:Int)
		If ExecutePresentation(display, caseId) <= 0 Then ..
			RuntimeError "Graphics presentation benchmark warmup failed"
		Local total:ULong
		Local best:ULong = $ffffffffffffffff:ULong
		Local checksum:UInt = FrameChecksum()
		For Local sample:Int = 0 Until GraphicsBenchmarkPresentSamples
			Local started:ULong = MonotonicMicroseconds()
			Local result:Int = ExecutePresentation(display, caseId)
			Local elapsed:ULong = MonotonicMicroseconds() - started
			If result <= 0 Then RuntimeError "Graphics presentation benchmark failed"
			total :+ elapsed
			If elapsed < best Then best = elapsed
			Print "G2D_BENCH,format=" + GraphicsBenchmarkFormat + ",kind=sample,phase=present" + ..
				",platform=" + GraphicsBenchmarkPlatform + ",width=" + display.Width() + ..
				",height=" + display.Height() + ",pixel_format=" + pixelFormatName + ..
				",case=" + PresentationCaseName(caseId) + ..
				",sample=" + sample + ",iterations=1,nominal_pixels=" + ..
				PresentationCasePixels(display, caseId) + ",us=" + elapsed + ..
				",checksum=" + checksum
			BenchmarkHousekeeping()
		Next
		Print "G2D_BENCH,format=" + GraphicsBenchmarkFormat + ",kind=summary,phase=present" + ..
			",platform=" + GraphicsBenchmarkPlatform + ",width=" + display.Width() + ..
			",height=" + display.Height() + ",pixel_format=" + pixelFormatName + ..
			",case=" + PresentationCaseName(caseId) + ..
			",iterations=1,nominal_pixels=" + PresentationCasePixels(display, caseId) + ..
			",best_us=" + best + ",mean_us=" + (total / GraphicsBenchmarkPresentSamples) + ..
			",checksum=" + checksum
		BenchmarkHousekeeping()
	End Method

	Method PreparePresentation()
		graphics.SetRotation(GraphicsRotation0)
		graphics.SetOrigin(0, 0)
		graphics.ResetViewport()
		graphics.SetColorValue($102030)
		graphics.FillRect(0, 0, frame.Width(), frame.Height())
		graphics.SetColorValue($d02030)
		graphics.FillRect(0, 0, frame.Width(), frame.Height() / 3)
		graphics.SetColorValue($20b050)
		graphics.FillRect(0, frame.Height() / 3, frame.Width(), frame.Height() / 3)
		graphics.SetColorValue($3060d0)
		graphics.FillRect(0, (frame.Height() / 3) * 2, frame.Width(), ..
			frame.Height() - (frame.Height() / 3) * 2)
	End Method

	Method ExecutePresentation:Int(display:TDisplay, caseId:Int)
		Local displayWidth:Int = display.Width()
		Local displayHeight:Int = display.Height()
		Select caseId
			Case 0
				Return display.Present(frame)
			Case 1
				Return display.PresentRegion(frame, displayWidth / 4, displayHeight / 4, ..
					displayWidth / 2, displayHeight / 2)
			Case 2
				Local width:Int = 32
				Local height:Int = 32
				If width > displayWidth Then width = displayWidth
				If height > displayHeight Then height = displayHeight
				Return display.PresentRegion(frame, (displayWidth - width) / 2, ..
					(displayHeight - height) / 2, width, height)
			Case 3
				Local width:Int = 32
				Local height:Int = 32
				If width > displayWidth / 2 Then width = displayWidth / 2
				If height > displayHeight / 2 Then height = displayHeight / 2
				presentX[0] = 0
				presentY[0] = 0
				presentWidth[0] = width
				presentHeight[0] = height
				presentX[1] = displayWidth - width
				presentY[1] = displayHeight - height
				presentWidth[1] = width
				presentHeight[1] = height
				Return display.PresentRegions(frame, Varptr presentX[0], Varptr presentY[0], ..
					Varptr presentWidth[0], Varptr presentHeight[0], 2)
		End Select
		Return DisplayErrorInvalidArgument
	End Method

	Method PresentationCaseName:String(caseId:Int)
		Select caseId
			Case 0 Return "full_frame"
			Case 1 Return "center_half"
			Case 2 Return "center_32x32"
			Case 3 Return "two_32x32_regions"
		End Select
		Return "unknown"
	End Method

	Method PresentationCasePixels:Long(display:TDisplay, caseId:Int)
		Select caseId
			Case 0 Return Long(display.Width()) * display.Height()
			Case 1 Return Long(display.Width() / 2) * (display.Height() / 2)
			Case 2 Return Long(MinimumInt(32, display.Width())) * MinimumInt(32, display.Height())
			Case 3 Return Long(MinimumInt(32, display.Width() / 2)) * ..
				MinimumInt(32, display.Height() / 2) * 2
		End Select
		Return 0
	End Method

	Method RunRenderCase(caseId:Int)
		Local iterations:Int = CaseIterations(caseId)
		For Local warmup:Int = 0 Until GraphicsBenchmarkWarmups
			PrepareCase(caseId)
			ExecuteCase(caseId, iterations)
		Next

		Local total:ULong
		Local best:ULong = $ffffffffffffffff:ULong
		For Local sample:Int = 0 Until GraphicsBenchmarkSamples
			PrepareCase(caseId)
			Local started:ULong = MonotonicMicroseconds()
			ExecuteCase(caseId, iterations)
			Local elapsed:ULong = MonotonicMicroseconds() - started
			Local checksum:UInt = FrameChecksum()
			samples[sample] = elapsed
			checksums[sample] = checksum
			total :+ elapsed
			If elapsed < best Then best = elapsed
			renderSamples[caseId * GraphicsBenchmarkSamples + sample] = elapsed
			BenchmarkHousekeeping()
		Next
		For Local sample:Int = 1 Until GraphicsBenchmarkSamples
			If checksums[sample] <> checksums[0] Then RuntimeError "Graphics benchmark checksum changed between samples"
		Next
		renderIterations[caseId] = iterations
		renderBest[caseId] = best
		renderMean[caseId] = total / GraphicsBenchmarkSamples
		renderChecksums[caseId] = checksums[0]
		BenchmarkHousekeeping()
	End Method

	Method PrepareCase(caseId:Int)
		graphics.SetRotation(GraphicsRotation0)
		graphics.SetOrigin(0, 0)
		graphics.ResetViewport()
		graphics.SetFont(Spleen5x8Font())
		graphics.SetColorValue($ffffff)
		If frame.Format() = DisplayPixelFormatMono1 Then
			frame.Clear($000000)
		Else
			frame.Clear($102030)
			If caseId = 12 Then frame.Clear($315a7d)
		End If
	End Method

	Method ExecuteCase(caseId:Int, iterations:Int)
		Local width:Int = frame.Width()
		Local height:Int = frame.Height()
		Select caseId
			Case 0
				For Local index:Int = 0 Until iterations
					frame.Clear(UInt(index * $010307) & $ffffff)
				Next
			Case 1
				For Local index:Int = 0 Until iterations
					graphics.SetColorValue(UInt(index * $030507) & $ffffff)
					graphics.FillRect(0, 0, width, height)
				Next
			Case 2
				For Local index:Int = 0 Until iterations
					graphics.SetColorValue(UInt(index * $070b0d) & $ffffff)
					graphics.FillRect((index * 13) Mod (width - 24), ..
						(index * 7) Mod (height - 16), 24, 16)
				Next
			Case 3
				For Local index:Int = 0 Until iterations
					graphics.DrawLine(0, index Mod height, width - 1, index Mod height)
				Next
			Case 4
				For Local index:Int = 0 Until iterations
					Local y:Int = (index * 11) Mod height
					graphics.DrawLine(0, y, width - 1, height - 1 - y)
				Next
			Case 5
				For Local index:Int = 0 Until iterations
					Local x:Int = (index * 7) Mod (width - 42)
					Local y:Int = (index * 5) Mod (height - 30)
					graphics.DrawRect(x, y, 42, 30)
				Next
			Case 6
				For Local index:Int = 0 Until iterations
					graphics.DrawCircle(16 + (index * 17) Mod (width - 32), ..
						16 + (index * 11) Mod (height - 32), 15)
				Next
			Case 7
				For Local index:Int = 0 Until iterations
					graphics.FillCircle(14 + (index * 17) Mod (width - 28), ..
						14 + (index * 11) Mod (height - 28), 13)
				Next
			Case 8
				For Local index:Int = 0 Until iterations
					graphics.DrawText("Graphics2D 012345", (index * 3) Mod 24, ..
						(index * 9) Mod (height - 8))
				Next
			Case 9
				graphics.SetColorValue($ffffff)
				For Local index:Int = 0 Until iterations
					graphics.DrawImage(image, (index * 13) Mod (width - 16), ..
						(index * 7) Mod (height - 16))
				Next
			Case 10
				graphics.SetColorValue($ffffff)
				For Local index:Int = 0 Until iterations
					graphics.DrawImageRect(image, (index * 13) Mod (width - 32), ..
						(index * 7) Mod (height - 32), 32, 32)
				Next
			Case 11
				graphics.SetColorValue($80d0ff)
				For Local index:Int = 0 Until iterations
					graphics.DrawImage(image, (index * 13) Mod (width - 16), ..
						(index * 7) Mod (height - 16))
				Next
			Case 12
				graphics.SetColorValue($ffffff)
				For Local index:Int = 0 Until iterations
					graphics.DrawImage(image, (index * 13) Mod (width - 16), ..
						(index * 7) Mod (height - 16), 0, 128)
				Next
			Case 13
				graphics.SetRotation(GraphicsRotation90)
				Local logicalWidth:Int = graphics.Width()
				Local logicalHeight:Int = graphics.Height()
				For Local index:Int = 0 Until iterations
					graphics.SetColorValue(UInt(index * $030507) & $ffffff)
					graphics.FillRect((index * 13) Mod (logicalWidth - 24), ..
						(index * 7) Mod (logicalHeight - 16), 24, 16)
				Next
			Case 14
				For Local index:Int = 0 Until iterations
					graphics.DrawText("Graphics2D 012345", (index * 3) Mod 24, ..
						(index * 9) Mod (height - 24), 3)
				Next
			Case 15
				For Local index:Int = 0 Until iterations
					graphics.DrawArc(width / 2, height / 2, 24, 135, 270, 8)
				Next
			Case 16
				graphics.SetRotation(GraphicsRotation90)
				For Local index:Int = 0 Until iterations
					graphics.DrawArc(graphics.Width() / 2, graphics.Height() / 2, ..
						24, 135, 270, 8)
				Next
			Case 17
				For Local index:Int = 0 Until iterations
					graphics.DrawRoundRect((index * 13) Mod (width - 48), ..
						(index * 7) Mod (height - 28), 48, 28, 8)
				Next
			Case 18
				For Local index:Int = 0 Until iterations
					graphics.SetColorValue(UInt(index * $030507) & $ffffff)
					graphics.FillRoundRect((index * 13) Mod (width - 48), ..
						(index * 7) Mod (height - 28), 48, 28, 8)
				Next
		End Select
	End Method

	Method FrameChecksum:UInt()
		Local pixels:Byte Ptr = frame.Pixels()
		Local checksum:UInt = $811c9dc5:UInt
		For Local index:Int = 0 Until frame.Size()
			checksum :~ UInt(pixels[index])
			checksum :* 16777619
		Next
		Return checksum
	End Method

	Method CaseName:String(caseId:Int)
		Select caseId
			Case 0 Return "buffer_clear"
			Case 1 Return "fill_full"
			Case 2 Return "fill_24x16"
			Case 3 Return "line_horizontal"
			Case 4 Return "line_diagonal"
			Case 5 Return "rect_outline_42x30"
			Case 6 Return "circle_outline_r15"
			Case 7 Return "circle_fill_r13"
			Case 8 Return "text_spleen_5x8"
			Case 9 Return "image_rgb565_16x16"
			Case 10 Return "image_scaled_32x32"
			Case 11 Return "image_tinted_16x16"
			Case 12 Return "image_alpha_16x16"
			Case 13 Return "fill_24x16_rot90"
			Case 14 Return "text_spleen_5x8_scale3"
			Case 15 Return "arc_270_w8"
			Case 16 Return "arc_270_w8_rot90"
			Case 17 Return "round_rect_outline_48x28_r8"
			Case 18 Return "round_rect_fill_48x28_r8"
		End Select
		Return "unknown"
	End Method

	Method CaseIterations:Int(caseId:Int)
		Local iterations:Int
		Select caseId
			Case 0, 1 iterations = 32
			Case 2 iterations = 192
			Case 3, 4 iterations = 128
			Case 5, 6 iterations = 96
			Case 7 iterations = 48
			Case 8, 14 iterations = 64
			Case 9, 11, 12 iterations = 128
			Case 10 iterations = 64
			Case 13 iterations = 192
			Case 15, 16 iterations = 32
			Case 17 iterations = 96
			Case 18 iterations = 48
		End Select
		If iterations = 0 Then iterations = 1
		' Mono1 uses generic colour conversion and bit-addressed writes. Keep a
		' single timed batch below embedded watchdog intervals while preserving
		' enough work for stable microsecond measurements.
		If frame.Format() = DisplayPixelFormatMono1 Then
			If (caseId >= 8 And caseId <= 12) Or caseId = 14 Then
				iterations = 1
			Else
				iterations :/ 16
			End If
			If iterations < 1 Then iterations = 1
		End If
		Return iterations
	End Method

	Method CaseNominalPixels:Long(caseId:Int, iterations:Int)
		Select caseId
			Case 0, 1 Return Long(frame.Width()) * frame.Height() * iterations
			Case 2, 13 Return Long(24 * 16) * iterations
			Case 3 Return Long(frame.Width()) * iterations
			Case 4 Return Long(frame.Width()) * iterations
			Case 5 Return Long((42 + 30) * 2 - 4) * iterations
			Case 7 Return Long(531) * iterations
			Case 8 Return Long(18 * 5 * 8) * iterations
			Case 14 Return Long(18 * 5 * 8 * 9) * iterations
			Case 15, 16 Return Long(904) * iterations
			Case 9, 11, 12 Return Long(16 * 16) * iterations
			Case 10 Return Long(32 * 32) * iterations
		End Select
		Return 0
	End Method
End Type

Function MinimumInt:Int(first:Int, second:Int)
	If first < second Then Return first
	Return second
End Function

Function CreateBenchmarkImageData:Byte[]()
	Const width:Int = 16
	Const height:Int = 16
	Const headerSize:Int = 32
	Local data:Byte[] = New Byte[headerSize + width * height * 2]
	data[0] = Asc("E")
	data[1] = Asc("B")
	data[2] = Asc("I")
	data[3] = Asc("1")
	PutBenchmarkU16(data, 4, EmbeddedImageVersion)
	PutBenchmarkU16(data, 8, width)
	PutBenchmarkU16(data, 10, height)
	PutBenchmarkU16(data, 12, DisplayPixelFormatRGB565)
	PutBenchmarkU16(data, 14, EmbeddedImageEncodingRaw)
	PutBenchmarkU32(data, 16, width * 2)
	PutBenchmarkU32(data, 20, headerSize)
	For Local y:Int = 0 Until height
		For Local x:Int = 0 Until width
			Local red:UInt = UInt(x * 17)
			Local green:UInt = UInt(y * 17)
			Local blue:UInt = UInt((x ~ y) * 17)
			Local rgb565:UInt = ((red Shr 3) Shl 11) | ((green Shr 2) Shl 5) | (blue Shr 3)
			Local offset:Int = headerSize + (y * width + x) * 2
			data[offset] = Byte(rgb565)
			data[offset + 1] = Byte(rgb565 Shr 8)
		Next
	Next
	Return data
End Function

Function PutBenchmarkU16(data:Byte[], offset:Int, value:Int)
	data[offset] = Byte(value)
	data[offset + 1] = Byte(value Shr 8)
End Function

Function PutBenchmarkU32(data:Byte[], offset:Int, value:Int)
	data[offset] = Byte(value)
	data[offset + 1] = Byte(value Shr 8)
	data[offset + 2] = Byte(value Shr 16)
	data[offset + 3] = Byte(value Shr 24)
End Function
