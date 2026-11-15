' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import ESP32.Drivers.Displays.RGB
Import "ui_frame_benchmark_core.bmx"

' Allow a serial monitor to reconnect after upload before emitting the report.
Delay 3000

Local displayConfig:TESP32RGBDisplayConfig = ESP32S31Korvo1ST7262Config()
displayConfig.framebufferCount = 2
Local display:TESP32RGBDisplay = TESP32RGBDisplay.Create(displayConfig)
If Not display Then RuntimeError "Could not initialize RGB display: " + RGBDisplayLastError()

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Could not access RGB display framebuffer"

Local benchmark:TUIFrameBenchmark = TUIFrameBenchmark.Create(display, frame)
If Not benchmark Then RuntimeError "Could not create UI frame benchmark"
benchmark.RunSuite()

Print "G2D_BENCH,format=" + UIFrameBenchmarkFormat + ",kind=done,phase=ui_frame"

While True
	Delay 1000
Wend
