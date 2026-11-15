' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import "graphics2d_sprite_benchmark_core.bmx"

Const SpriteBenchmarkWidth:Int = 160
Const SpriteBenchmarkHeight:Int = 128

' Allow a serial monitor to reconnect after upload before emitting the one-shot report.
SleepMicroseconds(3000000)

Function RunSpriteFormat(pixelFormat:Int, formatName:String)
	Local benchmark:TGraphics2DSpriteBenchmark = TGraphics2DSpriteBenchmark.Create(..
		SpriteBenchmarkWidth, SpriteBenchmarkHeight, pixelFormat)
	If Not benchmark Then RuntimeError "Unable to create " + formatName + " sprite benchmark"
	benchmark.Run()
	benchmark = Null
	CollectObjects()
End Function

RunSpriteFormat(DisplayPixelFormatRGB565, "RGB565")
RunSpriteFormat(DisplayPixelFormatMono1, "Mono1")

Print "G2D_SPRITE_BENCH,format=" + SpriteBenchmarkFormat + ",kind=done"

While True
	SleepMicroseconds(1000000)
Wend
