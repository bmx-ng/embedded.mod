' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Compact firmware-resident images and allocation-free raster drawing.
about: EBI1 images contain raw Mono1, RGB565, or RGB888 pixels and an optional
one-bit transparency mask. Images are validated once when opened and can then
be clipped, tinted, converted, or nearest-neighbour scaled while drawing.
End Rem
Module Embedded.Drivers.Display.Image
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Drivers.Display
Import "native/embedded_display_image_raster.c"

Extern "C"
	Function _DisplayBlitRGB565:Int(targetPixels:Byte Ptr, targetStride:Int, ..
		targetWidth:Int, targetHeight:Int, sourcePixels:Byte Ptr, sourceStride:Int, ..
		sourceWidth:Int, sourceHeight:Int, destinationX:Int, destinationY:Int, ..
		destinationWidth:Int, destinationHeight:Int, clipX:Int, clipY:Int, ..
		clipWidth:Int, clipHeight:Int, drawFlags:Int) = ..
		"bmx_embedded_display_blit_rgb565"
End Extern

Const EmbeddedImageVersion:Int = 1
Const EmbeddedImageEncodingRaw:Int = 0
Const EmbeddedImageFlagMask:Int = 1
Const EmbeddedImageDrawFlipX:Int = 1
Const EmbeddedImageDrawFlipY:Int = 2
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

	Public
	Rem
	bbdoc: Opens an EBI1 image held in persistent memory.
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
		Local minimumStride:Int = DisplayMinimumStride(width, format)
		If width <= 0 Or height <= 0 Or minimumStride <= 0 Or ..
				encoding <> EmbeddedImageEncodingRaw Or stride < minimumStride Or pixels < 32 Then Return Null
		Local pixelEnd:Long = Long(pixels) + Long(stride) * Long(height)
		If pixelEnd > length Then Return Null
		If flags & EmbeddedImageFlagMask Then
			Local minimumMaskStride:Int = (width + 7) / 8
			If alphaStride < minimumMaskStride Or alpha < 32 Then Return Null
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
		Return image
	End Function

	Method Width:Int()
		Return imageWidth
	End Method

	Method Height:Int()
		Return imageHeight
	End Method

	Method Format:Int()
		Return imageFormat
	End Method

	Method HasMask:Int()
		Return (imageFlags & EmbeddedImageFlagMask) <> 0
	End Method

	Rem
	bbdoc: Draws the complete image at its native size.
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

		Local targetPixels:Byte Ptr = target.Pixels()
		If targetPixels And tint = $ffffff And Not HasMask() And ..
				opacity = 255 And colorKey = EmbeddedImageColorKeyDisabled And imageFormat = target.Format() And ..
				imageFormat <> DisplayPixelFormatMono1 Then
			If imageFormat = DisplayPixelFormatRGB565 Then
				_DisplayBlitRGB565(targetPixels, target.Stride(), target.Width(), target.Height(), ..
					data + pixelOffset + sourceY * pixelStride + sourceX * 2, pixelStride, ..
					width, height, x, y, width, height, x0, y0, x1 - x0, y1 - y0, drawFlags)
				Return
			End If
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
		Local targetPixels:Byte Ptr = target.Pixels()
		If targetPixels And imageFormat = DisplayPixelFormatRGB565 And ..
				target.Format() = DisplayPixelFormatRGB565 And tint = $ffffff And ..
				Not HasMask() And opacity = 255 And colorKey = EmbeddedImageColorKeyDisabled Then
			_DisplayBlitRGB565(targetPixels, target.Stride(), target.Width(), target.Height(), ..
				data + pixelOffset, pixelStride, imageWidth, imageHeight, ..
				destinationX, destinationY, destinationWidth, destinationHeight, ..
				x0, y0, x1 - x0, y1 - y0, drawFlags)
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
	Method DrawPixel(target:TDisplayBuffer, x:Int, y:Int, sourceX:Int, sourceY:Int, ..
			tint:UInt, opacity:Int, colorKey:UInt)
		If Not PixelVisible(sourceX, sourceY) Then Return
		Local source:UInt = Pixel(sourceX, sourceY)
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

	Method Pixel:UInt(x:Int, y:Int)
		Local offset:Int
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
