' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import "graphics2d_benchmark_core.bmx"

Const BenchmarkWidth:Int = 160
Const BenchmarkHeight:Int = 128

' Allow a serial monitor to reconnect after upload before emitting the one-shot report.
SleepMicroseconds(3000000)

Function RunFormat(pixelFormat:Int, formatName:String)
	Local benchmark:TGraphics2DBenchmark = TGraphics2DBenchmark.Create(BenchmarkWidth, ..
		BenchmarkHeight, pixelFormat)
	If Not benchmark Then RuntimeError "Unable to create " + formatName + " Graphics2D benchmark"
	benchmark.RunRenderSuite()
	benchmark = Null
	CollectObjects()
End Function

RunFormat(DisplayPixelFormatRGB565, "RGB565")
RunFormat(DisplayPixelFormatMono1, "Mono1")

Print "G2D_BENCH,format=" + GraphicsBenchmarkFormat + ",kind=done"

' Keep USB service active so the board can be reset or replaced after capture.
While True
	SleepMicroseconds(1000000)
Wend
