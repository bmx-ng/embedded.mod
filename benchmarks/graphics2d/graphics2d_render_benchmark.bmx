' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time
Import "graphics2d_benchmark_core.bmx"

Const BenchmarkWidth:Int = 160
Const BenchmarkHeight:Int = 128

' Allow a serial monitor to reconnect after upload before emitting the one-shot report.
SleepMicroseconds(3000000)

Local rgb565:TGraphics2DBenchmark = TGraphics2DBenchmark.Create(BenchmarkWidth, ..
	BenchmarkHeight, DisplayPixelFormatRGB565)
If Not rgb565 Then RuntimeError "Unable to create RGB565 Graphics2D benchmark"
rgb565.RunRenderSuite()

Local mono1:TGraphics2DBenchmark = TGraphics2DBenchmark.Create(BenchmarkWidth, ..
	BenchmarkHeight, DisplayPixelFormatMono1)
If Not mono1 Then RuntimeError "Unable to create Mono1 Graphics2D benchmark"
mono1.RunRenderSuite()

Print "G2D_BENCH,format=" + GraphicsBenchmarkFormat + ",kind=done"

' Keep USB service active so the board can be reset or replaced after capture.
While True
	SleepMicroseconds(1000000)
Wend
