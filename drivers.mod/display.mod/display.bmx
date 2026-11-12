' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable pixel buffers and display presentation contracts.
about: Display drivers accept caller-owned raster buffers and synchronously copy
the requested region before returning. This keeps rendering independent from
the display controller and provides a small adapter boundary for graphics
engines such as LVGL.
End Rem
Module Embedded.Drivers.Display
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Rem
bbdoc: One bit per pixel, rows stored top-to-bottom and most-significant bit first.
End Rem
Const DisplayPixelFormatMono1:Int = 1

Rem
bbdoc: 16-bit RGB565 pixels stored least-significant byte first.
End Rem
Const DisplayPixelFormatRGB565:Int = 2

Rem
bbdoc: 24-bit pixels stored as red, green, then blue bytes.
End Rem
Const DisplayPixelFormatRGB888:Int = 3

Const DisplayErrorGeneric:Int = -1
Const DisplayErrorUnsupportedFormat:Int = -2
Const DisplayErrorInvalidArgument:Int = -5

Rem
bbdoc: Returns the number of bits used by one pixel, or zero for an unknown format.
End Rem
Function DisplayPixelFormatBits:Int(format:Int)
	Select format
		Case DisplayPixelFormatMono1
			Return 1
		Case DisplayPixelFormatRGB565
			Return 16
		Case DisplayPixelFormatRGB888
			Return 24
	End Select

	Return 0
End Function

Rem
bbdoc: Returns the minimum byte stride for a raster row.
End Rem
Function DisplayMinimumStride:Int(width:Int, format:Int)
	If width <= 0 Then
		Return 0
	End If

	Select format
		Case DisplayPixelFormatMono1
			Return (width + 7) / 8
		Case DisplayPixelFormatRGB565
			Return width * 2
		Case DisplayPixelFormatRGB888
			Return width * 3
	End Select

	Return 0
End Function

Rem
bbdoc: A compact, caller-owned raster buffer.
about: Mono buffers use horizontal, MSB-first rows. RGB colors supplied to
Clear, SetPixel, and drawing methods use $RRGGBB; Mono treats zero as off and
any non-zero value as on.
End Rem
Type TDisplayBuffer
	Private
	Field bufferWidth:Int
	Field bufferHeight:Int
	Field bufferStride:Int
	Field bufferFormat:Int
	Field storage:Byte[]
	Field externalStorage:Byte Ptr
	Field bufferSize:Int

	Public
	Function Create:TDisplayBuffer(width:Int, height:Int, format:Int)
		Local stride:Int = DisplayMinimumStride(width, format)
		If stride <= 0 Or height <= 0 Then
			Return Null
		End If

		Local result:TDisplayBuffer = New TDisplayBuffer
		result.bufferWidth = width
		result.bufferHeight = height
		result.bufferStride = stride
		result.bufferFormat = format
		result.bufferSize = stride * height
		result.storage = New Byte[result.bufferSize]
		Return result
	End Function

	Rem
	bbdoc: Wraps a caller-owned raster without allocating its pixel storage.
	about: The memory must remain valid for the lifetime of the buffer. Bytes returns
	Null for an external raster; use Pixels and Size for storage-independent access.
	End Rem
	Function CreateExternal:TDisplayBuffer(width:Int, height:Int, format:Int, pixels:Byte Ptr, stride:Int = 0)
		Local minimumStride:Int = DisplayMinimumStride(width, format)
		If minimumStride <= 0 Or height <= 0 Or pixels = Null Then Return Null
		If stride = 0 Then stride = minimumStride
		If stride < minimumStride Then Return Null
		Local size:Long = Long(stride) * Long(height)
		If size <= 0 Or size > $7fffffff Then Return Null

		Local result:TDisplayBuffer = New TDisplayBuffer
		result.bufferWidth = width
		result.bufferHeight = height
		result.bufferStride = stride
		result.bufferFormat = format
		result.externalStorage = pixels
		result.bufferSize = Int(size)
		Return result
	End Function

	Method Width:Int()
		Return bufferWidth
	End Method

	Method Height:Int()
		Return bufferHeight
	End Method

	Method Stride:Int()
		Return bufferStride
	End Method

	Method Format:Int()
		Return bufferFormat
	End Method

	Method Size:Int()
		Return bufferSize
	End Method

	Method Bytes:Byte[]()
		Return storage
	End Method

	Method Pixels:Byte Ptr()
		If externalStorage Then Return externalStorage
		If storage.length = 0 Then
			Return Null
		End If

		Return Varptr storage[0]
	End Method

	Method Clear(color:UInt = 0)
		Local pixels:Byte Ptr = Pixels()
		If Not pixels Then Return
		If bufferFormat = DisplayPixelFormatMono1 Then
			Local value:Byte
			If color Then
				value = $ff
			End If

			For Local index:Int = 0 Until bufferSize
				pixels[index] = value
			Next

			Return
		End If

		FillRect(0, 0, bufferWidth, bufferHeight, color)
	End Method

	Method SetPixel(x:Int, y:Int, color:UInt = $ffffff)
		If x < 0 Or y < 0 Or x >= bufferWidth Or y >= bufferHeight Then
			Return
		End If

		Local pixels:Byte Ptr = Pixels()
		If Not pixels Then Return
		Local offset:Int
		Select bufferFormat
			Case DisplayPixelFormatMono1
				offset = y * bufferStride + (x Shr 3)
				Local mask:Byte = Byte($80 Shr (x & 7))
				If color Then
					pixels[offset] :| mask
				Else
					pixels[offset] :& ~mask
				End If
			Case DisplayPixelFormatRGB565
				offset = y * bufferStride + x * 2
				Local red:UInt = (color Shr 19) & $1f
				Local green:UInt = (color Shr 10) & $3f
				Local blue:UInt = (color Shr 3) & $1f
				Local rgb565:UInt = (red Shl 11) | (green Shl 5) | blue
				pixels[offset] = Byte(rgb565)
				pixels[offset + 1] = Byte(rgb565 Shr 8)
			Case DisplayPixelFormatRGB888
				offset = y * bufferStride + x * 3
				pixels[offset] = Byte(color Shr 16)
				pixels[offset + 1] = Byte(color Shr 8)
				pixels[offset + 2] = Byte(color)
		End Select
	End Method

	Method Pixel:UInt(x:Int, y:Int)
		If x < 0 Or y < 0 Or x >= bufferWidth Or y >= bufferHeight Then
			Return 0
		End If

		Local pixels:Byte Ptr = Pixels()
		If Not pixels Then Return 0
		Local offset:Int
		Select bufferFormat
			Case DisplayPixelFormatMono1
				offset = y * bufferStride + (x Shr 3)
				Return (pixels[offset] & ($80 Shr (x & 7))) <> 0
			Case DisplayPixelFormatRGB565
				offset = y * bufferStride + x * 2
				Local rgb565:UInt = UInt(pixels[offset]) | (UInt(pixels[offset + 1]) Shl 8)
				Local red:UInt = (rgb565 Shr 11) & $1f
				Local green:UInt = (rgb565 Shr 5) & $3f
				Local blue:UInt = rgb565 & $1f
				Return ((red Shl 3) | (red Shr 2)) Shl 16 | ..
				((green Shl 2) | (green Shr 4)) Shl 8 | ..
				((blue Shl 3) | (blue Shr 2))
			Case DisplayPixelFormatRGB888
				offset = y * bufferStride + x * 3
				Return (UInt(pixels[offset]) Shl 16) | ..
					(UInt(pixels[offset + 1]) Shl 8) | UInt(pixels[offset + 2])
		End Select

		Return 0
	End Method

	Method FillRect(x:Int, y:Int, width:Int, height:Int, color:UInt = $ffffff)
		If width <= 0 Or height <= 0 Then
			Return
		End If

		Local x0:Int = x
		Local y0:Int = y
		Local x1:Int = x + width
		Local y1:Int = y + height
		If x0 < 0 Then
			x0 = 0
		End If

		If y0 < 0 Then
			y0 = 0
		End If

		If x1 > bufferWidth Then
			x1 = bufferWidth
		End If

		If y1 > bufferHeight Then
			y1 = bufferHeight
		End If
		If x0 >= x1 Or y0 >= y1 Then Return

		Local pixels:Byte Ptr = Pixels()
		If Not pixels Then Return
		Select bufferFormat
			Case DisplayPixelFormatRGB565
				Local red:UInt = (color Shr 19) & $1f
				Local green:UInt = (color Shr 10) & $3f
				Local blue:UInt = (color Shr 3) & $1f
				Local rgb565:UInt = (red Shl 11) | (green Shl 5) | blue
				For Local py:Int = y0 Until y1
					Local offset:Int = py * bufferStride + x0 * 2
					For Local px:Int = x0 Until x1
						pixels[offset] = Byte(rgb565)
						pixels[offset + 1] = Byte(rgb565 Shr 8)
						offset :+ 2
					Next
				Next
				Return
			Case DisplayPixelFormatRGB888
				Local red:Byte = Byte(color Shr 16)
				Local green:Byte = Byte(color Shr 8)
				Local blue:Byte = Byte(color)
				For Local py:Int = y0 Until y1
					Local offset:Int = py * bufferStride + x0 * 3
					For Local px:Int = x0 Until x1
						pixels[offset] = red
						pixels[offset + 1] = green
						pixels[offset + 2] = blue
						offset :+ 3
					Next
				Next
				Return
		End Select

		For Local py:Int = y0 Until y1
			For Local px:Int = x0 Until x1
				SetPixel(px, py, color)
			Next
		Next
	End Method

	Method DrawRect(x:Int, y:Int, width:Int, height:Int, color:UInt = $ffffff)
		If width <= 0 Or height <= 0 Then
			Return
		End If

		DrawLine(x, y, x + width - 1, y, color)
		DrawLine(x, y + height - 1, x + width - 1, y + height - 1, color)
		DrawLine(x, y, x, y + height - 1, color)
		DrawLine(x + width - 1, y, x + width - 1, y + height - 1, color)
	End Method

	Method DrawLine(x0:Int, y0:Int, x1:Int, y1:Int, color:UInt = $ffffff)
		Local dx:Int = x1 - x0
		If dx < 0 Then
			dx = -dx
		End If

		Local sx:Int = -1
		If x0 < x1 Then
			sx = 1
		End If

		Local dy:Int = y1 - y0
		If dy < 0 Then
			dy = -dy
		End If

		dy = -dy
		Local sy:Int = -1
		If y0 < y1 Then
			sy = 1
		End If

		Local error:Int = dx + dy
		While True
			SetPixel(x0, y0, color)
			If x0 = x1 And y0 = y1 Then
				Exit
			End If

			Local twiceError:Int = error Shl 1
			If twiceError >= dy Then
				error :+ dy
				x0 :+ sx
			End If

			If twiceError <= dx Then
				error :+ dx
				y0 :+ sy
			End If
		Wend
	End Method
End Type

Rem
bbdoc: Base class for synchronous display presentation drivers.
about: PresentPixels takes a pointer to the complete raster origin. The dirty
rectangle selects the part which needs sending; implementations may expand it
to controller page or transfer boundaries. The caller retains the memory and
must keep it valid until the method returns.
End Rem
Type TDisplay Abstract
	Method Width:Int() Abstract

	Method Height:Int() Abstract

	Method PreferredPixelFormat:Int() Abstract

	Method PresentPixels:Int(pixels:Byte Ptr, stride:Int, format:Int, ..
	x:Int, y:Int, width:Int, height:Int) Abstract

	Method SetEnabled:Int(enabled:Int) Abstract

	Method CreateBuffer:TDisplayBuffer()
		Return TDisplayBuffer.Create(Width(), Height(), PreferredPixelFormat())
	End Method

	Method Present:Int(buffer:TDisplayBuffer)
		If Not buffer Then
			Return DisplayErrorInvalidArgument
		End If

		Return PresentRegion(buffer, 0, 0, Width(), Height())
	End Method

	Method PresentRegion:Int(buffer:TDisplayBuffer, x:Int, y:Int, width:Int, height:Int)
		If Not buffer Or buffer.Width() < Width() Or buffer.Height() < Height() Then ..
			Return DisplayErrorInvalidArgument

		Return PresentPixels(buffer.Pixels(), buffer.Stride(), buffer.Format(), ..
		x, y, width, height)
	End Method
End Type
?
