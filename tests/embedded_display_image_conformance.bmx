SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Image
Import Embedded.Graphics2D

Function PutU16(data:Byte[], offset:Int, value:Int)
	data[offset] = Byte(value)
	data[offset + 1] = Byte(value Shr 8)
End Function

Function PutU32(data:Byte[], offset:Int, value:Int)
	data[offset] = Byte(value)
	data[offset + 1] = Byte(value Shr 8)
	data[offset + 2] = Byte(value Shr 16)
	data[offset + 3] = Byte(value Shr 24)
End Function

Function Header(data:Byte[], flags:Int, width:Int, height:Int, format:Int, stride:Int, ..
		pixelOffset:Int, maskStride:Int = 0, maskOffset:Int = 0)
	data[0] = Asc("E")
	data[1] = Asc("B")
	data[2] = Asc("I")
	data[3] = Asc("1")
	PutU16(data, 4, 1)
	PutU16(data, 6, flags)
	PutU16(data, 8, width)
	PutU16(data, 10, height)
	PutU16(data, 12, format)
	PutU16(data, 14, 0)
	PutU32(data, 16, stride)
	PutU32(data, 20, pixelOffset)
	PutU32(data, 24, maskStride)
	PutU32(data, 28, maskOffset)
End Function

Local passed:Int = True

' Red, green / blue, white.
Local rgbData:Byte[] = New Byte[44]
Header(rgbData, 0, 2, 2, DisplayPixelFormatRGB888, 6, 32)
rgbData[32] = $ff
rgbData[36] = $ff
rgbData[40] = $ff
rgbData[41] = $ff
rgbData[42] = $ff
rgbData[43] = $ff
Local image:TEmbeddedImage = TEmbeddedImage.Create(Varptr rgbData[0], rgbData.length)
passed :& image <> Null And image.Width() = 2 And image.Height() = 2
passed :& image.Format() = DisplayPixelFormatRGB888 And Not image.HasMask()

' Indexed pixels use an exact RGB888 palette held directly before the pixels.
Local indexedData:Byte[] = New Byte[46]
Header(indexedData, 0, 2, 2, EmbeddedImageFormatIndexed2, 1, 44)
' Red, green, blue, white palette.
indexedData[32] = $ff
indexedData[36] = $ff
indexedData[40] = $ff
indexedData[41] = $ff
indexedData[42] = $ff
indexedData[43] = $ff
indexedData[44] = $10 ' indices 0, 1
indexedData[45] = $b0 ' indices 2, 3
Local indexedImage:TEmbeddedImage = TEmbeddedImage.Create(Varptr indexedData[0], indexedData.length)
passed :& indexedImage <> Null And indexedImage.IsIndexed() And indexedImage.PaletteSize() = 4
passed :& indexedImage.Format() = EmbeddedImageFormatIndexed2
Local indexedTarget:TDisplayBuffer = TDisplayBuffer.Create(4, 4, DisplayPixelFormatRGB565)
indexedImage.DrawRect(indexedTarget, 0, 0, 4, 4)
passed :& indexedTarget.Pixel(0, 0) = $ff0000 And indexedTarget.Pixel(3, 0) = $00ff00
passed :& indexedTarget.Pixel(0, 3) = $0000ff And indexedTarget.Pixel(3, 3) = $ffffff

' All packed index widths use the same most-significant-bit-first row layout.
Local indexed1Data:Byte[] = New Byte[39]
Header(indexed1Data, 0, 2, 1, EmbeddedImageFormatIndexed1, 1, 38)
indexed1Data[35] = $ff; indexed1Data[36] = $ff; indexed1Data[37] = $ff
indexed1Data[38] = $40
Local indexed1:TEmbeddedImage = TEmbeddedImage.Create(Varptr indexed1Data[0], indexed1Data.length)
Local indexedWidthsTarget:TDisplayBuffer = TDisplayBuffer.Create(2, 3, DisplayPixelFormatRGB888)
indexed1.Draw(indexedWidthsTarget, 0, 0)
passed :& indexedWidthsTarget.Pixel(0, 0) = 0 And indexedWidthsTarget.Pixel(1, 0) = $ffffff

Local indexed4Data:Byte[] = New Byte[42]
Header(indexed4Data, 0, 2, 1, EmbeddedImageFormatIndexed4, 1, 41)
indexed4Data[32] = $ff; indexed4Data[36] = $ff; indexed4Data[40] = $ff
indexed4Data[41] = $12
Local indexed4:TEmbeddedImage = TEmbeddedImage.Create(Varptr indexed4Data[0], indexed4Data.length)
indexed4.Draw(indexedWidthsTarget, 0, 1)
passed :& indexedWidthsTarget.Pixel(0, 1) = $00ff00 And indexedWidthsTarget.Pixel(1, 1) = $0000ff

Local indexed8Data:Byte[] = New Byte[40]
Header(indexed8Data, 0, 2, 1, EmbeddedImageFormatIndexed8, 2, 38)
indexed8Data[32] = $ff; indexed8Data[37] = $ff
indexed8Data[38] = 0; indexed8Data[39] = 1
Local indexed8:TEmbeddedImage = TEmbeddedImage.Create(Varptr indexed8Data[0], indexed8Data.length)
indexed8.Draw(indexedWidthsTarget, 0, 2)
passed :& indexedWidthsTarget.Pixel(0, 2) = $ff0000 And indexedWidthsTarget.Pixel(1, 2) = $0000ff

' The native RGB565 path preserves clipping, nearest-neighbour scaling, and flips.
Local rgb565Data:Byte[] = New Byte[40]
Header(rgb565Data, 0, 2, 2, DisplayPixelFormatRGB565, 4, 32)
rgb565Data[32] = $00; rgb565Data[33] = $f8
rgb565Data[34] = $e0; rgb565Data[35] = $07
rgb565Data[36] = $1f; rgb565Data[37] = $00
rgb565Data[38] = $ff; rgb565Data[39] = $ff
Local rgb565Image:TEmbeddedImage = TEmbeddedImage.Create(Varptr rgb565Data[0], rgb565Data.length)
Local rgb565Scaled:TDisplayBuffer = TDisplayBuffer.Create(5, 4, DisplayPixelFormatRGB565)
rgb565Scaled.Clear($112233)
rgb565Image.DrawRectClipped(rgb565Scaled, 0, 0, 4, 4, $ffffff, 1, 0, 3, 4)
passed :& rgb565Scaled.Pixel(0, 0) = $102031 And rgb565Scaled.Pixel(4, 3) = $102031
passed :& rgb565Scaled.Pixel(1, 0) = $ff0000 And rgb565Scaled.Pixel(2, 0) = $00ff00
passed :& rgb565Scaled.Pixel(1, 3) = $0000ff And rgb565Scaled.Pixel(3, 3) = $ffffff
rgb565Scaled.Clear()
rgb565Image.DrawRect(rgb565Scaled, 0, 0, 4, 4, $ffffff, EmbeddedImageDrawFlipX)
passed :& rgb565Scaled.Pixel(0, 0) = $00ff00 And rgb565Scaled.Pixel(3, 0) = $ff0000

' RGB565 targets use the native conversion, tint, and exact opacity path.
Local rgb565Composited:TDisplayBuffer = TDisplayBuffer.Create(2, 1, DisplayPixelFormatRGB565)
rgb565Composited.Clear($0000ff)
image.DrawRegion(rgb565Composited, 0, 0, 0, 0, 2, 1, $ffffff, 0, 128)
passed :& rgb565Composited.Pixel(0, 0) = $84007b And rgb565Composited.Pixel(1, 0) = $00827b
rgb565Composited.Clear()
image.DrawRegion(rgb565Composited, 0, 0, 0, 0, 2, 1, $80ffff)
passed :& rgb565Composited.Pixel(0, 0) = $840000 And rgb565Composited.Pixel(1, 0) = $00ff00

Local rgb565:TDisplayBuffer = TDisplayBuffer.Create(2, 2, DisplayPixelFormatRGB565)
image.Draw(rgb565, 0, 0)
passed :& rgb565.Pixel(0, 0) = $ff0000 And rgb565.Pixel(1, 0) = $00ff00
passed :& rgb565.Pixel(0, 1) = $0000ff And rgb565.Pixel(1, 1) = $ffffff

Local scaled:TDisplayBuffer = TDisplayBuffer.Create(4, 4, DisplayPixelFormatRGB888)
SetRenderTarget scaled
SetColor 255, 255, 255
DrawImageRect image, 0, 0, 4, 4
passed :& scaled.Pixel(0, 0) = $ff0000 And scaled.Pixel(1, 1) = $ff0000
passed :& scaled.Pixel(2, 0) = $00ff00 And scaled.Pixel(0, 2) = $0000ff
passed :& scaled.Pixel(3, 3) = $ffffff

scaled.Clear()
SetViewport 1, 1, 2, 2
SetColor 128, 255, 255
DrawImageRect image, 0, 0, 4, 4
passed :& scaled.Pixel(0, 0) = 0 And scaled.Pixel(3, 3) = 0
passed :& scaled.Pixel(1, 1) = $800000 And scaled.Pixel(2, 1) = $00ff00

' Rotation is applied to images by the shared Graphics2D canvas view.
Local rotatedImage:TDisplayBuffer = TDisplayBuffer.Create(3, 2, DisplayPixelFormatRGB888)
SetRenderTarget rotatedImage
passed :& SetRotation(90)
SetColor 255, 255, 255
DrawImage image, 0, 0
passed :& GraphicsWidth() = 2 And GraphicsHeight() = 3
passed :& rotatedImage.Pixel(2, 0) = $ff0000 And rotatedImage.Pixel(2, 1) = $00ff00
passed :& rotatedImage.Pixel(1, 0) = $0000ff And rotatedImage.Pixel(1, 1) = $ffffff

' The first pixel is visible red; the second is transparent green.
Local maskedData:Byte[] = New Byte[39]
Header(maskedData, EmbeddedImageFlagMask, 2, 1, DisplayPixelFormatRGB888, 6, 32, 1, 38)
maskedData[32] = $ff
maskedData[36] = $ff
maskedData[38] = $80
Local masked:TEmbeddedImage = TEmbeddedImage.Create(Varptr maskedData[0], maskedData.length)
Local maskedTarget:TDisplayBuffer = TDisplayBuffer.Create(2, 1, DisplayPixelFormatRGB888)
maskedTarget.Clear($0000ff)
masked.Draw(maskedTarget, 0, 0)
passed :& masked <> Null And masked.HasMask()
passed :& maskedTarget.Pixel(0, 0) = $ff0000 And maskedTarget.Pixel(1, 0) = $0000ff

' Flips are source-space operations and may be combined.
Local flipped:TDisplayBuffer = TDisplayBuffer.Create(2, 2, DisplayPixelFormatRGB888)
image.Draw(flipped, 0, 0, $ffffff, EmbeddedImageDrawFlipX)
passed :& flipped.Pixel(0, 0) = $00ff00 And flipped.Pixel(1, 0) = $ff0000
passed :& flipped.Pixel(0, 1) = $ffffff And flipped.Pixel(1, 1) = $0000ff
flipped.Clear()
image.Draw(flipped, 0, 0, $ffffff, EmbeddedImageDrawFlipX | EmbeddedImageDrawFlipY)
passed :& flipped.Pixel(0, 0) = $ffffff And flipped.Pixel(1, 0) = $0000ff
passed :& flipped.Pixel(0, 1) = $00ff00 And flipped.Pixel(1, 1) = $ff0000

' Opacity blends with the existing destination using exact 0..255 coverage.
Local blended:TDisplayBuffer = TDisplayBuffer.Create(2, 1, DisplayPixelFormatRGB888)
blended.Clear($0000ff)
image.DrawRegion(blended, 0, 0, 0, 0, 2, 1, $ffffff, 0, 128)
passed :& blended.Pixel(0, 0) = $80007f And blended.Pixel(1, 0) = $00807f
Local unchanged:UInt = blended.Pixel(0, 0)
image.DrawRegion(blended, 0, 0, 0, 0, 1, 1, $ffffff, 0, 0)
passed :& blended.Pixel(0, 0) = unchanged

' A colour key is compared with the original pixel, before tinting.
Local keyed:TDisplayBuffer = TDisplayBuffer.Create(2, 1, DisplayPixelFormatRGB888)
keyed.Clear($112233)
image.DrawRegion(keyed, 0, 0, 0, 0, 2, 1, $808080, 0, 255, $00ff00)
passed :& keyed.Pixel(0, 0) = $800000 And keyed.Pixel(1, 0) = $112233

' Graphics2D exposes the same options and preserves its view transform.
Local optionCanvas:TDisplayBuffer = TDisplayBuffer.Create(4, 2, DisplayPixelFormatRGB888)
SetRenderTarget optionCanvas
passed :& SetRotation(0)
SetColor 255, 255, 255
DrawImageRect image, 0, 0, 4, 2, ImageFlipX, 128, $00ff00
passed :& optionCanvas.Pixel(0, 0) = 0 And optionCanvas.Pixel(1, 0) = 0
passed :& optionCanvas.Pixel(2, 0) = $800000 And optionCanvas.Pixel(3, 0) = $800000

Local truncated:Byte[] = New Byte[32]
Header(truncated, 0, 2, 2, DisplayPixelFormatRGB888, 6, 32)
passed :& TEmbeddedImage.Create(Varptr truncated[0], truncated.length) = Null
truncated[0] = Asc("X")
passed :& TEmbeddedImage.Create(Varptr truncated[0], truncated.length) = Null

' An index outside the stored palette is rejected during one-time validation.
Local invalidIndexed:Byte[] = New Byte[39]
Header(invalidIndexed, 0, 1, 1, EmbeddedImageFormatIndexed2, 1, 38)
invalidIndexed[32] = $ff
invalidIndexed[35] = $ff
invalidIndexed[38] = $c0
passed :& TEmbeddedImage.Create(Varptr invalidIndexed[0], invalidIndexed.length) = Null

If passed Then
	Print "Embedded display image conformance test passed"
Else
	Print "Embedded display image conformance test failed"
End If
