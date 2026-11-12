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

Const EmbeddedImageVersion:Int = 1
Const EmbeddedImageEncodingRaw:Int = 0
Const EmbeddedImageFlagMask:Int = 1

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
	Method Draw(target:TDisplayBuffer, x:Int, y:Int, tint:UInt = $ffffff)
		If Not target Then Return
		DrawRegionClipped(target, x, y, 0, 0, imageWidth, imageHeight, tint, ..
			0, 0, target.Width(), target.Height())
	End Method

	Rem
	bbdoc: Draws an unscaled source region at the destination position.
	End Rem
	Method DrawRegion(target:TDisplayBuffer, x:Int, y:Int, sourceX:Int, sourceY:Int, ..
			width:Int, height:Int, tint:UInt = $ffffff)
		If Not target Then Return
		DrawRegionClipped(target, x, y, sourceX, sourceY, width, height, tint, ..
			0, 0, target.Width(), target.Height())
	End Method

	Rem
	bbdoc: Draws the complete image scaled to a destination rectangle.
	about: Scaling uses deterministic nearest-neighbour sampling and allocates no memory.
	End Rem
	Method DrawRect(target:TDisplayBuffer, x:Int, y:Int, width:Int, height:Int, ..
			tint:UInt = $ffffff)
		If Not target Then Return
		DrawRectClipped(target, x, y, width, height, tint, ..
			0, 0, target.Width(), target.Height())
	End Method

	Rem
	bbdoc: Draws a source region while restricting changed pixels to a target rectangle.
	End Rem
	Method DrawRegionClipped(target:TDisplayBuffer, x:Int, y:Int, sourceX:Int, sourceY:Int, ..
			width:Int, height:Int, tint:UInt, clipX:Int, clipY:Int, clipWidth:Int, clipHeight:Int)
		If Not target Or width <= 0 Or height <= 0 Or clipWidth <= 0 Or clipHeight <= 0 Then Return
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
		If x < clipX Then
			Local delta:Int = clipX - x
			x = clipX
			sourceX :+ delta
			width :- delta
		End If
		If y < clipY Then
			Local delta:Int = clipY - y
			y = clipY
			sourceY :+ delta
			height :- delta
		End If
		If x + width > clipX1 Then width = clipX1 - x
		If y + height > clipY1 Then height = clipY1 - y
		If width <= 0 Or height <= 0 Then Return

		Local targetPixels:Byte Ptr = target.Pixels()
		If targetPixels And tint = $ffffff And Not HasMask() And imageFormat = target.Format() And ..
				imageFormat <> DisplayPixelFormatMono1 Then
			Local bytesPerPixel:Int = DisplayPixelFormatBits(imageFormat) / 8
			For Local row:Int = 0 Until height
				MemCopy(targetPixels + (y + row) * target.Stride() + x * bytesPerPixel, ..
					data + pixelOffset + (sourceY + row) * pixelStride + sourceX * bytesPerPixel, ..
					Size_T(width * bytesPerPixel))
			Next
			Return
		End If

		For Local row:Int = 0 Until height
			For Local column:Int = 0 Until width
				Local sx:Int = sourceX + column
				Local sy:Int = sourceY + row
				If PixelVisible(sx, sy) Then ..
					target.SetPixel(x + column, y + row, TintedPixel(sx, sy, tint))
			Next
		Next
	End Method

	Rem
	bbdoc: Draws and scales the complete image while clipping changed pixels.
	End Rem
	Method DrawRectClipped(target:TDisplayBuffer, x:Int, y:Int, width:Int, height:Int, ..
			tint:UInt, clipX:Int, clipY:Int, clipWidth:Int, clipHeight:Int)
		If Not target Or width <= 0 Or height <= 0 Or clipWidth <= 0 Or clipHeight <= 0 Then Return
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
		For Local py:Int = y0 Until y1
			Local sy:Int = (py - destinationY) * imageHeight / destinationHeight
			For Local px:Int = x0 Until x1
				Local sx:Int = (px - destinationX) * imageWidth / destinationWidth
				If PixelVisible(sx, sy) Then target.SetPixel(px, py, TintedPixel(sx, sy, tint))
			Next
		Next
	End Method

	Private
	Method PixelVisible:Int(x:Int, y:Int)
		If Not HasMask() Then Return True
		Local packed:Int = Int(data[maskOffset + y * maskStride + (x Shr 3)]) & $ff
		Return (packed & ($80 Shr (x & 7))) <> 0
	End Method

	Method TintedPixel:UInt(x:Int, y:Int, tint:UInt)
		Local color:UInt = Pixel(x, y)
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
