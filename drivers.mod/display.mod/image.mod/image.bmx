' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Compact firmware-resident images and allocation-free raster drawing.
about: EBI1 images contain raw Mono1, RGB565, RGB888, or raw/RLE indexed pixels
and an optional one-bit transparency mask. Images are validated once when opened
and can then be clipped, tinted, converted, or nearest-neighbour scaled while drawing.
End Rem
Module Embedded.Drivers.Display.Image
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Drivers.Display
Import "native/embedded_display_image_raster.c"

Private

Extern "C"
	Function _DisplayBlitRGB565:Int(targetPixels:Byte Ptr, targetStride:Int, ..
		targetWidth:Int, targetHeight:Int, sourcePixels:Byte Ptr, sourceStride:Int, ..
		sourceWidth:Int, sourceHeight:Int, sourceFormat:Int, destinationX:Int, destinationY:Int, ..
		destinationWidth:Int, destinationHeight:Int, clipX:Int, clipY:Int, ..
		clipWidth:Int, clipHeight:Int, tint:UInt, opacity:Int, drawFlags:Int) = ..
		"bmx_embedded_display_blit_rgb565"
	Function _DisplayBlitMaskedRGB565:Int(targetPixels:Byte Ptr, targetStride:Int, ..
		targetWidth:Int, targetHeight:Int, sourcePixels:Byte Ptr, sourceStride:Int, ..
		sourceWidth:Int, sourceHeight:Int, maskPixels:Byte Ptr, maskStride:Int, maskX:Int, ..
		destinationX:Int, destinationY:Int, clipX:Int, clipY:Int, clipWidth:Int, ..
		clipHeight:Int, tint:UInt, opacity:Int, drawFlags:Int) = ..
		"bmx_embedded_display_blit_masked_rgb565"
End Extern

Public

Rem
bbdoc: The Embedded Bitmap Image data-format version accepted by TEmbeddedImage.
End Rem
Const EmbeddedImageVersion:Int = 1

Rem
bbdoc: Identifies image pixels stored directly in packed raster rows.
End Rem
Const EmbeddedImageEncodingRaw:Int = 0

Rem
bbdoc: Identifies indexed image pixels stored as row-based run-length pairs.
End Rem
Const EmbeddedImageEncodingRLE:Int = 1

Rem
bbdoc: Indicates that an EBI1 image contains a one-bit transparency mask.
End Rem
Const EmbeddedImageFlagMask:Int = 1

Rem
bbdoc: Identifies one-bit indexed pixels with up to two palette entries.
End Rem
Const EmbeddedImageFormatIndexed1:Int = $101

Rem
bbdoc: Identifies two-bit indexed pixels with up to four palette entries.
End Rem
Const EmbeddedImageFormatIndexed2:Int = $102

Rem
bbdoc: Identifies four-bit indexed pixels with up to sixteen palette entries.
End Rem
Const EmbeddedImageFormatIndexed4:Int = $104

Rem
bbdoc: Identifies eight-bit indexed pixels with up to 256 palette entries.
End Rem
Const EmbeddedImageFormatIndexed8:Int = $108

Rem
bbdoc: Mirrors image pixels horizontally while drawing.
End Rem
Const EmbeddedImageDrawFlipX:Int = 1

Rem
bbdoc: Mirrors image pixels vertically while drawing.
End Rem
Const EmbeddedImageDrawFlipY:Int = 2

Rem
bbdoc: Disables source color-key transparency.
End Rem
Const EmbeddedImageColorKeyDisabled:UInt = $ffffffff:UInt

Private

Function ImageU16:Int(data:Byte Ptr, offset:Int)
	Return (Int(data[offset]) & $ff) | ((Int(data[offset + 1]) & $ff) Shl 8)
End Function

Function ImageU32:UInt(data:Byte Ptr, offset:Int)
	Return UInt(Int(data[offset]) & $ff) | ..
		(UInt(Int(data[offset + 1]) & $ff) Shl 8) | ..
		(UInt(Int(data[offset + 2]) & $ff) Shl 16) | ..
		(UInt(Int(data[offset + 3]) & $ff) Shl 24)
End Function

Function TintComponent:UInt(value:UInt, tint:UInt)
	Return (value * tint + 127) / 255
End Function

Function BlendComponent:UInt(source:UInt, destination:UInt, opacity:UInt)
	Return (source * opacity + destination * (255 - opacity) + 127) / 255
End Function

Function IndexedFormatBits:Int(format:Int)
	Select format
		Case EmbeddedImageFormatIndexed1
			Return 1
		Case EmbeddedImageFormatIndexed2
			Return 2
		Case EmbeddedImageFormatIndexed4
			Return 4
		Case EmbeddedImageFormatIndexed8
			Return 8
	End Select
	Return 0
End Function

Public

Rem
bbdoc: A validated read-only EBI1 image stored in persistent memory.
End Rem
Type TEmbeddedImage Final
	Private
	Field data:Byte Ptr
	Field dataLength:Int
	Field imageWidth:Int
	Field imageHeight:Int
	Field imageFormat:Int
	Field pixelStride:Int
	Field pixelOffset:Int
	Field maskStride:Int
	Field maskOffset:Int
	Field imageFlags:Int
	Field paletteEntries:Int
	Field imageEncoding:Int
	Field rleDataOffset:Int

	Public
	Rem
	bbdoc: Opens an EBI1 image held in persistent memory.
	param: A pointer to the first byte of EBI1 image data.
	param: The available data length in bytes.
	returns: Null when the header, dimensions, format, offsets, or lengths are invalid.
	End Rem
	Function Create:TEmbeddedImage(data:Byte Ptr, length:Int)
		If data = Null Or length < 32 Then Return Null
		If (Int(data[0]) & $ff) <> Asc("E") Or (Int(data[1]) & $ff) <> Asc("B") Or ..
				(Int(data[2]) & $ff) <> Asc("I") Or (Int(data[3]) & $ff) <> Asc("1") Then Return Null
		If ImageU16(data, 4) <> EmbeddedImageVersion Then Return Null
		Local flags:Int = ImageU16(data, 6)
		If flags & ~EmbeddedImageFlagMask Then Return Null
		Local width:Int = ImageU16(data, 8)
		Local height:Int = ImageU16(data, 10)
		Local format:Int = ImageU16(data, 12)
		Local encoding:Int = ImageU16(data, 14)
		Local stride:Int = Int(ImageU32(data, 16))
		Local pixels:Int = Int(ImageU32(data, 20))
		Local alphaStride:Int = Int(ImageU32(data, 24))
		Local alpha:Int = Int(ImageU32(data, 28))
		Local indexedBits:Int = IndexedFormatBits(format)
		Local minimumStride:Int
		Local paletteEntries:Int
		If indexedBits Then
			minimumStride = (width * indexedBits + 7) / 8
			If pixels < 35 Or ((pixels - 32) Mod 3) <> 0 Then Return Null
			paletteEntries = (pixels - 32) / 3
			If paletteEntries <= 0 Or paletteEntries > (1 Shl indexedBits) Then Return Null
		Else
			minimumStride = DisplayMinimumStride(width, format)
			If pixels < 32 Then Return Null
		End If
		If width <= 0 Or height <= 0 Or minimumStride <= 0 Then Return Null
		If encoding <> EmbeddedImageEncodingRaw And encoding <> EmbeddedImageEncodingRLE Then Return Null
		If encoding = EmbeddedImageEncodingRLE And Not indexedBits Then Return Null
		Local pixelEnd:Long
		Local rleDataOffset:Int
		Local rleLength:Int
		If encoding = EmbeddedImageEncodingRaw Then
			If stride < minimumStride Then Return Null
			pixelEnd = Long(pixels) + Long(stride) * Long(height)
			If pixelEnd > length Then Return Null
		Else
			If stride <> 0 Then Return Null
			Local tableBytes:Long = Long(height + 1) * 4
			If Long(pixels) + tableBytes > length Then Return Null
			rleDataOffset = pixels + Int(tableBytes)
			If ImageU32(data, pixels) <> 0 Then Return Null
			Local finalOffset:Int = Int(ImageU32(data, pixels + height * 4))
			If finalOffset < 0 Or Long(rleDataOffset) + finalOffset > length Then Return Null
			rleLength = finalOffset
			pixelEnd = Long(rleDataOffset) + finalOffset
		End If
		If indexedBits And encoding = EmbeddedImageEncodingRaw Then
			For Local y:Int = 0 Until height
				For Local x:Int = 0 Until width
					Local packed:Int = Int(data[pixels + y * stride + ((x * indexedBits) Shr 3)]) & $ff
					Local shift:Int = 8 - indexedBits - ((x * indexedBits) & 7)
					Local index:Int = (packed Shr shift) & ((1 Shl indexedBits) - 1)
					If index >= paletteEntries Then Return Null
				Next
			Next
		Else If indexedBits Then
			Local previousEnd:Int
			For Local y:Int = 0 Until height
				Local rowStart:Int = Int(ImageU32(data, pixels + y * 4))
				Local rowEnd:Int = Int(ImageU32(data, pixels + (y + 1) * 4))
				If rowStart <> previousEnd Or rowEnd < rowStart Or rowEnd > rleLength Or ..
						(rowEnd - rowStart) Mod 2 Then Return Null
				Local decodedWidth:Int
				For Local runOffset:Int = rowStart Until rowEnd Step 2
					decodedWidth :+ (Int(data[rleDataOffset + runOffset]) & $ff) + 1
					If (Int(data[rleDataOffset + runOffset + 1]) & $ff) >= paletteEntries Or ..
							decodedWidth > width Then Return Null
				Next
				If decodedWidth <> width Then Return Null
				previousEnd = rowEnd
			Next
		End If
		If flags & EmbeddedImageFlagMask Then
			Local minimumMaskStride:Int = (width + 7) / 8
			If alphaStride < minimumMaskStride Or Long(alpha) < pixelEnd Then Return Null
			Local maskEnd:Long = Long(alpha) + Long(alphaStride) * Long(height)
			If maskEnd > length Then Return Null
		Else If alphaStride <> 0 Or alpha <> 0 Then
			Return Null
		End If
		Local image:TEmbeddedImage = New TEmbeddedImage
		image.data = data
		image.dataLength = length
		image.imageWidth = width
		image.imageHeight = height
		image.imageFormat = format
		image.pixelStride = stride
		image.pixelOffset = pixels
		image.maskStride = alphaStride
		image.maskOffset = alpha
		image.imageFlags = flags
		image.paletteEntries = paletteEntries
		image.imageEncoding = encoding
		image.rleDataOffset = rleDataOffset
		Return image
	End Function

	Rem
	bbdoc: Returns the image width in pixels.
	returns: The native width.
	End Rem
	Method Width:Int()
		Return imageWidth
	End Method

	Rem
	bbdoc: Returns the image height in pixels.
	returns: The native height.
	End Rem
	Method Height:Int()
		Return imageHeight
	End Method

	Rem
	bbdoc: Returns the stored pixel format.
	returns: A DisplayPixelFormat or EmbeddedImageFormatIndexed value.
	End Rem
	Method Format:Int()
		Return imageFormat
	End Method

	Rem
	bbdoc: Reports whether the image contains a one-bit transparency mask.
	returns: True when masked pixels are present.
	End Rem
	Method HasMask:Int()
		Return (imageFlags & EmbeddedImageFlagMask) <> 0
	End Method

	Rem
	bbdoc: Reports whether pixels refer to a stored RGB palette.
	returns: True for an indexed image.
	End Rem
	Method IsIndexed:Int()
		Return paletteEntries > 0
	End Method

	Rem
	bbdoc: Returns the number of RGB colors in an indexed image's palette.
	returns: The palette entry count, or zero for a direct-color image.
	End Rem
	Method PaletteSize:Int()
		Return paletteEntries
	End Method

	Rem
	bbdoc: Returns the image's pixel encoding.
	returns: EmbeddedImageEncodingRaw or EmbeddedImageEncodingRLE.
	End Rem
	Method Encoding:Int()
		Return imageEncoding
	End Method

	Rem
	bbdoc: Draws the complete image at its native size.
	param: The destination raster buffer.
	param: The destination left coordinate.
	param: The destination top coordinate.
	param: An $RRGGBB tint multiplied with each source pixel.
	param: A bitwise combination of EmbeddedImageDrawFlip values.
	param: Source opacity from 0 through 255.
	param: An $RRGGBB transparent source color, or EmbeddedImageColorKeyDisabled.
	End Rem
	Method Draw(target:TDisplayBuffer, x:Int, y:Int, tint:UInt = $ffffff, ..
			drawFlags:Int = 0, opacity:Int = 255, ..
			colorKey:UInt = EmbeddedImageColorKeyDisabled)
		If Not target Then Return
		DrawRegionClipped(target, x, y, 0, 0, imageWidth, imageHeight, tint, ..
			0, 0, target.Width(), target.Height(), drawFlags, opacity, colorKey)
	End Method

	Rem
	bbdoc: Draws an unscaled source region at the destination position.
	param: The destination raster buffer.
	param: The destination left coordinate.
	param: The destination top coordinate.
	param: The source-region left coordinate.
	param: The source-region top coordinate.
	param: The region width in pixels.
	param: The region height in pixels.
	param: An $RRGGBB tint multiplied with each source pixel.
	param: A bitwise combination of EmbeddedImageDrawFlip values.
	param: Source opacity from 0 through 255.
	param: An $RRGGBB transparent source color, or EmbeddedImageColorKeyDisabled.
	End Rem
	Method DrawRegion(target:TDisplayBuffer, x:Int, y:Int, sourceX:Int, sourceY:Int, ..
			width:Int, height:Int, tint:UInt = $ffffff, drawFlags:Int = 0, ..
			opacity:Int = 255, colorKey:UInt = EmbeddedImageColorKeyDisabled)
		If Not target Then Return
		DrawRegionClipped(target, x, y, sourceX, sourceY, width, height, tint, ..
			0, 0, target.Width(), target.Height(), drawFlags, opacity, colorKey)
	End Method

	Rem
	bbdoc: Draws the complete image scaled to a destination rectangle.
	param: The destination raster buffer.
	param: The destination left coordinate.
	param: The destination top coordinate.
	param: The destination width in pixels.
	param: The destination height in pixels.
	param: An $RRGGBB tint multiplied with each source pixel.
	param: A bitwise combination of EmbeddedImageDrawFlip values.
	param: Source opacity from 0 through 255.
	param: An $RRGGBB transparent source color, or EmbeddedImageColorKeyDisabled.
	about: Scaling uses deterministic nearest-neighbour sampling and allocates no memory.
	End Rem
	Method DrawRect(target:TDisplayBuffer, x:Int, y:Int, width:Int, height:Int, ..
			tint:UInt = $ffffff, drawFlags:Int = 0, opacity:Int = 255, ..
			colorKey:UInt = EmbeddedImageColorKeyDisabled)
		If Not target Then Return
		DrawRectClipped(target, x, y, width, height, tint, ..
			0, 0, target.Width(), target.Height(), drawFlags, opacity, colorKey)
	End Method

	Rem
	bbdoc: Draws a source region while restricting changed pixels to a target rectangle.
	param: The destination raster buffer.
	param: The destination left coordinate.
	param: The destination top coordinate.
	param: The source-region left coordinate.
	param: The source-region top coordinate.
	param: The region width in pixels.
	param: The region height in pixels.
	param: An $RRGGBB tint multiplied with each source pixel.
	param: The clipping rectangle's left edge.
	param: The clipping rectangle's top edge.
	param: The clipping rectangle's width.
	param: The clipping rectangle's height.
	param: A bitwise combination of EmbeddedImageDrawFlip values.
	param: Source opacity from 0 through 255.
	param: An $RRGGBB transparent source color, or EmbeddedImageColorKeyDisabled.
	End Rem
	Method DrawRegionClipped(target:TDisplayBuffer, x:Int, y:Int, sourceX:Int, sourceY:Int, ..
			width:Int, height:Int, tint:UInt, clipX:Int, clipY:Int, clipWidth:Int, clipHeight:Int, ..
			drawFlags:Int = 0, opacity:Int = 255, colorKey:UInt = EmbeddedImageColorKeyDisabled)
		If Not target Or width <= 0 Or height <= 0 Or clipWidth <= 0 Or clipHeight <= 0 Then Return
		If opacity <= 0 Then Return
		If opacity > 255 Then opacity = 255
		drawFlags :& EmbeddedImageDrawFlipX | EmbeddedImageDrawFlipY
		If sourceX < 0 Then
			Local delta:Int = -sourceX
			sourceX = 0
			x :+ delta
			width :- delta
		End If
		If sourceY < 0 Then
			Local delta:Int = -sourceY
			sourceY = 0
			y :+ delta
			height :- delta
		End If
		If sourceX + width > imageWidth Then width = imageWidth - sourceX
		If sourceY + height > imageHeight Then height = imageHeight - sourceY
		If width <= 0 Or height <= 0 Then Return

		Local clipX1:Int = clipX + clipWidth
		Local clipY1:Int = clipY + clipHeight
		If clipX < 0 Then clipX = 0
		If clipY < 0 Then clipY = 0
		If clipX1 > target.Width() Then clipX1 = target.Width()
		If clipY1 > target.Height() Then clipY1 = target.Height()
		Local x0:Int = x
		Local y0:Int = y
		Local x1:Int = x + width
		Local y1:Int = y + height
		If x0 < clipX Then x0 = clipX
		If y0 < clipY Then y0 = clipY
		If x1 > clipX1 Then x1 = clipX1
		If y1 > clipY1 Then y1 = clipY1
		If x0 >= x1 Or y0 >= y1 Then Return
		If imageEncoding = EmbeddedImageEncodingRLE Then
			For Local py:Int = y0 Until y1
				Local sourceRow:Int = py - y
				Local sy:Int = sourceY + sourceRow
				If drawFlags & EmbeddedImageDrawFlipY Then sy = sourceY + height - 1 - sourceRow
				DrawRLERow(target, py, x0, x1, sy, sourceX, width, x, width, ..
					(drawFlags & EmbeddedImageDrawFlipX) <> 0, tint, opacity, colorKey)
			Next
			Return
		End If

		Local targetPixels:Byte Ptr = target.Pixels()
		If targetPixels And target.Format() = DisplayPixelFormatRGB565 And ..
				imageFormat = DisplayPixelFormatRGB565 And HasMask() And ..
				colorKey = EmbeddedImageColorKeyDisabled Then
			_DisplayBlitMaskedRGB565(targetPixels, target.Stride(), target.Width(), target.Height(), ..
				data + pixelOffset + sourceY * pixelStride + sourceX * 2, pixelStride, width, ..
				height, data + maskOffset + sourceY * maskStride, maskStride, sourceX, ..
				x, y, x0, y0, x1 - x0, y1 - y0, tint, opacity, drawFlags)
			Return
		End If
		If targetPixels And target.Format() = DisplayPixelFormatRGB565 And Not HasMask() And ..
				colorKey = EmbeddedImageColorKeyDisabled And ..
				(imageFormat = DisplayPixelFormatRGB565 Or imageFormat = DisplayPixelFormatRGB888) Then
			Local sourceBytesPerPixel:Int = DisplayPixelFormatBits(imageFormat) / 8
			_DisplayBlitRGB565(targetPixels, target.Stride(), target.Width(), target.Height(), ..
				data + pixelOffset + sourceY * pixelStride + sourceX * sourceBytesPerPixel, pixelStride, ..
				width, height, imageFormat, x, y, width, height, x0, y0, x1 - x0, y1 - y0, ..
				tint, opacity, drawFlags)
			Return
		End If
		If targetPixels And tint = $ffffff And Not HasMask() And ..
				opacity = 255 And colorKey = EmbeddedImageColorKeyDisabled And imageFormat = target.Format() And ..
				imageFormat <> DisplayPixelFormatMono1 Then
			If drawFlags = 0 Then
				Local bytesPerPixel:Int = DisplayPixelFormatBits(imageFormat) / 8
				For Local py:Int = y0 Until y1
					Local sx:Int = sourceX + x0 - x
					Local sy:Int = sourceY + py - y
					MemCopy(targetPixels + py * target.Stride() + x0 * bytesPerPixel, ..
						data + pixelOffset + sy * pixelStride + sx * bytesPerPixel, ..
						Size_T((x1 - x0) * bytesPerPixel))
				Next
				Return
			End If
		End If

		For Local py:Int = y0 Until y1
			Local sourceRow:Int = py - y
			Local sy:Int = sourceY + sourceRow
			If drawFlags & EmbeddedImageDrawFlipY Then sy = sourceY + height - 1 - sourceRow
			For Local px:Int = x0 Until x1
				Local sourceColumn:Int = px - x
				Local sx:Int = sourceX + sourceColumn
				If drawFlags & EmbeddedImageDrawFlipX Then sx = sourceX + width - 1 - sourceColumn
				DrawPixel(target, px, py, sx, sy, tint, opacity, colorKey)
			Next
		Next
	End Method

	Rem
	bbdoc: Draws and scales the complete image while clipping changed pixels.
	param: The destination raster buffer.
	param: The destination left coordinate.
	param: The destination top coordinate.
	param: The destination width in pixels.
	param: The destination height in pixels.
	param: An $RRGGBB tint multiplied with each source pixel.
	param: The clipping rectangle's left edge.
	param: The clipping rectangle's top edge.
	param: The clipping rectangle's width.
	param: The clipping rectangle's height.
	param: A bitwise combination of EmbeddedImageDrawFlip values.
	param: Source opacity from 0 through 255.
	param: An $RRGGBB transparent source color, or EmbeddedImageColorKeyDisabled.
	End Rem
	Method DrawRectClipped(target:TDisplayBuffer, x:Int, y:Int, width:Int, height:Int, ..
			tint:UInt, clipX:Int, clipY:Int, clipWidth:Int, clipHeight:Int, ..
			drawFlags:Int = 0, opacity:Int = 255, colorKey:UInt = EmbeddedImageColorKeyDisabled)
		If Not target Or width <= 0 Or height <= 0 Or clipWidth <= 0 Or clipHeight <= 0 Then Return
		If opacity <= 0 Then Return
		If opacity > 255 Then opacity = 255
		drawFlags :& EmbeddedImageDrawFlipX | EmbeddedImageDrawFlipY
		Local destinationX:Int = x
		Local destinationY:Int = y
		Local destinationWidth:Int = width
		Local destinationHeight:Int = height
		Local x0:Int = x
		Local y0:Int = y
		Local x1:Int = x + width
		Local y1:Int = y + height
		Local clipX1:Int = clipX + clipWidth
		Local clipY1:Int = clipY + clipHeight
		If clipX < 0 Then clipX = 0
		If clipY < 0 Then clipY = 0
		If clipX1 > target.Width() Then clipX1 = target.Width()
		If clipY1 > target.Height() Then clipY1 = target.Height()
		If x0 < clipX Then x0 = clipX
		If y0 < clipY Then y0 = clipY
		If x1 > clipX1 Then x1 = clipX1
		If y1 > clipY1 Then y1 = clipY1
		If x0 >= x1 Or y0 >= y1 Then Return
		If imageEncoding = EmbeddedImageEncodingRLE Then
			For Local py:Int = y0 Until y1
				Local sy:Int = (py - destinationY) * imageHeight / destinationHeight
				If drawFlags & EmbeddedImageDrawFlipY Then sy = imageHeight - 1 - sy
				DrawRLERow(target, py, x0, x1, sy, 0, imageWidth, destinationX, ..
					destinationWidth, (drawFlags & EmbeddedImageDrawFlipX) <> 0, ..
					tint, opacity, colorKey)
			Next
			Return
		End If
		Local targetPixels:Byte Ptr = target.Pixels()
		If targetPixels And target.Format() = DisplayPixelFormatRGB565 And Not HasMask() And ..
				colorKey = EmbeddedImageColorKeyDisabled And ..
				(imageFormat = DisplayPixelFormatRGB565 Or imageFormat = DisplayPixelFormatRGB888) Then
			_DisplayBlitRGB565(targetPixels, target.Stride(), target.Width(), target.Height(), ..
				data + pixelOffset, pixelStride, imageWidth, imageHeight, imageFormat, ..
				destinationX, destinationY, destinationWidth, destinationHeight, ..
				x0, y0, x1 - x0, y1 - y0, tint, opacity, drawFlags)
			Return
		End If
		For Local py:Int = y0 Until y1
			Local sy:Int = (py - destinationY) * imageHeight / destinationHeight
			If drawFlags & EmbeddedImageDrawFlipY Then sy = imageHeight - 1 - sy
			For Local px:Int = x0 Until x1
				Local sx:Int = (px - destinationX) * imageWidth / destinationWidth
				If drawFlags & EmbeddedImageDrawFlipX Then sx = imageWidth - 1 - sx
				DrawPixel(target, px, py, sx, sy, tint, opacity, colorKey)
			Next
		Next
	End Method

	Private
	Method DrawRLERow(target:TDisplayBuffer, targetY:Int, x0:Int, x1:Int, sourceY:Int, ..
			sourceX:Int, sourceWidth:Int, destinationX:Int, destinationWidth:Int, ..
			flipX:Int, tint:UInt, opacity:Int, colorKey:UInt)
		Local rowStart:Int = Int(ImageU32(data, pixelOffset + sourceY * 4))
		Local rowEnd:Int = Int(ImageU32(data, pixelOffset + (sourceY + 1) * 4))
		Local firstSourceX:Int = sourceX + (x0 - destinationX) * sourceWidth / destinationWidth
		If flipX Then firstSourceX = sourceX + sourceWidth - 1 - ..
			((x0 - destinationX) * sourceWidth / destinationWidth)
		Local runOffset:Int = rowStart
		Local runStart:Int
		Local runEnd:Int
		While runOffset < rowEnd
			runEnd = runStart + (Int(data[rleDataOffset + runOffset]) & $ff) + 1
			If firstSourceX < runEnd Then Exit
			runStart = runEnd
			runOffset :+ 2
		Wend
		For Local px:Int = x0 Until x1
			Local sx:Int = sourceX + (px - destinationX) * sourceWidth / destinationWidth
			If flipX Then sx = sourceX + sourceWidth - 1 - ..
				((px - destinationX) * sourceWidth / destinationWidth)
			If flipX Then
				While sx < runStart
					runOffset :- 2
					runEnd = runStart
					runStart = runEnd - ((Int(data[rleDataOffset + runOffset]) & $ff) + 1)
				Wend
			Else
				While sx >= runEnd
					runStart = runEnd
					runOffset :+ 2
					runEnd = runStart + (Int(data[rleDataOffset + runOffset]) & $ff) + 1
				Wend
			End If
			If PixelVisible(sx, sourceY) Then
				Local index:Int = Int(data[rleDataOffset + runOffset + 1]) & $ff
				DrawColor(target, px, targetY, PalettePixel(index), tint, opacity, colorKey)
			End If
		Next
	End Method

	Method DrawPixel(target:TDisplayBuffer, x:Int, y:Int, sourceX:Int, sourceY:Int, ..
			tint:UInt, opacity:Int, colorKey:UInt)
		If Not PixelVisible(sourceX, sourceY) Then Return
		DrawColor(target, x, y, Pixel(sourceX, sourceY), tint, opacity, colorKey)
	End Method

	Method DrawColor(target:TDisplayBuffer, x:Int, y:Int, source:UInt, ..
			tint:UInt, opacity:Int, colorKey:UInt)
		If colorKey <> EmbeddedImageColorKeyDisabled And source = (colorKey & $ffffff) Then Return
		source = TintPixel(source, tint)
		If opacity >= 255 Then
			target.SetPixel(x, y, source)
			Return
		End If
		Local destination:UInt = target.Pixel(x, y)
		Local alpha:UInt = UInt(opacity)
		Local red:UInt = BlendComponent((source Shr 16) & $ff, (destination Shr 16) & $ff, alpha)
		Local green:UInt = BlendComponent((source Shr 8) & $ff, (destination Shr 8) & $ff, alpha)
		Local blue:UInt = BlendComponent(source & $ff, destination & $ff, alpha)
		target.SetPixel(x, y, (red Shl 16) | (green Shl 8) | blue)
	End Method

	Method PixelVisible:Int(x:Int, y:Int)
		If Not HasMask() Then Return True
		Local packed:Int = Int(data[maskOffset + y * maskStride + (x Shr 3)]) & $ff
		Return (packed & ($80 Shr (x & 7))) <> 0
	End Method

	Method TintPixel:UInt(color:UInt, tint:UInt)
		If tint = $ffffff Then Return color
		Local red:UInt = TintComponent((color Shr 16) & $ff, (tint Shr 16) & $ff)
		Local green:UInt = TintComponent((color Shr 8) & $ff, (tint Shr 8) & $ff)
		Local blue:UInt = TintComponent(color & $ff, tint & $ff)
		Return (red Shl 16) | (green Shl 8) | blue
	End Method

	Method PalettePixel:UInt(index:Int)
		Local offset:Int = 32 + index * 3
		Return (UInt(Int(data[offset]) & $ff) Shl 16) | ..
			(UInt(Int(data[offset + 1]) & $ff) Shl 8) | UInt(Int(data[offset + 2]) & $ff)
	End Method

	Method Pixel:UInt(x:Int, y:Int)
		Local offset:Int
		Local indexedBits:Int = IndexedFormatBits(imageFormat)
		If indexedBits Then
			Local index:Int
			If imageEncoding = EmbeddedImageEncodingRLE Then
				Local runOffset:Int = Int(ImageU32(data, pixelOffset + y * 4))
				Local rowEnd:Int = Int(ImageU32(data, pixelOffset + (y + 1) * 4))
				Local decodedX:Int
				While runOffset < rowEnd
					decodedX :+ (Int(data[rleDataOffset + runOffset]) & $ff) + 1
					If x < decodedX Then
						index = Int(data[rleDataOffset + runOffset + 1]) & $ff
						Exit
					End If
					runOffset :+ 2
				Wend
			Else
				Local packed:Int = Int(data[pixelOffset + y * pixelStride + ((x * indexedBits) Shr 3)]) & $ff
				Local shift:Int = 8 - indexedBits - ((x * indexedBits) & 7)
				index = (packed Shr shift) & ((1 Shl indexedBits) - 1)
			End If
			Return PalettePixel(index)
		End If
		Select imageFormat
			Case DisplayPixelFormatMono1
				offset = pixelOffset + y * pixelStride + (x Shr 3)
				If (Int(data[offset]) & $ff) & ($80 Shr (x & 7)) Then Return $ffffff
			Case DisplayPixelFormatRGB565
			offset = pixelOffset + y * pixelStride + x * 2
			Local rgb565:UInt = UInt(Int(data[offset]) & $ff) | ..
				(UInt(Int(data[offset + 1]) & $ff) Shl 8)
			Local red:UInt = (rgb565 Shr 11) & $1f
			Local green:UInt = (rgb565 Shr 5) & $3f
			Local blue:UInt = rgb565 & $1f
			Return (((red Shl 3) | (red Shr 2)) Shl 16) | ..
				(((green Shl 2) | (green Shr 4)) Shl 8) | ((blue Shl 3) | (blue Shr 2))
			Case DisplayPixelFormatRGB888
			offset = pixelOffset + y * pixelStride + x * 3
			Return (UInt(Int(data[offset]) & $ff) Shl 16) | ..
				(UInt(Int(data[offset + 1]) & $ff) Shl 8) | UInt(Int(data[offset + 2]) & $ff)
		End Select
		Return 0
	End Method
End Type
?
