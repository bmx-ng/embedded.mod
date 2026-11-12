SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display

Local passed:Int = True

passed :& DisplayPixelFormatBits(DisplayPixelFormatMono1) = 1
passed :& DisplayPixelFormatBits(DisplayPixelFormatRGB565) = 16
passed :& DisplayPixelFormatBits(DisplayPixelFormatRGB888) = 24
passed :& DisplayMinimumStride(9, DisplayPixelFormatMono1) = 2
passed :& DisplayMinimumStride(3, DisplayPixelFormatRGB565) = 6
passed :& DisplayMinimumStride(3, DisplayPixelFormatRGB888) = 9

Local mono:TDisplayBuffer = TDisplayBuffer.Create(10, 4, DisplayPixelFormatMono1)
passed :& mono <> Null And mono.Size() = 8
mono.SetPixel(0, 0)
mono.SetPixel(9, 3)
passed :& mono.Pixel(0, 0) = 1 And mono.Pixel(9, 3) = 1
passed :& mono.Pixel(1, 0) = 0 And mono.Pixel(8, 3) = 0
mono.Clear()
passed :& mono.Pixel(0, 0) = 0 And mono.Pixel(9, 3) = 0
mono.FillRect(-2, -1, 5, 3)
passed :& mono.Pixel(0, 0) = 1 And mono.Pixel(2, 1) = 1
passed :& mono.Pixel(3, 1) = 0 And mono.Pixel(0, 2) = 0
mono.Clear()
mono.DrawLine(0, 0, 3, 3)
passed :& mono.Pixel(0, 0) = 1 And mono.Pixel(1, 1) = 1
passed :& mono.Pixel(2, 2) = 1 And mono.Pixel(3, 3) = 1

Local rgb565:TDisplayBuffer = TDisplayBuffer.Create(2, 1, DisplayPixelFormatRGB565)
rgb565.SetPixel(0, 0, $ff0000)
rgb565.SetPixel(1, 0, $00ff00)
passed :& rgb565.Pixel(0, 0) = $ff0000
passed :& rgb565.Pixel(1, 0) = $00ff00

Local rgb888:TDisplayBuffer = TDisplayBuffer.Create(1, 1, DisplayPixelFormatRGB888)
rgb888.SetPixel(0, 0, $123456)
passed :& rgb888.Pixel(0, 0) = $123456

Local externalBytes:Byte[] = New Byte[12]
Local external:TDisplayBuffer = TDisplayBuffer.CreateExternal(3, 2, DisplayPixelFormatRGB565, ..
	Varptr externalBytes[0], 6)
passed :& external <> Null And external.Size() = 12 And external.Bytes() = Null
external.SetPixel(1, 1, $ff0000)
passed :& external.Pixel(1, 1) = $ff0000
passed :& externalBytes[8] = 0 And (Int(externalBytes[9]) & $ff) = $f8
passed :& TDisplayBuffer.CreateExternal(3, 2, DisplayPixelFormatRGB565, ..
	Varptr externalBytes[0], 5) = Null

If passed Then
	Print "Embedded display conformance test passed"
Else
	Print "Embedded display conformance test failed"
End If
