' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import ESP32.Drivers.Displays.RGB
Import "graphics2d_benchmark_core.bmx"

' Allow a serial monitor to reconnect after upload before emitting the report.
Delay 3000

Local display:TESP32RGBDisplay = TESP32RGBDisplay.Create(ESP32S31Korvo1ST7262Config())
If Not display Then RuntimeError "Could not initialize RGB display: " + RGBDisplayLastError()

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Could not access RGB display framebuffer"

Local benchmark:TGraphics2DBenchmark = TGraphics2DBenchmark.CreateWithBuffer(frame)
If Not benchmark Then RuntimeError "Could not create Graphics2D presentation benchmark"
benchmark.RunPresentationSuite(display)

Print "G2D_BENCH,format=" + GraphicsBenchmarkFormat + ",kind=done,phase=present"

While True
	Delay 1000
Wend
