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

Import "native/embedded_display_raster.c"

Private

Extern "C"
	Function _DisplayFillMono1(pixels:Byte Ptr, stride:Int, bufferWidth:Int, ..
		bufferHeight:Int, x:Int, y:Int, width:Int, height:Int, color:UInt) = ..
		"bmx_embedded_display_fill_mono1"
	Function _DisplayFillRGB565(pixels:Byte Ptr, stride:Int, bufferWidth:Int, ..
		bufferHeight:Int, x:Int, y:Int, width:Int, height:Int, color:UInt) = ..
		"bmx_embedded_display_fill_rgb565"
	Function _DisplayDrawLine(pixels:Byte Ptr, stride:Int, bufferWidth:Int, ..
		bufferHeight:Int, format:Int, x0:Int, y0:Int, x1:Int, y1:Int, color:UInt) = ..
		"bmx_embedded_display_draw_line"
	Function _DisplayDrawMono1Mask(pixels:Byte Ptr, stride:Int, bufferWidth:Int, ..
		bufferHeight:Int, format:Int, mask:Byte Ptr, maskStride:Int, maskWidth:Int, ..
		maskHeight:Int, x:Int, y:Int, scale:Int, clipX:Int, clipY:Int, clipWidth:Int, ..
		clipHeight:Int, color:UInt) = "bmx_embedded_display_draw_mono1_mask"
	Function _DisplayDrawCircle(pixels:Byte Ptr, stride:Int, bufferWidth:Int, ..
		bufferHeight:Int, format:Int, centerX:Int, centerY:Int, radius:Int, clipX:Int, ..
		clipY:Int, clipWidth:Int, clipHeight:Int, color:UInt) = ..
		"bmx_embedded_display_draw_circle"
End Extern

Public

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

Rem
bbdoc: A generic display operation failure.
End Rem
Const DisplayErrorGeneric:Int = -1

Rem
bbdoc: The display does not accept the requested pixel format.
End Rem
Const DisplayErrorUnsupportedFormat:Int = -2

Rem
bbdoc: One or more display operation arguments are invalid.
End Rem
Const DisplayErrorInvalidArgument:Int = -5

Rem
bbdoc: The display accepts presentation rectangles smaller than the complete frame.
End Rem
Const DisplayCapabilityPartialPresent:Int = 1

Rem
bbdoc: Drawing storage is scanned directly by the display and may require synchronization.
End Rem
Const DisplayCapabilityLiveFramebuffer:Int = 2

Rem
bbdoc: The display exposes a vertical synchronization boundary.
End Rem
Const DisplayCapabilityVSync:Int = 4

Rem
bbdoc: Presentation exchanges a render buffer with a separately scanned buffer.
End Rem
Const DisplayCapabilityBufferSwap:Int = 8

Rem
bbdoc: The display can discard render-buffer contents after complete presentation.
End Rem
Const DisplayCapabilityDiscardPresent:Int = 16

Rem
bbdoc: Large solid fills may be handled by a target-specific hardware engine.
End Rem
Const DisplayCapabilityAcceleratedFill:Int = 32

Rem
bbdoc: Compatible image copies and scaling may use a target-specific hardware engine.
End Rem
Const DisplayCapabilityAcceleratedBlit:Int = 64

Rem
bbdoc: Uses the display's unrotated native orientation.
End Rem
Const DisplayOrientation0:Int = 0

Rem
bbdoc: Rotates the logical display orientation 90 degrees clockwise.
End Rem
Const DisplayOrientation90:Int = 90

Rem
bbdoc: Rotates the logical display orientation 180 degrees clockwise.
End Rem
Const DisplayOrientation180:Int = 180

Rem
bbdoc: Rotates the logical display orientation 270 degrees clockwise.
End Rem
Const DisplayOrientation270:Int = 270

Rem
bbdoc: Normalizes a supported clockwise display orientation, or returns -1.
param: An orientation in degrees; values outside one turn are wrapped.
returns: One of the DisplayOrientation constants, or -1 when the wrapped angle is not a quarter-turn.
End Rem
Function NormalizeDisplayOrientation:Int(degrees:Int)
	degrees :Mod 360
	If degrees < 0 Then degrees :+ 360
	If degrees = DisplayOrientation0 Or degrees = DisplayOrientation90 Or ..
			degrees = DisplayOrientation180 Or degrees = DisplayOrientation270 Then Return degrees
	Return -1
End Function

Rem
bbdoc: Returns the number of bits used by one pixel, or zero for an unknown format.
param: A DisplayPixelFormat value.
returns: The number of bits per pixel, or zero when the format is unknown.
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
param: The raster width in pixels.
param: A DisplayPixelFormat value.
returns: The minimum number of bytes per row, or zero for invalid dimensions or an unknown format.
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
	Rem
	bbdoc: Creates a managed raster buffer using the minimum stride for its format.
	param: The buffer width in pixels.
	param: The buffer height in pixels.
	param: A DisplayPixelFormat value.
	returns: A new zero-filled buffer, or Null when the dimensions or format are invalid.
	End Rem
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
	param: The buffer width in pixels.
	param: The buffer height in pixels.
	param: A DisplayPixelFormat value.
	param: A pointer to the first byte of caller-owned pixel storage.
	param: The number of bytes between rows, or zero to use the minimum stride.
	returns: A buffer view, or Null when the arguments are invalid.
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

	Rem
	bbdoc: Returns the physical raster width in pixels.
	returns: The buffer width.
	End Rem
	Method Width:Int()
		Return bufferWidth
	End Method

	Rem
	bbdoc: Returns the physical raster height in pixels.
	returns: The buffer height.
	End Rem
	Method Height:Int()
		Return bufferHeight
	End Method

	Rem
	bbdoc: Returns the distance in bytes between adjacent raster rows.
	returns: The row stride.
	End Rem
	Method Stride:Int()
		Return bufferStride
	End Method

	Rem
	bbdoc: Returns the raster pixel format.
	returns: A DisplayPixelFormat value.
	End Rem
	Method Format:Int()
		Return bufferFormat
	End Method

	Rem
	bbdoc: Returns the total size of the raster storage in bytes.
	returns: The byte size including any row padding.
	End Rem
	Method Size:Int()
		Return bufferSize
	End Method

	Rem
	bbdoc: Returns the managed byte array owned by this buffer.
	returns: The managed storage, or Null when the buffer wraps external memory.
	End Rem
	Method Bytes:Byte[]()
		Return storage
	End Method

	Rem
	bbdoc: Returns a pointer to the first byte of raster storage.
	returns: The pixel pointer, or Null when no storage is available.
	End Rem
	Method Pixels:Byte Ptr()
		If externalStorage Then Return externalStorage
		If storage.length = 0 Then
			Return Null
		End If

		Return Varptr storage[0]
	End Method

	Rem
	bbdoc: Retargets a buffer created by CreateExternal to equally sized storage.
	param: A pointer to replacement storage with the same size and layout.
	returns: True when the external buffer was retargeted successfully.
	about: This supports driver-owned buffer exchange while keeping the
	TDisplayBuffer identity stable for renderers. Managed buffers cannot be
	retargeted.
	End Rem
	Method RetargetExternal:Int(pixels:Byte Ptr)
		If storage.length Or Not externalStorage Or Not pixels Then Return False
		externalStorage = pixels
		Return True
	End Method

	Rem
	bbdoc: Fills the complete raster with one color.
	param: An $RRGGBB color; Mono1 treats zero as off and any non-zero value as on.
	End Rem
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

	Rem
	bbdoc: Writes one pixel, silently clipping coordinates outside the raster.
	param: The physical x coordinate.
	param: The physical y coordinate.
	param: An $RRGGBB color; Mono1 treats zero as off and any non-zero value as on.
	End Rem
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

	Rem
	bbdoc: Reads one pixel as an $RRGGBB color.
	param: The physical x coordinate.
	param: The physical y coordinate.
	returns: The expanded pixel color, or zero when the coordinates or storage are invalid.
	End Rem
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

	Rem
	bbdoc: Fills a clipped physical raster rectangle.
	param: The left coordinate.
	param: The top coordinate.
	param: The rectangle width in pixels.
	param: The rectangle height in pixels.
	param: An $RRGGBB color; Mono1 treats zero as off and any non-zero value as on.
	End Rem
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
			Case DisplayPixelFormatMono1
				_DisplayFillMono1(pixels, bufferStride, bufferWidth, bufferHeight, ..
					x0, y0, x1 - x0, y1 - y0, color)
				Return
			Case DisplayPixelFormatRGB565
				_DisplayFillRGB565(pixels, bufferStride, bufferWidth, bufferHeight, ..
					x0, y0, x1 - x0, y1 - y0, color)
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

	Rem
	bbdoc: Draws the one-pixel outline of a clipped physical raster rectangle.
	param: The left coordinate.
	param: The top coordinate.
	param: The rectangle width in pixels.
	param: The rectangle height in pixels.
	param: An $RRGGBB color; Mono1 treats zero as off and any non-zero value as on.
	End Rem
	Method DrawRect(x:Int, y:Int, width:Int, height:Int, color:UInt = $ffffff)
		If width <= 0 Or height <= 0 Then
			Return
		End If

		DrawLine(x, y, x + width - 1, y, color)
		DrawLine(x, y + height - 1, x + width - 1, y + height - 1, color)
		DrawLine(x, y, x, y + height - 1, color)
		DrawLine(x + width - 1, y, x + width - 1, y + height - 1, color)
	End Method

	Rem
	bbdoc: Draws the set pixels of a packed one-bit mask in a solid color.
	param: A pointer to top-to-bottom, most-significant-bit-first mask rows.
	param: The number of bytes between adjacent mask rows.
	param: The mask width in pixels.
	param: The mask height in pixels.
	param: The destination left coordinate.
	param: The destination top coordinate.
	param: A positive integer nearest-neighbour scale.
	param: The clipping rectangle's left coordinate.
	param: The clipping rectangle's top coordinate.
	param: The clipping rectangle's width.
	param: The clipping rectangle's height.
	param: An $RRGGBB color; Mono1 treats zero as off and any non-zero value as on.
	about: Clear mask bits leave the destination unchanged. This compact primitive
	is suitable for bitmap glyphs, monochrome icons, and other transparent masks.
	End Rem
	Method DrawMono1Mask(mask:Byte Ptr, maskStride:Int, maskWidth:Int, maskHeight:Int, ..
			x:Int, y:Int, scale:Int, clipX:Int, clipY:Int, clipWidth:Int, clipHeight:Int, ..
			color:UInt = $ffffff)
		If Not mask Or maskStride < (maskWidth + 7) / 8 Or maskWidth <= 0 Or ..
				maskHeight <= 0 Or scale <= 0 Or clipWidth <= 0 Or clipHeight <= 0 Then Return
		Local clipX1:Int = clipX + clipWidth
		Local clipY1:Int = clipY + clipHeight
		If clipX < 0 Then clipX = 0
		If clipY < 0 Then clipY = 0
		If clipX1 > bufferWidth Then clipX1 = bufferWidth
		If clipY1 > bufferHeight Then clipY1 = bufferHeight
		If clipX >= clipX1 Or clipY >= clipY1 Then Return
		Local pixels:Byte Ptr = Pixels()
		If pixels Then _DisplayDrawMono1Mask(pixels, bufferStride, bufferWidth, bufferHeight, ..
			bufferFormat, mask, maskStride, maskWidth, maskHeight, x, y, scale, clipX, clipY, ..
			clipX1 - clipX, clipY1 - clipY, color)
	End Method

	Rem
	bbdoc: Draws a clipped one-pixel circle outline using integer midpoint rasterisation.
	param: The centre x coordinate.
	param: The centre y coordinate.
	param: The non-negative radius in pixels.
	param: The clipping rectangle's left coordinate.
	param: The clipping rectangle's top coordinate.
	param: The clipping rectangle's width.
	param: The clipping rectangle's height.
	param: An $RRGGBB color; Mono1 treats zero as off and any non-zero value as on.
	End Rem
	Method DrawCircle(centerX:Int, centerY:Int, radius:Int, clipX:Int, clipY:Int, ..
			clipWidth:Int, clipHeight:Int, color:UInt = $ffffff)
		If radius < 0 Or clipWidth <= 0 Or clipHeight <= 0 Then Return
		Local clipX1:Int = clipX + clipWidth
		Local clipY1:Int = clipY + clipHeight
		If clipX < 0 Then clipX = 0
		If clipY < 0 Then clipY = 0
		If clipX1 > bufferWidth Then clipX1 = bufferWidth
		If clipY1 > bufferHeight Then clipY1 = bufferHeight
		If clipX >= clipX1 Or clipY >= clipY1 Then Return
		Local pixels:Byte Ptr = Pixels()
		If pixels Then _DisplayDrawCircle(pixels, bufferStride, bufferWidth, bufferHeight, ..
			bufferFormat, centerX, centerY, radius, clipX, clipY, clipX1 - clipX, ..
			clipY1 - clipY, color)
	End Method

	Rem
	bbdoc: Draws a clipped one-pixel line including both endpoints.
	param: The starting x coordinate.
	param: The starting y coordinate.
	param: The ending x coordinate.
	param: The ending y coordinate.
	param: An $RRGGBB color; Mono1 treats zero as off and any non-zero value as on.
	End Rem
	Method DrawLine(x0:Int, y0:Int, x1:Int, y1:Int, color:UInt = $ffffff)
		If y0 = y1 Then
			If x0 > x1 Then
				Local swap:Int = x0
				x0 = x1
				x1 = swap
			End If
			FillRect(x0, y0, x1 - x0 + 1, 1, color)
			Return
		End If
		If x0 = x1 Then
			If y0 > y1 Then
				Local swap:Int = y0
				y0 = y1
				y1 = swap
			End If
			FillRect(x0, y0, 1, y1 - y0 + 1, color)
			Return
		End If
		Local pixels:Byte Ptr = Pixels()
		If pixels Then
			_DisplayDrawLine(pixels, bufferStride, bufferWidth, bufferHeight, bufferFormat, ..
				x0, y0, x1, y1, color)
		End If
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
	Private
	Field configuredOrientation:Int

	Public
	Rem
	bbdoc: Returns the display's native physical width in pixels.
	returns: The physical width.
	End Rem
	Method Width:Int() Abstract

	Rem
	bbdoc: Returns the display's native physical height in pixels.
	returns: The physical height.
	End Rem
	Method Height:Int() Abstract

	Rem
	bbdoc: Returns the raster format preferred by this display driver.
	returns: A DisplayPixelFormat value.
	End Rem
	Method PreferredPixelFormat:Int() Abstract

	Rem
	bbdoc: Reports optional presentation behavior supported by this display.
	returns: A bitwise combination of DisplayCapability constants.
	about: Drivers which do not override this retain the original synchronous
	partial-presentation contract.
	End Rem
	Method Capabilities:Int()
		Return DisplayCapabilityPartialPresent
	End Method

	Rem
	bbdoc: Tests whether every requested display capability is available.
	param: A bitwise combination of DisplayCapability constants.
	returns: True when all requested capability bits are present.
	End Rem
	Method HasCapability:Int(capability:Int)
		Return (Capabilities() & capability) = capability
	End Method

	Rem
	bbdoc: Synchronously presents a rectangular region from a complete raster.
	param: A pointer to the first byte of the complete raster.
	param: The number of bytes between adjacent raster rows.
	param: A DisplayPixelFormat value describing the raster.
	param: The left edge of the region in physical display coordinates.
	param: The top edge of the region in physical display coordinates.
	param: The region width in pixels.
	param: The region height in pixels.
	returns: A positive value on success, or a DisplayError value on failure.
	about: The source pointer always addresses the full raster origin, not the
	first pixel of the requested region. The caller may reuse the memory after
	the method returns.
	End Rem
	Method PresentPixels:Int(pixels:Byte Ptr, stride:Int, format:Int, ..
	x:Int, y:Int, width:Int, height:Int) Abstract

	Rem
	bbdoc: Presents a complete raster without requiring its contents to remain available for the next frame.
	param: A pointer to the first byte of the complete raster.
	param: The number of bytes between adjacent raster rows.
	param: A DisplayPixelFormat value describing the raster.
	returns: A positive value on success, or a DisplayError value on failure.
	about: Drivers without a discard path safely retain the normal PresentPixels
	behavior. Callers must completely redraw the buffer before presenting it again.
	End Rem
	Method PresentPixelsDiscard:Int(pixels:Byte Ptr, stride:Int, format:Int)
		Return PresentPixels(pixels, stride, format, 0, 0, Width(), Height())
	End Method

	Rem
	bbdoc: Enables or disables the physical display output.
	param: True to enable output, or False to disable it.
	returns: True on success, or False when the operation fails or is unsupported.
	End Rem
	Method SetEnabled:Int(enabled:Int) Abstract

	Rem
	bbdoc: Configures the clockwise orientation used as rotation zero by drawing and input APIs.
	param: The clockwise orientation in degrees.
	returns: True for a supported quarter-turn orientation.
	End Rem
	Method SetOrientation:Int(degrees:Int)
		Local normalized:Int = NormalizeDisplayOrientation(degrees)
		If normalized < 0 Then Return False
		configuredOrientation = normalized
		Return True
	End Method

	Rem
	bbdoc: Returns the configured clockwise display orientation.
	returns: One of the DisplayOrientation constants.
	End Rem
	Method Orientation:Int()
		Return configuredOrientation
	End Method

	Rem
	bbdoc: Returns the width visible to orientation-aware drawing APIs.
	returns: The oriented logical width in pixels.
	End Rem
	Method LogicalWidth:Int()
		If configuredOrientation = DisplayOrientation90 Or ..
				configuredOrientation = DisplayOrientation270 Then Return Height()
		Return Width()
	End Method

	Rem
	bbdoc: Returns the height visible to orientation-aware drawing APIs.
	returns: The oriented logical height in pixels.
	End Rem
	Method LogicalHeight:Int()
		If configuredOrientation = DisplayOrientation90 Or ..
				configuredOrientation = DisplayOrientation270 Then Return Width()
		Return Height()
	End Method

	Rem
	bbdoc: Creates a managed full-screen buffer in the preferred pixel format.
	returns: A new zero-filled buffer, or Null when allocation or configuration fails.
	End Rem
	Method CreateBuffer:TDisplayBuffer()
		Return TDisplayBuffer.Create(Width(), Height(), PreferredPixelFormat())
	End Method

	Rem
	bbdoc: Presents the complete display area from a buffer.
	param: A raster at least as large as the physical display.
	returns: A positive value on success, or a DisplayError value on failure.
	End Rem
	Method Present:Int(buffer:TDisplayBuffer)
		If Not buffer Then
			Return DisplayErrorInvalidArgument
		End If

		Return PresentRegion(buffer, 0, 0, Width(), Height())
	End Method

	Rem
	bbdoc: Presents a complete buffer whose contents may then be discarded.
	param: A raster at least as large as the physical display.
	returns: A positive value on success, or a DisplayError value on failure.
	about: The caller must redraw the complete buffer before its next presentation.
	End Rem
	Method PresentDiscard:Int(buffer:TDisplayBuffer)
		If Not buffer Or buffer.Width() < Width() Or buffer.Height() < Height() Then ..
			Return DisplayErrorInvalidArgument

		Return PresentPixelsDiscard(buffer.Pixels(), buffer.Stride(), buffer.Format())
	End Method

	Rem
	bbdoc: Presents one physical display rectangle from a complete buffer.
	param: A raster at least as large as the physical display.
	param: The left edge of the region.
	param: The top edge of the region.
	param: The region width in pixels.
	param: The region height in pixels.
	returns: A positive value on success, or a DisplayError value on failure.
	End Rem
	Method PresentRegion:Int(buffer:TDisplayBuffer, x:Int, y:Int, width:Int, height:Int)
		If Not buffer Or buffer.Width() < Width() Or buffer.Height() < Height() Then ..
			Return DisplayErrorInvalidArgument

		Return PresentPixels(buffer.Pixels(), buffer.Stride(), buffer.Format(), ..
		x, y, width, height)
	End Method

	Rem
	bbdoc: Presents several independent dirty rectangles from one raster.
	param: A raster at least as large as the physical display.
	param: A pointer to an array of left coordinates.
	param: A pointer to an array of top coordinates.
	param: A pointer to an array of rectangle widths.
	param: A pointer to an array of rectangle heights.
	param: The number of rectangles in each array.
	returns: A positive value on success, or a DisplayError value on failure.
	about: The default synchronous implementation submits each rectangle in order.
	Framebuffer-swap drivers should override this method so the complete list is
	presented as one frame. Rectangle arrays must each contain at least count items.
	End Rem
	Method PresentRegions:Int(buffer:TDisplayBuffer, x:Int Ptr, y:Int Ptr, ..
			width:Int Ptr, height:Int Ptr, count:Int)
		If Not buffer Or buffer.Width() < Width() Or buffer.Height() < Height() Or ..
				Not x Or Not y Or Not width Or Not height Or count <= 0 Then ..
			Return DisplayErrorInvalidArgument
		For Local index:Int = 0 Until count
			Local result:Int = PresentRegion(buffer, x[index], y[index], width[index], height[index])
			If result <= 0 Then Return result
		Next
		Return True
	End Method
End Type
?
