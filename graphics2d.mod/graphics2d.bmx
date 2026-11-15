' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Familiar stateful 2D drawing over portable embedded display buffers.
about: TEmbedded2DContext provides explicit state for libraries and multiple
displays. The module-level functions use one default context for compact
Max2D-style applications. Drawing does not allocate or own another framebuffer.
End Rem
Module Embedded.Graphics2D
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Font
Import Embedded.Drivers.Display.Image

Private

Function ClampColorComponent:Int(value:Int)
	If value < 0 Then Return 0
	If value > 255 Then Return 255
	Return value
End Function

Public

Rem
bbdoc: Selects unrotated logical drawing.
End Rem
Const GraphicsRotation0:Int = DisplayOrientation0

Rem
bbdoc: Selects logical drawing rotated 90 degrees clockwise.
End Rem
Const GraphicsRotation90:Int = DisplayOrientation90

Rem
bbdoc: Selects logical drawing rotated 180 degrees clockwise.
End Rem
Const GraphicsRotation180:Int = DisplayOrientation180

Rem
bbdoc: Selects logical drawing rotated 270 degrees clockwise.
End Rem
Const GraphicsRotation270:Int = DisplayOrientation270

Rem
bbdoc: The maximum number of saved drawing states, including nested views.
End Rem
Const EmbeddedGraphicsStateMaximum:Int = 16

Rem
bbdoc: The maximum number of independently tracked dirty rectangles.
End Rem
Const EmbeddedGraphicsDirtyMaximum:Int = 8

Rem
bbdoc: Aligns wrapped text against the left edge of its text box.
End Rem
Const TextAlignLeft:Int = EmbeddedTextAlignLeft

Rem
bbdoc: Centers each wrapped line within its text box.
End Rem
Const TextAlignCenter:Int = EmbeddedTextAlignCenter

Rem
bbdoc: Aligns wrapped text against the right edge of its text box.
End Rem
Const TextAlignRight:Int = EmbeddedTextAlignRight

Rem
bbdoc: Mirrors an image horizontally while drawing.
End Rem
Const ImageFlipX:Int = EmbeddedImageDrawFlipX

Rem
bbdoc: Mirrors an image vertically while drawing.
End Rem
Const ImageFlipY:Int = EmbeddedImageDrawFlipY

Rem
bbdoc: Disables image color-key transparency.
End Rem
Const ImageColorKeyDisabled:UInt = EmbeddedImageColorKeyDisabled

Private

' A logical drawing view over a physical framebuffer. Keeping this as a buffer
' adapter means fonts, images, and future raster operations all inherit the
' same exact quarter-turn transform without allocating while drawing.
Type TGraphicsDisplayBuffer Extends TDisplayBuffer
	Field target:TDisplayBuffer
	Field logicalWidth:Int
	Field logicalHeight:Int
	Field xx:Int = 1
	Field xy:Int
	Field yx:Int
	Field yy:Int = 1
	Field tx:Int
	Field ty:Int

	Function Create:TGraphicsDisplayBuffer(target:TDisplayBuffer)
		Local view:TGraphicsDisplayBuffer = New TGraphicsDisplayBuffer
		view.target = target
		If target Then
			view.logicalWidth = target.Width()
			view.logicalHeight = target.Height()
		End If
		Return view
	End Function

	Method SetTransform(width:Int, height:Int, xx:Int, xy:Int, yx:Int, yy:Int, tx:Int, ty:Int)
		logicalWidth = width
		logicalHeight = height
		Self.xx = xx
		Self.xy = xy
		Self.yx = yx
		Self.yy = yy
		Self.tx = tx
		Self.ty = ty
	End Method

	Method Width:Int() Override
		Return logicalWidth
	End Method

	Method Height:Int() Override
		Return logicalHeight
	End Method

	Method Stride:Int() Override
		Return 0
	End Method

	Method Format:Int() Override
		If target Then Return target.Format()
		Return 0
	End Method

	Method Size:Int() Override
		Return 0
	End Method

	Method Bytes:Byte[]() Override
		Return Null
	End Method

	Method Pixels:Byte Ptr() Override
		Return Null
	End Method

	Method Clear(color:UInt = 0) Override
		If target Then target.Clear(color)
	End Method

	Method SetPixel(x:Int, y:Int, color:UInt = $ffffff) Override
		If Not target Or x < 0 Or y < 0 Or x >= Width() Or y >= Height() Then Return
		target.SetPixel(xx * x + xy * y + tx, yx * x + yy * y + ty, color)
	End Method

	Method Pixel:UInt(x:Int, y:Int) Override
		If Not target Or x < 0 Or y < 0 Or x >= Width() Or y >= Height() Then Return 0
		Return target.Pixel(xx * x + xy * y + tx, yx * x + yy * y + ty)
	End Method

	Method FillRect(x:Int, y:Int, width:Int, height:Int, color:UInt = $ffffff) Override
		If Not target Or width <= 0 Or height <= 0 Then Return
		Local x1:Int = x + width
		Local y1:Int = y + height
		If x < 0 Then x = 0
		If y < 0 Then y = 0
		If x1 > Width() Then x1 = Width()
		If y1 > Height() Then y1 = Height()
		If x >= x1 Or y >= y1 Then Return
		Local px0:Int
		Local py0:Int
		Local px1:Int
		Local py1:Int
		MapPoint(x, y, px0, py0)
		MapPoint(x1 - 1, y1 - 1, px1, py1)
		If px0 > px1 Then
			Local swap:Int = px0
			px0 = px1
			px1 = swap
		End If
		If py0 > py1 Then
			Local swap:Int = py0
			py0 = py1
			py1 = swap
		End If
		target.FillRect(px0, py0, px1 - px0 + 1, py1 - py0 + 1, color)
	End Method

	Method DrawLine(x0:Int, y0:Int, x1:Int, y1:Int, color:UInt = $ffffff) Override
		If Not target Then Return
		Local tx0:Int
		Local ty0:Int
		Local tx1:Int
		Local ty1:Int
		MapPoint(x0, y0, tx0, ty0)
		MapPoint(x1, y1, tx1, ty1)
		target.DrawLine(tx0, ty0, tx1, ty1, color)
	End Method

	Private
	Method MapPoint(x:Int, y:Int, targetX:Int Var, targetY:Int Var)
		targetX = xx * x + xy * y + tx
		targetY = yx * x + yy * y + ty
	End Method
End Type

Type TEmbedded2DSavedState
	Field font:TBitmapFont
	Field drawColor:UInt
	Field clearColor:UInt
	Field originX:Int
	Field originY:Int
	Field viewportX:Int
	Field viewportY:Int
	Field viewportWidth:Int
	Field viewportHeight:Int
	Field viewClipX:Int
	Field viewClipY:Int
	Field viewClipWidth:Int
	Field viewClipHeight:Int
	Field logicalWidth:Int
	Field logicalHeight:Int
	Field xx:Int
	Field xy:Int
	Field yx:Int
	Field yy:Int
	Field tx:Int
	Field ty:Int
	Field rotation:Int
	Field viewDepth:Int
	Field viewBoundary:Int
End Type

Public

Rem
bbdoc: Stateful allocation-free drawing context for one display buffer.
about: Origins affect drawing coordinates. Viewports are always expressed in
the current logical view and clip every primitive, including text.
End Rem
Type TEmbedded2DContext Final
	Private
	Field target:TDisplayBuffer
	Field boundDisplay:TDisplay
	Field currentFont:TBitmapFont
	Field drawColor:UInt = $ffffff
	Field clearColor:UInt
	Field originX:Int
	Field originY:Int
	Field viewportX:Int
	Field viewportY:Int
	Field viewportWidth:Int
	Field viewportHeight:Int
	Field viewClipX:Int
	Field viewClipY:Int
	Field viewClipWidth:Int
	Field viewClipHeight:Int
	Field logicalWidth:Int
	Field logicalHeight:Int
	Field transformXX:Int = 1
	Field transformXY:Int
	Field transformYX:Int
	Field transformYY:Int = 1
	Field transformTX:Int
	Field transformTY:Int
	Field rotation:Int
	Field drawingTarget:TGraphicsDisplayBuffer
	Field savedStates:TEmbedded2DSavedState[EmbeddedGraphicsStateMaximum]
	Field stateDepth:Int
	Field viewDepth:Int
	Field dirtyTracking:Int
	Field dirtyValid:Int
	Field dirtyX0:Int
	Field dirtyY0:Int
	Field dirtyX1:Int
	Field dirtyY1:Int
	Field dirtyCount:Int
	Field dirtyRegionX0:Int[EmbeddedGraphicsDirtyMaximum]
	Field dirtyRegionY0:Int[EmbeddedGraphicsDirtyMaximum]
	Field dirtyRegionX1:Int[EmbeddedGraphicsDirtyMaximum]
	Field dirtyRegionY1:Int[EmbeddedGraphicsDirtyMaximum]

	Public
	Rem
	bbdoc: Creates an unbound drawing context with preallocated state storage.
	End Rem
	Method New()
		For Local index:Int = 0 Until EmbeddedGraphicsStateMaximum
			savedStates[index] = New TEmbedded2DSavedState
		Next
	End Method

	Rem
	bbdoc: Creates a drawing context bound to a raster and optional display.
	param: The raster buffer that receives drawing operations.
	param: The display used for orientation and presentation, or Null for buffer-only drawing.
	returns: A new drawing context.
	End Rem
	Function Create:TEmbedded2DContext(target:TDisplayBuffer, display:TDisplay = Null)
		Local context:TEmbedded2DContext = New TEmbedded2DContext
		context.SetRenderTarget(target, display)
		Return context
	End Function

	Rem
	bbdoc: Rebinds this context and resets its transform, viewport, views, state stack, and dirty regions.
	param: The raster buffer that receives drawing operations, or Null to unbind the context.
	param: The display used for orientation and presentation, or Null for buffer-only drawing.
	End Rem
	Method SetRenderTarget(target:TDisplayBuffer, display:TDisplay = Null)
		Self.target = target
		boundDisplay = display
		drawingTarget = TGraphicsDisplayBuffer.Create(target)
		stateDepth = 0
		viewDepth = 0
		originX = 0
		originY = 0
		ResetDirty()
		ResetRootTransform()
	End Method

	Rem
	bbdoc: Returns the physical raster receiving drawing operations.
	returns: The bound display buffer, or Null when unbound.
	End Rem
	Method RenderTarget:TDisplayBuffer()
		Return target
	End Method

	Rem
	bbdoc: Rebinds the display used for orientation and presentation.
	param: The new display, or Null to retain buffer-only drawing.
	returns: True on success, or False while drawing state or a view is saved.
	End Rem
	Method SetDisplay:Int(display:TDisplay)
		If stateDepth Then Return False
		boundDisplay = display
		ResetRootTransform()
		Return True
	End Method

	Rem
	bbdoc: Returns the display associated with this context.
	returns: The bound display, or Null when none is configured.
	End Rem
	Method Display:TDisplay()
		Return boundDisplay
	End Method

	Rem
	bbdoc: Selects clockwise logical canvas rotation in quarter turns.
	param: The clockwise drawing rotation in degrees.
	about: Valid values are 0, 90, 180, and 270 degrees. Negative and greater-than-
	360 values are normalized. A successful change resets the viewport to the new
	logical canvas dimensions while retaining the origin, colours, and font.
	returns: True when the requested angle is a supported quarter turn.
	End Rem
	Method SetRotation:Int(degrees:Int)
		If viewDepth Then Return False
		Local normalized:Int = NormalizeDisplayOrientation(degrees)
		If normalized < 0 Then Return False
		rotation = normalized
		ResetRootTransform()
		Return True
	End Method

	Rem
	bbdoc: Returns the drawing rotation relative to the configured display orientation.
	returns: One of the GraphicsRotation constants.
	End Rem
	Method Rotation:Int()
		Return rotation
	End Method

	Rem
	bbdoc: Returns the configured device orientation used as drawing rotation zero.
	returns: One of the DisplayOrientation constants.
	End Rem
	Method Orientation:Int()
		If boundDisplay Then Return boundDisplay.Orientation()
		Return DisplayOrientation0
	End Method

	Rem
	bbdoc: Changes the bound display's configured orientation at runtime.
	param: The clockwise orientation in degrees.
	returns: True when a display is bound and accepts the requested quarter turn.
	about: The relative drawing rotation is retained and the viewport is reset to
	the new logical dimensions. Configure an associated touch device with the same
	orientation so its events remain aligned.
	End Rem
	Method SetDisplayOrientation:Int(degrees:Int)
		If stateDepth Then Return False
		If Not boundDisplay Or Not boundDisplay.SetOrientation(degrees) Then Return False
		ResetRootTransform()
		Return True
	End Method

	Rem
	bbdoc: Returns the physical quarter-turn produced by orientation plus drawing rotation.
	returns: One of the DisplayOrientation constants.
	End Rem
	Method EffectiveRotation:Int()
		Return (Orientation() + rotation) Mod 360
	End Method

	Rem
	bbdoc: Returns the logical drawing width after rotation.
	returns: The current view width in logical pixels.
	End Rem
	Method Width:Int()
		Return logicalWidth
	End Method

	Rem
	bbdoc: Returns the logical drawing height after rotation.
	returns: The current view height in logical pixels.
	End Rem
	Method Height:Int()
		Return logicalHeight
	End Method

	Rem
	bbdoc: Returns the root screen width before any relative drawing rotation.
	returns: The orientation-aware root width in pixels.
	End Rem
	Method ScreenWidth:Int()
		If boundDisplay Then Return boundDisplay.LogicalWidth()
		If Not target Then Return 0
		If Orientation() = DisplayOrientation90 Or Orientation() = DisplayOrientation270 Then ..
			Return target.Height()
		Return target.Width()
	End Method

	Rem
	bbdoc: Returns the root screen height before any relative drawing rotation.
	returns: The orientation-aware root height in pixels.
	End Rem
	Method ScreenHeight:Int()
		If boundDisplay Then Return boundDisplay.LogicalHeight()
		If Not target Then Return 0
		If Orientation() = DisplayOrientation90 Or Orientation() = DisplayOrientation270 Then ..
			Return target.Width()
		Return target.Height()
	End Method

	Rem
	bbdoc: Selects the bitmap font used by subsequent text operations.
	param: The font to use, or Null to disable text drawing.
	End Rem
	Method SetFont(font:TBitmapFont)
		currentFont = font
	End Method

	Rem
	bbdoc: Returns the currently selected bitmap font.
	returns: The selected font, or Null when no font is active.
	End Rem
	Method Font:TBitmapFont()
		Return currentFont
	End Method

	Rem
	bbdoc: Sets the drawing color from clamped RGB components.
	param: The red component from 0 to 255.
	param: The green component from 0 to 255.
	param: The blue component from 0 to 255.
	End Rem
	Method SetColor(red:Int, green:Int, blue:Int)
		drawColor = UInt(ClampColorComponent(red) Shl 16) | ..
			UInt(ClampColorComponent(green) Shl 8) | UInt(ClampColorComponent(blue))
	End Method

	Rem
	bbdoc: Sets the drawing color from an $RRGGBB value.
	param: The drawing color; bits above the low 24 are ignored.
	End Rem
	Method SetColorValue(color:UInt)
		drawColor = color & $ffffff
	End Method

	Rem
	bbdoc: Returns the current drawing color.
	returns: An $RRGGBB color value.
	End Rem
	Method Color:UInt()
		Return drawColor
	End Method

	Rem
	bbdoc: Sets the clear color from clamped RGB components.
	param: The red component from 0 to 255.
	param: The green component from 0 to 255.
	param: The blue component from 0 to 255.
	End Rem
	Method SetClsColor(red:Int, green:Int, blue:Int)
		clearColor = UInt(ClampColorComponent(red) Shl 16) | ..
			UInt(ClampColorComponent(green) Shl 8) | UInt(ClampColorComponent(blue))
	End Method

	Rem
	bbdoc: Sets the clear color from an $RRGGBB value.
	param: The clear color; bits above the low 24 are ignored.
	End Rem
	Method SetClsColorValue(color:UInt)
		clearColor = color & $ffffff
	End Method

	Rem
	bbdoc: Returns the current clear color.
	returns: An $RRGGBB color value.
	End Rem
	Method ClsColor:UInt()
		Return clearColor
	End Method

	Rem
	bbdoc: Sets the translation added to subsequent drawing coordinates.
	param: The horizontal logical offset.
	param: The vertical logical offset.
	End Rem
	Method SetOrigin(x:Int, y:Int)
		originX = x
		originY = y
	End Method

	Rem
	bbdoc: Returns the current horizontal drawing origin.
	returns: The logical x offset.
	End Rem
	Method OriginX:Int()
		Return originX
	End Method

	Rem
	bbdoc: Returns the current vertical drawing origin.
	returns: The logical y offset.
	End Rem
	Method OriginY:Int()
		Return originY
	End Method

	Rem
	bbdoc: Restricts drawing to a rectangle within the current view.
	param: The logical left edge, unaffected by the drawing origin.
	param: The logical top edge, unaffected by the drawing origin.
	param: The viewport width in pixels.
	param: The viewport height in pixels.
	about: The requested rectangle is clipped to the current view. Invalid or
	empty dimensions establish an empty viewport in which nothing is drawn.
	End Rem
	Method SetViewport(x:Int, y:Int, width:Int, height:Int)
		If Not target Or width <= 0 Or height <= 0 Then
			viewportX = 0
			viewportY = 0
			viewportWidth = 0
			viewportHeight = 0
			Return
		End If
		Local x1:Int = x + width
		Local y1:Int = y + height
		Local clipX1:Int = viewClipX + viewClipWidth
		Local clipY1:Int = viewClipY + viewClipHeight
		If x < viewClipX Then x = viewClipX
		If y < viewClipY Then y = viewClipY
		If x1 > clipX1 Then x1 = clipX1
		If y1 > clipY1 Then y1 = clipY1
		If x1 <= x Or y1 <= y Then
			viewportWidth = 0
			viewportHeight = 0
			Return
		End If
		viewportX = x
		viewportY = y
		viewportWidth = x1 - x
		viewportHeight = y1 - y
	End Method

	Rem
	bbdoc: Restores the viewport to the complete current view.
	End Rem
	Method ResetViewport()
		If target Then
			viewportX = viewClipX
			viewportY = viewClipY
			viewportWidth = viewClipWidth
			viewportHeight = viewClipHeight
		Else
			viewportX = 0
			viewportY = 0
			viewportWidth = 0
			viewportHeight = 0
		End If
	End Method

	Rem
	bbdoc: Returns the clipped viewport's logical left edge.
	returns: The viewport x coordinate.
	End Rem
	Method ViewportX:Int()
		Return viewportX
	End Method

	Rem
	bbdoc: Returns the clipped viewport's logical top edge.
	returns: The viewport y coordinate.
	End Rem
	Method ViewportY:Int()
		Return viewportY
	End Method

	Rem
	bbdoc: Returns the clipped viewport width.
	returns: The width in pixels, or zero for an empty viewport.
	End Rem
	Method ViewportWidth:Int()
		Return viewportWidth
	End Method

	Rem
	bbdoc: Returns the clipped viewport height.
	returns: The height in pixels, or zero for an empty viewport.
	End Rem
	Method ViewportHeight:Int()
		Return viewportHeight
	End Method

	Rem
	bbdoc: Enables or disables automatic dirty-region tracking for this context.
	param: True to record drawing bounds, or False to disable tracking.
	about: Enabling starts with an empty region. Tracking records physical
	framebuffer bounds so the result can be passed directly to PresentRegion.
	End Rem
	Method SetDirtyTracking(enabled:Int = True)
		dirtyTracking = enabled <> 0
		ResetDirty()
	End Method

	Rem
	bbdoc: Reports whether automatic dirty-region tracking is enabled.
	returns: True when drawing operations accumulate dirty rectangles.
	End Rem
	Method DirtyTracking:Int()
		Return dirtyTracking
	End Method

	Rem
	bbdoc: Clears the accumulated dirty region without changing framebuffer pixels.
	End Rem
	Method ResetDirty()
		dirtyValid = False
		dirtyCount = 0
		dirtyX0 = 0
		dirtyY0 = 0
		dirtyX1 = 0
		dirtyY1 = 0
	End Method

	Rem
	bbdoc: Returns the number of independent accumulated dirty rectangles.
	returns: A value from zero through EmbeddedGraphicsDirtyMaximum.
	End Rem
	Method DirtyRegionCount:Int()
		Return dirtyCount
	End Method

	Rem
	bbdoc: Returns one accumulated physical framebuffer rectangle.
	param: The zero-based dirty-region index.
	param: Receives the physical left edge.
	param: Receives the physical top edge.
	param: Receives the physical width.
	param: Receives the physical height.
	returns: False when the index is outside the current dirty-region list.
	End Rem
	Method DirtyRegion:Int(index:Int, x:Int Var, y:Int Var, width:Int Var, height:Int Var)
		If index < 0 Or index >= dirtyCount Then
			x = 0
			y = 0
			width = 0
			height = 0
			Return False
		End If
		x = dirtyRegionX0[index]
		y = dirtyRegionY0[index]
		width = dirtyRegionX1[index] - x
		height = dirtyRegionY1[index] - y
		Return True
	End Method

	Rem
	bbdoc: Returns the accumulated physical framebuffer rectangle.
	param: Receives the physical left edge.
	param: Receives the physical top edge.
	param: Receives the physical width.
	param: Receives the physical height.
	returns: False when no drawing has been recorded.
	End Rem
	Method DirtyRect:Int(x:Int Var, y:Int Var, width:Int Var, height:Int Var)
		If Not dirtyValid Then
			x = 0
			y = 0
			width = 0
			height = 0
			Return False
		End If
		x = dirtyX0
		y = dirtyY0
		width = dirtyX1 - dirtyX0
		height = dirtyY1 - dirtyY0
		Return True
	End Method

	Rem
	bbdoc: Adds a rectangle in the current view to the dirty region.
	param: The left edge relative to the current origin.
	param: The top edge relative to the current origin.
	param: The rectangle width in pixels.
	param: The rectangle height in pixels.
	about: The current origin, viewport, nested view, drawing rotation, and device
	orientation are applied exactly as they are for drawing operations.
	End Rem
	Method InvalidateRect(x:Int, y:Int, width:Int, height:Int)
		MarkDirtyLogical(x + originX, y + originY, width, height)
	End Method

	Rem
	bbdoc: Marks the complete current logical canvas dirty.
	End Rem
	Method InvalidateAll()
		MarkDirtyLogical(0, 0, logicalWidth, logicalHeight)
	End Method

	Rem
	bbdoc: Fills the current viewport with the clear color.
	about: Clearing a root full-screen viewport may use the display buffer's
	optimized clear path. Nested views and clipped viewports remain bounded.
	End Rem
	Method Cls()
		If Not target Or viewportWidth <= 0 Or viewportHeight <= 0 Then Return
		MarkDirtyLogical(viewportX, viewportY, viewportWidth, viewportHeight)
		If viewDepth = 0 And viewportX = 0 And viewportY = 0 And viewportWidth = Width() And ..
				viewportHeight = Height() Then
			target.Clear(clearColor)
		Else
			DrawingTarget().FillRect(viewportX, viewportY, viewportWidth, viewportHeight, clearColor)
		End If
	End Method

	Rem
	bbdoc: Draws one pixel using the current color.
	param: The x coordinate relative to the current origin.
	param: The y coordinate relative to the current origin.
	End Rem
	Method Plot(x:Int, y:Int)
		If Not target Then Return
		x :+ originX
		y :+ originY
		If PointVisible(x, y) Then
			MarkDirtyLogical(x, y, 1, 1)
			DrawingTarget().SetPixel(x, y, drawColor)
		End If
	End Method

	Rem
	bbdoc: Draws a clipped one-pixel line including both endpoints.
	param: The starting x coordinate relative to the current origin.
	param: The starting y coordinate relative to the current origin.
	param: The ending x coordinate relative to the current origin.
	param: The ending y coordinate relative to the current origin.
	End Rem
	Method DrawLine(x0:Int, y0:Int, x1:Int, y1:Int)
		If Not target Or viewportWidth <= 0 Or viewportHeight <= 0 Then Return
		x0 :+ originX
		y0 :+ originY
		x1 :+ originX
		y1 :+ originY
		If Not ClipLine(x0, y0, x1, y1) Then Return
		Local dirtyX:Int = x0
		Local dirtyY:Int = y0
		Local dirtyWidth:Int = x1 - x0
		Local dirtyHeight:Int = y1 - y0
		If dirtyWidth < 0 Then
			dirtyX = x1
			dirtyWidth = -dirtyWidth
		End If
		If dirtyHeight < 0 Then
			dirtyY = y1
			dirtyHeight = -dirtyHeight
		End If
		MarkDirtyLogical(dirtyX, dirtyY, dirtyWidth + 1, dirtyHeight + 1)
		DrawingTarget().DrawLine(x0, y0, x1, y1, drawColor)
	End Method

	Rem
	bbdoc: Draws the one-pixel outline of a rectangle using the current color.
	param: The left coordinate relative to the current origin.
	param: The top coordinate relative to the current origin.
	param: The rectangle width in pixels.
	param: The rectangle height in pixels.
	End Rem
	Method DrawRect(x:Int, y:Int, width:Int, height:Int)
		If width <= 0 Or height <= 0 Then Return
		DrawLine(x, y, x + width - 1, y)
		DrawLine(x, y + height - 1, x + width - 1, y + height - 1)
		DrawLine(x, y, x, y + height - 1)
		DrawLine(x + width - 1, y, x + width - 1, y + height - 1)
	End Method

	Rem
	bbdoc: Draws a circle using integer midpoint rasterisation.
	param: The centre x coordinate relative to the current origin.
	param: The centre y coordinate relative to the current origin.
	param: The radius in pixels.
	End Rem
	Method DrawCircle(centerX:Int, centerY:Int, radius:Int)
		If radius < 0 Then Return
		If radius = 0 Then
			Plot(centerX, centerY)
			Return
		End If
		If Not target Or viewportWidth <= 0 Or viewportHeight <= 0 Then Return
		centerX :+ originX
		centerY :+ originY
		MarkDirtyLogical(centerX - radius, centerY - radius, radius * 2 + 1, radius * 2 + 1)
		Local raster:TDisplayBuffer = DrawingTarget()
		Local x:Int = radius
		Local y:Int
		Local error:Int = 1 - radius
		While x >= y
			PlotLogicalUntracked(raster, centerX + x, centerY + y)
			PlotLogicalUntracked(raster, centerX + y, centerY + x)
			PlotLogicalUntracked(raster, centerX - y, centerY + x)
			PlotLogicalUntracked(raster, centerX - x, centerY + y)
			PlotLogicalUntracked(raster, centerX - x, centerY - y)
			PlotLogicalUntracked(raster, centerX - y, centerY - x)
			PlotLogicalUntracked(raster, centerX + y, centerY - x)
			PlotLogicalUntracked(raster, centerX + x, centerY - y)
			y :+ 1
			If error < 0 Then
				error :+ 2 * y + 1
			Else
				x :- 1
				error :+ 2 * (y - x + 1)
			End If
		Wend
	End Method

	Rem
	bbdoc: Draws a filled circle using clipped horizontal spans.
	param: The centre x coordinate relative to the current origin.
	param: The centre y coordinate relative to the current origin.
	param: The radius in pixels.
	End Rem
	Method FillCircle(centerX:Int, centerY:Int, radius:Int)
		If radius < 0 Then Return
		If Not target Or viewportWidth <= 0 Or viewportHeight <= 0 Then Return
		centerX :+ originX
		centerY :+ originY
		MarkDirtyLogical(centerX - radius, centerY - radius, radius * 2 + 1, radius * 2 + 1)
		Local raster:TDisplayBuffer = DrawingTarget()
		Local extent:Int
		Local radiusSquared:Long = Long(radius) * radius
		For Local offset:Int = radius To 0 Step -1
			While extent < radius And Long(extent + 1) * (extent + 1) + ..
				Long(offset) * offset <= radiusSquared
				extent :+ 1
			Wend
			FillLogicalSpanUntracked(raster, centerX - extent, centerX + extent, centerY - offset)
			If offset Then FillLogicalSpanUntracked(raster, centerX - extent, ..
				centerX + extent, centerY + offset)
		Next
	End Method

	Rem
	bbdoc: Draws an ellipse from its centre and horizontal and vertical radii.
	param: The centre x coordinate relative to the current origin.
	param: The centre y coordinate relative to the current origin.
	param: The horizontal radius in pixels.
	param: The vertical radius in pixels.
	End Rem
	Method DrawEllipse(centerX:Int, centerY:Int, radiusX:Int, radiusY:Int)
		If radiusX < 0 Or radiusY < 0 Then Return
		If radiusX = 0 Then
			DrawLine(centerX, centerY - radiusY, centerX, centerY + radiusY)
			Return
		End If
		If radiusY = 0 Then
			DrawLine(centerX - radiusX, centerY, centerX + radiusX, centerY)
			Return
		End If

		' Plot both the horizontal and vertical boundary samples. Combining the
		' two monotonic passes avoids holes on very wide or very tall ellipses.
		Local radiusXSquared:Long = Long(radiusX) * radiusX
		Local radiusYSquared:Long = Long(radiusY) * radiusY
		Local extentX:Int = radiusX
		For Local offsetY:Int = 0 To radiusY
			While extentX > 0 And Long(extentX) * extentX * radiusYSquared + ..
				Long(offsetY) * offsetY * radiusXSquared > radiusXSquared * radiusYSquared
				extentX :- 1
			Wend
			Plot(centerX - extentX, centerY - offsetY)
			Plot(centerX + extentX, centerY - offsetY)
			If offsetY Then
				Plot(centerX - extentX, centerY + offsetY)
				Plot(centerX + extentX, centerY + offsetY)
			End If
		Next
		Local extentY:Int = radiusY
		For Local offsetX:Int = 0 To radiusX
			While extentY > 0 And Long(offsetX) * offsetX * radiusYSquared + ..
				Long(extentY) * extentY * radiusXSquared > radiusXSquared * radiusYSquared
				extentY :- 1
			Wend
			Plot(centerX - offsetX, centerY - extentY)
			Plot(centerX - offsetX, centerY + extentY)
			If offsetX Then
				Plot(centerX + offsetX, centerY - extentY)
				Plot(centerX + offsetX, centerY + extentY)
			End If
		Next
	End Method

	Rem
	bbdoc: Draws a filled ellipse from its centre and radii.
	param: The centre x coordinate relative to the current origin.
	param: The centre y coordinate relative to the current origin.
	param: The horizontal radius in pixels.
	param: The vertical radius in pixels.
	End Rem
	Method FillEllipse(centerX:Int, centerY:Int, radiusX:Int, radiusY:Int)
		If radiusX < 0 Or radiusY < 0 Then Return
		If radiusX = 0 Then
			DrawLine(centerX, centerY - radiusY, centerX, centerY + radiusY)
			Return
		End If
		If radiusY = 0 Then
			DrawLine(centerX - radiusX, centerY, centerX + radiusX, centerY)
			Return
		End If
		Local radiusXSquared:Long = Long(radiusX) * radiusX
		Local radiusYSquared:Long = Long(radiusY) * radiusY
		Local limit:Long = radiusXSquared * radiusYSquared
		Local extentX:Int = radiusX
		For Local offsetY:Int = 0 To radiusY
			While extentX > 0 And Long(extentX) * extentX * radiusYSquared + ..
				Long(offsetY) * offsetY * radiusXSquared > limit
				extentX :- 1
			Wend
			DrawLine(centerX - extentX, centerY - offsetY, centerX + extentX, centerY - offsetY)
			If offsetY Then ..
				DrawLine(centerX - extentX, centerY + offsetY, centerX + extentX, centerY + offsetY)
		Next
	End Method

	Rem
	bbdoc: Draws the three one-pixel edges of a triangle.
	param: The first vertex x coordinate.
	param: The first vertex y coordinate.
	param: The second vertex x coordinate.
	param: The second vertex y coordinate.
	param: The third vertex x coordinate.
	param: The third vertex y coordinate.
	End Rem
	Method DrawTriangle(x0:Int, y0:Int, x1:Int, y1:Int, x2:Int, y2:Int)
		DrawLine(x0, y0, x1, y1)
		DrawLine(x1, y1, x2, y2)
		DrawLine(x2, y2, x0, y0)
	End Method

	Rem
	bbdoc: Draws a filled triangle using deterministic integer scanlines.
	param: The first vertex x coordinate.
	param: The first vertex y coordinate.
	param: The second vertex x coordinate.
	param: The second vertex y coordinate.
	param: The third vertex x coordinate.
	param: The third vertex y coordinate.
	End Rem
	Method FillTriangle(x0:Int, y0:Int, x1:Int, y1:Int, x2:Int, y2:Int)
		Local swap:Int
		If y1 < y0 Then
			swap = x0
			x0 = x1
			x1 = swap
			swap = y0
			y0 = y1
			y1 = swap
		End If
		If y2 < y0 Then
			swap = x0
			x0 = x2
			x2 = swap
			swap = y0
			y0 = y2
			y2 = swap
		End If
		If y2 < y1 Then
			swap = x1
			x1 = x2
			x2 = swap
			swap = y1
			y1 = y2
			y2 = swap
		End If
		If y0 = y2 Then
			Local minimumX:Int = x0
			Local maximumX:Int = x0
			If x1 < minimumX Then minimumX = x1
			If x2 < minimumX Then minimumX = x2
			If x1 > maximumX Then maximumX = x1
			If x2 > maximumX Then maximumX = x2
			DrawLine(minimumX, y0, maximumX, y0)
			Return
		End If
		For Local y:Int = y0 To y2
			Local edgeX:Int = x0 + Int(Long(x2 - x0) * (y - y0) / (y2 - y0))
			Local splitX:Int
			If y < y1 And y1 <> y0 Then
				splitX = x0 + Int(Long(x1 - x0) * (y - y0) / (y1 - y0))
			Else If y2 <> y1 Then
				splitX = x1 + Int(Long(x2 - x1) * (y - y1) / (y2 - y1))
			Else
				splitX = x1
			End If
			If edgeX <= splitX Then
				DrawLine(edgeX, y, splitX, y)
			Else
				DrawLine(splitX, y, edgeX, y)
			End If
		Next
	End Method

	Rem
	bbdoc: Draws the one-pixel outline of a rounded rectangle.
	param: The left coordinate relative to the current origin.
	param: The top coordinate relative to the current origin.
	param: The rectangle width in pixels.
	param: The rectangle height in pixels.
	param: The corner radius, clamped to half the shortest dimension.
	End Rem
	Method DrawRoundRect(x:Int, y:Int, width:Int, height:Int, radius:Int)
		If width <= 0 Or height <= 0 Or radius < 0 Then Return
		Local maximumRadius:Int = width / 2
		If height / 2 < maximumRadius Then maximumRadius = height / 2
		If radius > maximumRadius Then radius = maximumRadius
		If radius = 0 Then
			DrawRect(x, y, width, height)
			Return
		End If
		Local leftCenter:Int = x + radius
		Local rightCenter:Int = x + width - radius - 1
		Local topCenter:Int = y + radius
		Local bottomCenter:Int = y + height - radius - 1
		DrawLine(leftCenter, y, rightCenter, y)
		DrawLine(leftCenter, y + height - 1, rightCenter, y + height - 1)
		DrawLine(x, topCenter, x, bottomCenter)
		DrawLine(x + width - 1, topCenter, x + width - 1, bottomCenter)
		Local curveX:Int = radius
		Local curveY:Int
		Local error:Int = 1 - radius
		While curveX >= curveY
			Plot(leftCenter - curveX, topCenter - curveY)
			Plot(leftCenter - curveY, topCenter - curveX)
			Plot(rightCenter + curveX, topCenter - curveY)
			Plot(rightCenter + curveY, topCenter - curveX)
			Plot(leftCenter - curveX, bottomCenter + curveY)
			Plot(leftCenter - curveY, bottomCenter + curveX)
			Plot(rightCenter + curveX, bottomCenter + curveY)
			Plot(rightCenter + curveY, bottomCenter + curveX)
			curveY :+ 1
			If error < 0 Then
				error :+ 2 * curveY + 1
			Else
				curveX :- 1
				error :+ 2 * (curveY - curveX + 1)
			End If
		Wend
	End Method

	Rem
	bbdoc: Draws a filled rounded rectangle.
	param: The left coordinate relative to the current origin.
	param: The top coordinate relative to the current origin.
	param: The rectangle width in pixels.
	param: The rectangle height in pixels.
	param: The corner radius, clamped to half the shortest dimension.
	End Rem
	Method FillRoundRect(x:Int, y:Int, width:Int, height:Int, radius:Int)
		If width <= 0 Or height <= 0 Or radius < 0 Then Return
		Local maximumRadius:Int = width / 2
		If height / 2 < maximumRadius Then maximumRadius = height / 2
		If radius > maximumRadius Then radius = maximumRadius
		If radius = 0 Then
			FillRect(x, y, width, height)
			Return
		End If
		Local leftCenter:Int = x + radius
		Local rightCenter:Int = x + width - radius - 1
		Local topCenter:Int = y + radius
		Local bottomCenter:Int = y + height - radius - 1
		Local extent:Int
		Local radiusSquared:Long = Long(radius) * radius
		For Local offset:Int = radius To 0 Step -1
			While extent < radius And Long(extent + 1) * (extent + 1) + ..
				Long(offset) * offset <= radiusSquared
				extent :+ 1
			Wend
			DrawLine(leftCenter - extent, topCenter - offset, ..
				rightCenter + extent, topCenter - offset)
			If offset Then DrawLine(leftCenter - extent, bottomCenter + offset, ..
				rightCenter + extent, bottomCenter + offset)
		Next
		' The upper arc already supplies topCenter. Fill through bottomCenter so
		' the lower arc begins on the following row without a one-pixel seam.
		If bottomCenter > topCenter Then ..
			FillRect(x, topCenter + 1, width, bottomCenter - topCenter)
	End Method

	Rem
	bbdoc: Fills a clipped rectangle using the current drawing color.
	param: The left coordinate relative to the current origin.
	param: The top coordinate relative to the current origin.
	param: The rectangle width in pixels.
	param: The rectangle height in pixels.
	End Rem
	Method FillRect(x:Int, y:Int, width:Int, height:Int)
		If Not target Or width <= 0 Or height <= 0 Or viewportWidth <= 0 Or viewportHeight <= 0 Then Return
		x :+ originX
		y :+ originY
		Local x1:Int = x + width
		Local y1:Int = y + height
		Local viewportX1:Int = viewportX + viewportWidth
		Local viewportY1:Int = viewportY + viewportHeight
		If x < viewportX Then x = viewportX
		If y < viewportY Then y = viewportY
		If x1 > viewportX1 Then x1 = viewportX1
		If y1 > viewportY1 Then y1 = viewportY1
		If x < x1 And y < y1 Then
			MarkDirtyLogical(x, y, x1 - x, y1 - y)
			DrawingTarget().FillRect(x, y, x1 - x, y1 - y, drawColor)
		End If
	End Method

	Rem
	bbdoc: Saves the complete drawing state on a fixed-depth stack.
	returns: True on success, or False when the fixed-depth stack is full.
	End Rem
	Method PushState:Int()
		Return PushStateInternal(False)
	End Method

	Rem
	bbdoc: Restores the most recently saved drawing state.
	returns: True on success, or False when the stack is empty.
	End Rem
	Method PopState:Int()
		If stateDepth <= 0 Then Return False
		stateDepth :- 1
		RestoreState(savedStates[stateDepth])
		Return True
	End Method

	Rem
	bbdoc: Returns the number of saved drawing states.
	returns: The current state-stack depth.
	End Rem
	Method StateDepth:Int()
		Return stateDepth
	End Method

	Rem
	bbdoc: Begins a clipped local drawing view with an optional clockwise quarter-turn.
	param: The view's left edge in its parent coordinate system.
	param: The view's top edge in its parent coordinate system.
	param: The physical width occupied in the parent view.
	param: The physical height occupied in the parent view.
	param: The clockwise rotation applied inside the view.
	about: The rectangle is expressed in the parent view. Drawing inside it uses
	local coordinates, origin, viewport, and logical dimensions. Views may be nested.
	returns: True on success, or False for an invalid rotation, empty size, or full state stack.
	End Rem
	Method BeginView:Int(x:Int, y:Int, width:Int, height:Int, viewRotation:Int = 0)
		Local normalized:Int = NormalizeDisplayOrientation(viewRotation)
		If Not target Or width <= 0 Or height <= 0 Or normalized < 0 Then Return False

		x :+ originX
		y :+ originY
		If Not PushStateInternal(True) Then Return False

		Local intersectionX0:Int = x
		Local intersectionY0:Int = y
		Local intersectionX1:Int = x + width
		Local intersectionY1:Int = y + height
		If intersectionX0 < viewportX Then intersectionX0 = viewportX
		If intersectionY0 < viewportY Then intersectionY0 = viewportY
		If intersectionX1 > viewportX + viewportWidth Then intersectionX1 = viewportX + viewportWidth
		If intersectionY1 > viewportY + viewportHeight Then intersectionY1 = viewportY + viewportHeight
		If intersectionX1 < intersectionX0 Then intersectionX1 = intersectionX0
		If intersectionY1 < intersectionY0 Then intersectionY1 = intersectionY0

		Local childXX:Int = 1
		Local childXY:Int
		Local childYX:Int
		Local childYY:Int = 1
		Local childTX:Int = x
		Local childTY:Int = y
		Local clipX0:Int
		Local clipY0:Int
		Local clipX1:Int
		Local clipY1:Int

		Select normalized
			Case DisplayOrientation0
				logicalWidth = width
				logicalHeight = height
				clipX0 = intersectionX0 - x
				clipY0 = intersectionY0 - y
				clipX1 = intersectionX1 - x
				clipY1 = intersectionY1 - y
			Case DisplayOrientation90
				logicalWidth = height
				logicalHeight = width
				childXX = 0
				childXY = -1
				childYX = 1
				childYY = 0
				childTX = x + width - 1
				clipX0 = intersectionY0 - y
				clipX1 = intersectionY1 - y
				clipY0 = x + width - intersectionX1
				clipY1 = x + width - intersectionX0
			Case DisplayOrientation180
				logicalWidth = width
				logicalHeight = height
				childXX = -1
				childYY = -1
				childTX = x + width - 1
				childTY = y + height - 1
				clipX0 = x + width - intersectionX1
				clipX1 = x + width - intersectionX0
				clipY0 = y + height - intersectionY1
				clipY1 = y + height - intersectionY0
			Case DisplayOrientation270
				logicalWidth = height
				logicalHeight = width
				childXX = 0
				childXY = 1
				childYX = -1
				childYY = 0
				childTX = x
				childTY = y + height - 1
				clipX0 = y + height - intersectionY1
				clipX1 = y + height - intersectionY0
				clipY0 = intersectionX0 - x
				clipY1 = intersectionX1 - x
		End Select

		Local parent:TEmbedded2DSavedState = savedStates[stateDepth - 1]
		transformXX = parent.xx * childXX + parent.xy * childYX
		transformXY = parent.xx * childXY + parent.xy * childYY
		transformYX = parent.yx * childXX + parent.yy * childYX
		transformYY = parent.yx * childXY + parent.yy * childYY
		transformTX = parent.xx * childTX + parent.xy * childTY + parent.tx
		transformTY = parent.yx * childTX + parent.yy * childTY + parent.ty
		viewClipX = clipX0
		viewClipY = clipY0
		viewClipWidth = clipX1 - clipX0
		viewClipHeight = clipY1 - clipY0
		originX = 0
		originY = 0
		viewDepth :+ 1
		ResetViewport()
		ApplyTransform()
		Return True
	End Method

	Rem
	bbdoc: Ends the innermost local view and restores its parent drawing state.
	returns: True on success, or False when the most recent saved state is not a view.
	End Rem
	Method EndView:Int()
		If stateDepth <= 0 Or Not savedStates[stateDepth - 1].viewBoundary Then Return False
		Return PopState()
	End Method

	Rem
	bbdoc: Returns the number of active nested drawing views.
	returns: The current view depth.
	End Rem
	Method ViewDepth:Int()
		Return viewDepth
	End Method

	Rem
	bbdoc: Converts a point in the current view to root logical screen coordinates.
	param: The x coordinate in the current view.
	param: The y coordinate in the current view.
	param: Receives the root logical screen x coordinate.
	param: Receives the root logical screen y coordinate.
	about: The current origin is applied, matching drawing operations. Screen
	coordinates follow the configured display orientation and are therefore the
	same pixel coordinate system obtained by scaling standard touch events.
	End Rem
	Method ViewToScreen(x:Int, y:Int, screenX:Int Var, screenY:Int Var)
		Local physicalX:Int = transformXX * (x + originX) + transformXY * (y + originY) + transformTX
		Local physicalY:Int = transformYX * (x + originX) + transformYY * (y + originY) + transformTY
		PhysicalToScreen(physicalX, physicalY, screenX, screenY)
	End Method

	Rem
	bbdoc: Converts a root logical screen point to coordinates in the current view.
	param: The root logical screen x coordinate.
	param: The root logical screen y coordinate.
	param: Receives the x coordinate in the current view.
	param: Receives the y coordinate in the current view.
	about: The current origin is removed, making the result directly usable with
	the drawing API. Points outside the view are still converted; use PointInView
	when bounds or viewport clipping matter.
	End Rem
	Method ScreenToView(screenX:Int, screenY:Int, x:Int Var, y:Int Var)
		Local physicalX:Int
		Local physicalY:Int
		ScreenToPhysical(screenX, screenY, physicalX, physicalY)
		Local deltaX:Int = physicalX - transformTX
		Local deltaY:Int = physicalY - transformTY
		x = transformXX * deltaX + transformYX * deltaY - originX
		y = transformXY * deltaX + transformYY * deltaY - originY
	End Method

	Rem
	bbdoc: Tests whether a root logical screen point is inside the current viewport.
	param: The root logical screen x coordinate.
	param: The root logical screen y coordinate.
	returns: True when the transformed point lies inside the active viewport.
	about: This uses the same origin, nested-view transform, and clipping as drawing.
	End Rem
	Method PointInView:Int(screenX:Int, screenY:Int)
		Local x:Int
		Local y:Int
		ScreenToView(screenX, screenY, x, y)
		Return PointVisible(x + originX, y + originY)
	End Method

	Rem
	bbdoc: Draws text using the current bitmap font and color.
	param: The UTF-8 text to draw; newline characters begin new lines.
	param: The left coordinate of the first line.
	param: The top coordinate of the first line.
	param: The positive integer pixel scale.
	returns: The logical x coordinate immediately following the final glyph.
	End Rem
	Method DrawText:Int(text:String, x:Int, y:Int, scale:Int = 1)
		If Not target Or Not currentFont Then Return x
		If scale > 0 And text.length Then
			MarkDirtyLogical(x + originX, y + originY, currentFont.TextWidth(text, scale), ..
				TextLineCount(text) * currentFont.LineHeight() * scale)
		End If
		Return currentFont.DrawTextClipped(DrawingTarget(), text, x + originX, y + originY, ..
			drawColor, scale, viewportX, viewportY, viewportWidth, viewportHeight) - originX
	End Method

	Rem
	bbdoc: Measures the widest line of text using the current bitmap font.
	param: The UTF-8 text to measure.
	param: The positive integer pixel scale.
	returns: The width in logical pixels, or zero when no font is selected.
	End Rem
	Method TextWidth:Int(text:String, scale:Int = 1)
		If Not currentFont Then Return 0
		Return currentFont.TextWidth(text, scale)
	End Method

	Rem
	bbdoc: Returns the scaled line height of the current bitmap font.
	param: The positive integer pixel scale.
	returns: The line height in pixels, or zero for no font or an invalid scale.
	End Rem
	Method FontHeight:Int(scale:Int = 1)
		If Not currentFont Or scale <= 0 Then Return 0
		Return currentFont.LineHeight() * scale
	End Method

	Rem
	bbdoc: Measures text wrapped to a fixed width.
	param: The UTF-8 text to measure.
	param: The maximum line width in pixels.
	param: Receives the widest resulting line.
	param: Receives the total height of the resulting lines.
	param: The positive integer pixel scale.
	returns: The number of resulting lines.
	End Rem
	Method TextBoxSize:Int(text:String, width:Int, measuredWidth:Int Var, ..
			measuredHeight:Int Var, scale:Int = 1)
		If Not currentFont Then
			measuredWidth = 0
			measuredHeight = 0
			Return 0
		End If
		Return currentFont.TextBoxSize(text, width, measuredWidth, measuredHeight, scale)
	End Method

	Rem
	bbdoc: Draws aligned, word-wrapped text inside a fixed rectangle.
	param: The UTF-8 text to draw.
	param: The text-box left coordinate.
	param: The text-box top coordinate.
	param: The text-box width in pixels.
	param: The text-box height in pixels.
	param: A TextAlign value applied independently to each line.
	param: The positive integer pixel scale.
	param: True to add an ellipsis when text exceeds the available lines.
	about: The rectangle and result use the current local view. When ellipsis is
	true, overflowing text is shortened on the final visible line and ends in
	three dots. Drawing does not allocate temporary strings.
	returns: The number of lines drawn.
	End Rem
	Method DrawTextBox:Int(text:String, x:Int, y:Int, width:Int, height:Int, ..
			alignment:Int = TextAlignLeft, scale:Int = 1, ellipsis:Int = True)
		If Not target Or Not currentFont Then Return 0
		If alignment < TextAlignLeft Or alignment > TextAlignRight Then alignment = TextAlignLeft
		If scale > 0 And text.length Then MarkDirtyLogical(x + originX, y + originY, width, height)
		Return currentFont.DrawTextBoxClipped(DrawingTarget(), text, x + originX, y + originY, ..
			width, height, drawColor, alignment, scale, ellipsis, ..
			viewportX, viewportY, viewportWidth, viewportHeight)
	End Method

	Rem
	bbdoc: Draws an image with optional flipping, opacity, and source colour-key transparency.
	param: The firmware-resident image to draw.
	param: The destination left coordinate.
	param: The destination top coordinate.
	param: A bitwise combination of ImageFlip constants.
	param: Source opacity from 0 through 255.
	param: An $RRGGBB transparent source color, or ImageColorKeyDisabled.
	about: Opacity is clamped to 0..255. The colour key is matched against the
	original source pixel before tinting; omit it to use only the image's mask.
	End Rem
	Method DrawImage(image:TEmbeddedImage, x:Int, y:Int, drawFlags:Int = 0, ..
			opacity:Int = 255, colorKey:UInt = ImageColorKeyDisabled)
		If Not target Or Not image Or opacity <= 0 Then Return
		MarkDirtyLogical(x + originX, y + originY, image.Width(), image.Height())
		image.DrawRegionClipped(DrawingTarget(), x + originX, y + originY, 0, 0, ..
			image.Width(), image.Height(), drawColor, ..
			viewportX, viewportY, viewportWidth, viewportHeight, drawFlags, opacity, colorKey)
	End Method

	Rem
	bbdoc: Draws an image scaled to the supplied destination rectangle.
	param: The firmware-resident image to draw.
	param: The destination left coordinate.
	param: The destination top coordinate.
	param: The destination width in pixels.
	param: The destination height in pixels.
	param: A bitwise combination of ImageFlip constants.
	param: Source opacity from 0 through 255.
	param: An $RRGGBB transparent source color, or ImageColorKeyDisabled.
	about: Scaling uses nearest-neighbour sampling.
	End Rem
	Method DrawImageRect(image:TEmbeddedImage, x:Int, y:Int, width:Int, height:Int, ..
			drawFlags:Int = 0, opacity:Int = 255, colorKey:UInt = ImageColorKeyDisabled)
		If Not target Or Not image Or opacity <= 0 Then Return
		MarkDirtyLogical(x + originX, y + originY, width, height)
		image.DrawRectClipped(DrawingTarget(), x + originX, y + originY, width, height, drawColor, ..
			viewportX, viewportY, viewportWidth, viewportHeight, drawFlags, opacity, colorKey)
	End Method

	Rem
	bbdoc: Draws an unscaled rectangular region of an image.
	param: The firmware-resident image to draw.
	param: The destination left coordinate.
	param: The destination top coordinate.
	param: The source-region left coordinate.
	param: The source-region top coordinate.
	param: The region width in pixels.
	param: The region height in pixels.
	param: A bitwise combination of ImageFlip constants.
	param: Source opacity from 0 through 255.
	param: An $RRGGBB transparent source color, or ImageColorKeyDisabled.
	End Rem
	Method DrawImageRegion(image:TEmbeddedImage, x:Int, y:Int, sourceX:Int, sourceY:Int, ..
			width:Int, height:Int, drawFlags:Int = 0, opacity:Int = 255, ..
			colorKey:UInt = ImageColorKeyDisabled)
		If Not target Or Not image Or opacity <= 0 Then Return
		MarkDirtyLogical(x + originX, y + originY, width, height)
		image.DrawRegionClipped(DrawingTarget(), x + originX, y + originY, ..
			sourceX, sourceY, width, height, drawColor, ..
			viewportX, viewportY, viewportWidth, viewportHeight, drawFlags, opacity, colorKey)
	End Method

	Rem
	bbdoc: Presents the complete render target through a display.
	param: The destination display, or Null to use the bound display.
	returns: A positive value on success, or a DisplayError value on failure.
	about: Successful presentation clears accumulated dirty regions.
	End Rem
	Method Present:Int(display:TDisplay = Null)
		If Not target Then Return DisplayErrorInvalidArgument
		If Not display Then display = boundDisplay
		If Not display Then Return DisplayErrorInvalidArgument
		Local result:Int = display.Present(target)
		If result > 0 Then ResetDirty()
		Return result
	End Method

	Rem
	bbdoc: Presents a complete frame and permits its render-buffer contents to be discarded.
	param: The destination display, or Null to use the bound display.
	returns: A positive value on success, or a DisplayError value on failure.
	about: The application must redraw every pixel before its next presentation.
	Drivers without an optimized discard path safely use ordinary presentation.
	End Rem
	Method PresentDiscard:Int(display:TDisplay = Null)
		If Not target Then Return DisplayErrorInvalidArgument
		If Not display Then display = boundDisplay
		If Not display Then Return DisplayErrorInvalidArgument
		Local result:Int = display.PresentDiscard(target)
		If result > 0 Then ResetDirty()
		Return result
	End Method

	Rem
	bbdoc: Presents the accumulated physical dirty rectangles as one frame.
	param: The destination display, or Null to use the bound display.
	returns: A positive value on success, or a DisplayError value on failure.
	about: When tracking is disabled this falls back to a complete presentation.
	An empty enabled tracker succeeds without calling the display driver. A
	successful transfer clears the regions; failures retain them for retry.
	End Rem
	Method PresentDirty:Int(display:TDisplay = Null)
		If Not target Then Return DisplayErrorInvalidArgument
		If Not display Then display = boundDisplay
		If Not display Then Return DisplayErrorInvalidArgument
		If Not dirtyTracking Then Return Present(display)
		If Not dirtyValid Then Return True
		Local widths:Int[EmbeddedGraphicsDirtyMaximum]
		Local heights:Int[EmbeddedGraphicsDirtyMaximum]
		For Local index:Int = 0 Until dirtyCount
			widths[index] = dirtyRegionX1[index] - dirtyRegionX0[index]
			heights[index] = dirtyRegionY1[index] - dirtyRegionY0[index]
		Next
		Local result:Int = display.PresentRegions(target, Varptr dirtyRegionX0[0], ..
			Varptr dirtyRegionY0[0], Varptr widths[0], Varptr heights[0], dirtyCount)
		If result > 0 Then ResetDirty()
		Return result
	End Method

	Private
	Method PlotLogicalUntracked(raster:TDisplayBuffer, x:Int, y:Int)
		If PointVisible(x, y) Then raster.SetPixel(x, y, drawColor)
	End Method

	Method FillLogicalSpanUntracked(raster:TDisplayBuffer, x0:Int, x1:Int, y:Int)
		If y < viewportY Or y >= viewportY + viewportHeight Then Return
		If x0 < viewportX Then x0 = viewportX
		Local viewportX1:Int = viewportX + viewportWidth - 1
		If x1 > viewportX1 Then x1 = viewportX1
		If x0 <= x1 Then raster.FillRect(x0, y, x1 - x0 + 1, 1, drawColor)
	End Method

	Method TextLineCount:Int(text:String)
		If Not text.length Then Return 0
		Local lines:Int = 1
		For Local index:Int = 0 Until text.length
			If text[index] = 10 Then lines :+ 1
		Next
		Return lines
	End Method

	Method MarkDirtyLogical(x:Int, y:Int, width:Int, height:Int)
		If Not dirtyTracking Or Not target Or width <= 0 Or height <= 0 Or ..
				viewportWidth <= 0 Or viewportHeight <= 0 Then Return
		Local x1:Int = x + width
		Local y1:Int = y + height
		Local viewportX1:Int = viewportX + viewportWidth
		Local viewportY1:Int = viewportY + viewportHeight
		If x < viewportX Then x = viewportX
		If y < viewportY Then y = viewportY
		If x1 > viewportX1 Then x1 = viewportX1
		If y1 > viewportY1 Then y1 = viewportY1
		If x >= x1 Or y >= y1 Then Return

		Local px0:Int = transformXX * x + transformXY * y + transformTX
		Local py0:Int = transformYX * x + transformYY * y + transformTY
		Local px1:Int = transformXX * (x1 - 1) + transformXY * y + transformTX
		Local py1:Int = transformYX * (x1 - 1) + transformYY * y + transformTY
		Local px2:Int = transformXX * x + transformXY * (y1 - 1) + transformTX
		Local py2:Int = transformYX * x + transformYY * (y1 - 1) + transformTY
		Local px3:Int = transformXX * (x1 - 1) + transformXY * (y1 - 1) + transformTX
		Local py3:Int = transformYX * (x1 - 1) + transformYY * (y1 - 1) + transformTY
		Local minimumX:Int = px0
		Local maximumX:Int = px0
		Local minimumY:Int = py0
		Local maximumY:Int = py0
		If px1 < minimumX Then minimumX = px1
		If px2 < minimumX Then minimumX = px2
		If px3 < minimumX Then minimumX = px3
		If px1 > maximumX Then maximumX = px1
		If px2 > maximumX Then maximumX = px2
		If px3 > maximumX Then maximumX = px3
		If py1 < minimumY Then minimumY = py1
		If py2 < minimumY Then minimumY = py2
		If py3 < minimumY Then minimumY = py3
		If py1 > maximumY Then maximumY = py1
		If py2 > maximumY Then maximumY = py2
		If py3 > maximumY Then maximumY = py3
		IncludeDirtyPhysical(minimumX, minimumY, maximumX + 1, maximumY + 1)
	End Method

	Method IncludeDirtyPhysical(x0:Int, y0:Int, x1:Int, y1:Int)
		If x0 < 0 Then x0 = 0
		If y0 < 0 Then y0 = 0
		If x1 > target.Width() Then x1 = target.Width()
		If y1 > target.Height() Then y1 = target.Height()
		If x0 >= x1 Or y0 >= y1 Then Return
		If Not dirtyValid Then
			dirtyX0 = x0
			dirtyY0 = y0
			dirtyX1 = x1
			dirtyY1 = y1
			dirtyValid = True
		Else
			If x0 < dirtyX0 Then dirtyX0 = x0
			If y0 < dirtyY0 Then dirtyY0 = y0
			If x1 > dirtyX1 Then dirtyX1 = x1
			If y1 > dirtyY1 Then dirtyY1 = y1
		End If

		' Keep overlapping and edge-adjacent changes together, but retain distant
		' rectangles independently. Removing a merged entry and restarting makes
		' transitive joins deterministic without allocating or sorting.
		Local index:Int
		While index < dirtyCount
			If x0 <= dirtyRegionX1[index] And x1 >= dirtyRegionX0[index] And ..
					y0 <= dirtyRegionY1[index] And y1 >= dirtyRegionY0[index] Then
				If dirtyRegionX0[index] < x0 Then x0 = dirtyRegionX0[index]
				If dirtyRegionY0[index] < y0 Then y0 = dirtyRegionY0[index]
				If dirtyRegionX1[index] > x1 Then x1 = dirtyRegionX1[index]
				If dirtyRegionY1[index] > y1 Then y1 = dirtyRegionY1[index]
				RemoveDirtyRegion(index)
				index = 0
			Else
				index :+ 1
			End If
		Wend

		If dirtyCount >= EmbeddedGraphicsDirtyMaximum Then
			SetDirtyFull()
			Return
		End If
		dirtyRegionX0[dirtyCount] = x0
		dirtyRegionY0[dirtyCount] = y0
		dirtyRegionX1[dirtyCount] = x1
		dirtyRegionY1[dirtyCount] = y1
		dirtyCount :+ 1

		Local dirtyArea:Long
		For index = 0 Until dirtyCount
			dirtyArea :+ Long(dirtyRegionX1[index] - dirtyRegionX0[index]) * ..
				Long(dirtyRegionY1[index] - dirtyRegionY0[index])
		Next
		Local frameArea:Long = Long(target.Width()) * Long(target.Height())
		If dirtyArea * 100 >= frameArea * 60 Then SetDirtyFull()
	End Method

	Method RemoveDirtyRegion(index:Int)
		dirtyCount :- 1
		For Local move:Int = index Until dirtyCount
			dirtyRegionX0[move] = dirtyRegionX0[move + 1]
			dirtyRegionY0[move] = dirtyRegionY0[move + 1]
			dirtyRegionX1[move] = dirtyRegionX1[move + 1]
			dirtyRegionY1[move] = dirtyRegionY1[move + 1]
		Next
	End Method

	Method SetDirtyFull()
		dirtyCount = 1
		dirtyRegionX0[0] = 0
		dirtyRegionY0[0] = 0
		dirtyRegionX1[0] = target.Width()
		dirtyRegionY1[0] = target.Height()
		dirtyX0 = 0
		dirtyY0 = 0
		dirtyX1 = target.Width()
		dirtyY1 = target.Height()
		dirtyValid = True
	End Method

	Method DrawingTarget:TDisplayBuffer()
		If drawingTarget And (transformXX <> 1 Or transformXY Or transformYX Or transformYY <> 1 Or ..
				transformTX Or transformTY Or logicalWidth <> target.Width() Or logicalHeight <> target.Height()) Then
			Return drawingTarget
		End If
		Return target
	End Method

	Method ApplyTransform()
		If drawingTarget Then drawingTarget.SetTransform(logicalWidth, logicalHeight, ..
			transformXX, transformXY, transformYX, transformYY, transformTX, transformTY)
	End Method

	Method ScreenToPhysical(screenX:Int, screenY:Int, physicalX:Int Var, physicalY:Int Var)
		If Not target Then
			physicalX = screenX
			physicalY = screenY
			Return
		End If
		Select Orientation()
			Case DisplayOrientation90
				physicalX = target.Width() - 1 - screenY
				physicalY = screenX
			Case DisplayOrientation180
				physicalX = target.Width() - 1 - screenX
				physicalY = target.Height() - 1 - screenY
			Case DisplayOrientation270
				physicalX = screenY
				physicalY = target.Height() - 1 - screenX
			Default
				physicalX = screenX
				physicalY = screenY
		End Select
	End Method

	Method PhysicalToScreen(physicalX:Int, physicalY:Int, screenX:Int Var, screenY:Int Var)
		If Not target Then
			screenX = physicalX
			screenY = physicalY
			Return
		End If
		Select Orientation()
			Case DisplayOrientation90
				screenX = physicalY
				screenY = target.Width() - 1 - physicalX
			Case DisplayOrientation180
				screenX = target.Width() - 1 - physicalX
				screenY = target.Height() - 1 - physicalY
			Case DisplayOrientation270
				screenX = target.Height() - 1 - physicalY
				screenY = physicalX
			Default
				screenX = physicalX
				screenY = physicalY
		End Select
	End Method

	Method ResetRootTransform()
		transformXX = 1
		transformXY = 0
		transformYX = 0
		transformYY = 1
		transformTX = 0
		transformTY = 0
		logicalWidth = 0
		logicalHeight = 0
		If target Then
			Local physicalWidth:Int = target.Width()
			Local physicalHeight:Int = target.Height()
			Select EffectiveRotation()
				Case DisplayOrientation0
					logicalWidth = physicalWidth
					logicalHeight = physicalHeight
				Case DisplayOrientation90
					logicalWidth = physicalHeight
					logicalHeight = physicalWidth
					transformXX = 0
					transformXY = -1
					transformYX = 1
					transformYY = 0
					transformTX = physicalWidth - 1
				Case DisplayOrientation180
					logicalWidth = physicalWidth
					logicalHeight = physicalHeight
					transformXX = -1
					transformYY = -1
					transformTX = physicalWidth - 1
					transformTY = physicalHeight - 1
				Case DisplayOrientation270
					logicalWidth = physicalHeight
					logicalHeight = physicalWidth
					transformXX = 0
					transformXY = 1
					transformYX = -1
					transformYY = 0
					transformTY = physicalHeight - 1
			End Select
		End If
		viewClipX = 0
		viewClipY = 0
		viewClipWidth = logicalWidth
		viewClipHeight = logicalHeight
		ApplyTransform()
		ResetViewport()
	End Method

	Method PushStateInternal:Int(viewBoundary:Int)
		If stateDepth >= EmbeddedGraphicsStateMaximum Then Return False
		Local state:TEmbedded2DSavedState = savedStates[stateDepth]
		state.font = currentFont
		state.drawColor = drawColor
		state.clearColor = clearColor
		state.originX = originX
		state.originY = originY
		state.viewportX = viewportX
		state.viewportY = viewportY
		state.viewportWidth = viewportWidth
		state.viewportHeight = viewportHeight
		state.viewClipX = viewClipX
		state.viewClipY = viewClipY
		state.viewClipWidth = viewClipWidth
		state.viewClipHeight = viewClipHeight
		state.logicalWidth = logicalWidth
		state.logicalHeight = logicalHeight
		state.xx = transformXX
		state.xy = transformXY
		state.yx = transformYX
		state.yy = transformYY
		state.tx = transformTX
		state.ty = transformTY
		state.rotation = rotation
		state.viewDepth = viewDepth
		state.viewBoundary = viewBoundary
		stateDepth :+ 1
		Return True
	End Method

	Method RestoreState(state:TEmbedded2DSavedState)
		currentFont = state.font
		drawColor = state.drawColor
		clearColor = state.clearColor
		originX = state.originX
		originY = state.originY
		viewportX = state.viewportX
		viewportY = state.viewportY
		viewportWidth = state.viewportWidth
		viewportHeight = state.viewportHeight
		viewClipX = state.viewClipX
		viewClipY = state.viewClipY
		viewClipWidth = state.viewClipWidth
		viewClipHeight = state.viewClipHeight
		logicalWidth = state.logicalWidth
		logicalHeight = state.logicalHeight
		transformXX = state.xx
		transformXY = state.xy
		transformYX = state.yx
		transformYY = state.yy
		transformTX = state.tx
		transformTY = state.ty
		rotation = state.rotation
		viewDepth = state.viewDepth
		ApplyTransform()
	End Method

	Method PointVisible:Int(x:Int, y:Int)
		Return viewportWidth > 0 And viewportHeight > 0 And x >= viewportX And y >= viewportY And ..
			x < viewportX + viewportWidth And y < viewportY + viewportHeight
	End Method

	Method OutCode:Int(x:Int, y:Int)
		Local code:Int
		If x < viewportX Then
			code :| 1
		Else If x >= viewportX + viewportWidth Then
			code :| 2
		End If
		If y < viewportY Then
			code :| 4
		Else If y >= viewportY + viewportHeight Then
			code :| 8
		End If
		Return code
	End Method

	Method ClipLine:Int(x0:Int Var, y0:Int Var, x1:Int Var, y1:Int Var)
		Local minimumX:Int = viewportX
		Local minimumY:Int = viewportY
		Local maximumX:Int = viewportX + viewportWidth - 1
		Local maximumY:Int = viewportY + viewportHeight - 1
		While True
			Local code0:Int = OutCode(x0, y0)
			Local code1:Int = OutCode(x1, y1)
			If Not (code0 | code1) Then Return True
			If code0 & code1 Then Return False
			Local outside:Int = code0
			If Not outside Then outside = code1
			Local x:Int
			Local y:Int
			If outside & 4 Then
				If y1 = y0 Then Return False
				x = x0 + (x1 - x0) * (minimumY - y0) / (y1 - y0)
				y = minimumY
			Else If outside & 8 Then
				If y1 = y0 Then Return False
				x = x0 + (x1 - x0) * (maximumY - y0) / (y1 - y0)
				y = maximumY
			Else If outside & 2 Then
				If x1 = x0 Then Return False
				y = y0 + (y1 - y0) * (maximumX - x0) / (x1 - x0)
				x = maximumX
			Else
				If x1 = x0 Then Return False
				y = y0 + (y1 - y0) * (minimumX - x0) / (x1 - x0)
				x = minimumX
			End If
			If outside = code0 Then
				x0 = x
				y0 = y
			Else
				x1 = x
				y1 = y
			End If
		Wend
	End Method
End Type

Private
Global defaultContext:TEmbedded2DContext

Function Default2DContext:TEmbedded2DContext()
	If Not defaultContext Then defaultContext = New TEmbedded2DContext
	Return defaultContext
End Function

Public

Rem
bbdoc: Binds the default drawing context to a raster and optional display.
param: The raster buffer that receives drawing operations, or Null to unbind it.
param: The display used for orientation and presentation, or Null for buffer-only drawing.
End Rem
Function SetRenderTarget(target:TDisplayBuffer, display:TDisplay = Null)
	Default2DContext().SetRenderTarget(target, display)
End Function

Rem
bbdoc: Returns the raster bound to the default drawing context.
returns: The current render target, or Null when unbound.
End Rem
Function RenderTarget:TDisplayBuffer()
	Return Default2DContext().RenderTarget()
End Function

Rem
bbdoc: Associates a display with the default drawing context.
param: The new display, or Null for buffer-only drawing.
End Rem
Function SetDisplay(display:TDisplay)
	Default2DContext().SetDisplay(display)
End Function

Rem
bbdoc: Sets the default context's clockwise drawing rotation.
param: A quarter-turn angle in degrees.
returns: True when the requested angle is supported.
End Rem
Function SetRotation:Int(degrees:Int)
	Return Default2DContext().SetRotation(degrees)
End Function

Rem
bbdoc: Returns the default context's relative drawing rotation.
returns: One of the GraphicsRotation constants.
End Rem
Function Rotation:Int()
	Return Default2DContext().Rotation()
End Function

Rem
bbdoc: Returns the orientation configured on the bound display.
returns: One of the DisplayOrientation constants.
End Rem
Function DisplayOrientation:Int()
	Return Default2DContext().Orientation()
End Function

Rem
bbdoc: Changes the orientation configured on the bound display.
param: A clockwise quarter-turn angle in degrees.
returns: True when the display accepts the orientation.
End Rem
Function SetDisplayOrientation:Int(degrees:Int)
	Return Default2DContext().SetDisplayOrientation(degrees)
End Function

Rem
bbdoc: Returns the physical rotation produced by display orientation plus drawing rotation.
returns: One of the DisplayOrientation constants.
End Rem
Function EffectiveRotation:Int()
	Return Default2DContext().EffectiveRotation()
End Function

Rem
bbdoc: Returns the logical width of the current default-context view.
returns: The width in pixels.
End Rem
Function GraphicsWidth:Int()
	Return Default2DContext().Width()
End Function

Rem
bbdoc: Returns the logical height of the current default-context view.
returns: The height in pixels.
End Rem
Function GraphicsHeight:Int()
	Return Default2DContext().Height()
End Function

Rem
bbdoc: Returns the orientation-aware root screen width.
returns: The width in pixels before relative drawing rotation.
End Rem
Function GraphicsScreenWidth:Int()
	Return Default2DContext().ScreenWidth()
End Function

Rem
bbdoc: Returns the orientation-aware root screen height.
returns: The height in pixels before relative drawing rotation.
End Rem
Function GraphicsScreenHeight:Int()
	Return Default2DContext().ScreenHeight()
End Function

Rem
bbdoc: Selects the bitmap font used by default-context text operations.
param: The font to use, or Null to disable text drawing.
End Rem
Function SetFont(font:TBitmapFont)
	Default2DContext().SetFont(font)
End Function

Rem
bbdoc: Sets the default drawing color from clamped RGB components.
param: The red component from 0 through 255.
param: The green component from 0 through 255.
param: The blue component from 0 through 255.
End Rem
Function SetColor(red:Int, green:Int, blue:Int)
	Default2DContext().SetColor(red, green, blue)
End Function

Rem
bbdoc: Sets the default drawing color from an $RRGGBB value.
param: The drawing color.
End Rem
Function SetColorValue(color:UInt)
	Default2DContext().SetColorValue(color)
End Function

Rem
bbdoc: Sets the default clear color from clamped RGB components.
param: The red component from 0 through 255.
param: The green component from 0 through 255.
param: The blue component from 0 through 255.
End Rem
Function SetClsColor(red:Int, green:Int, blue:Int)
	Default2DContext().SetClsColor(red, green, blue)
End Function

Rem
bbdoc: Sets the default clear color from an $RRGGBB value.
param: The clear color.
End Rem
Function SetClsColorValue(color:UInt)
	Default2DContext().SetClsColorValue(color)
End Function

Rem
bbdoc: Sets the coordinate origin used by default-context drawing operations.
param: The horizontal logical offset.
param: The vertical logical offset.
End Rem
Function SetOrigin(x:Int, y:Int)
	Default2DContext().SetOrigin(x, y)
End Function

Rem
bbdoc: Saves the default context's complete drawing state.
returns: True on success, or False when the state stack is full.
End Rem
Function PushGraphicsState:Int()
	Return Default2DContext().PushState()
End Function

Rem
bbdoc: Restores the most recently saved default-context drawing state.
returns: True on success, or False when the state stack is empty.
End Rem
Function PopGraphicsState:Int()
	Return Default2DContext().PopState()
End Function

Rem
bbdoc: Returns the number of states saved by the default context.
returns: The current state-stack depth.
End Rem
Function GraphicsStateDepth:Int()
	Return Default2DContext().StateDepth()
End Function

Rem
bbdoc: Begins a clipped local view in the default drawing context.
param: The view's left edge in its parent coordinate system.
param: The view's top edge in its parent coordinate system.
param: The physical width occupied in the parent view.
param: The physical height occupied in the parent view.
param: The clockwise rotation applied inside the view.
returns: True on success, or False when the arguments or state-stack capacity are invalid.
End Rem
Function BeginView:Int(x:Int, y:Int, width:Int, height:Int, rotation:Int = 0)
	Return Default2DContext().BeginView(x, y, width, height, rotation)
End Function

Rem
bbdoc: Ends the innermost default-context view and restores its parent state.
returns: True on success, or False when no view is active.
End Rem
Function EndView:Int()
	Return Default2DContext().EndView()
End Function

Rem
bbdoc: Returns the number of active default-context views.
returns: The current nested view depth.
End Rem
Function GraphicsViewDepth:Int()
	Return Default2DContext().ViewDepth()
End Function

Rem
bbdoc: Converts a default-context view point to root logical screen coordinates.
param: The x coordinate in the current view.
param: The y coordinate in the current view.
param: Receives the root logical screen x coordinate.
param: Receives the root logical screen y coordinate.
End Rem
Function ViewToScreen(x:Int, y:Int, screenX:Int Var, screenY:Int Var)
	Default2DContext().ViewToScreen(x, y, screenX, screenY)
End Function

Rem
bbdoc: Converts a root logical screen point to default-context view coordinates.
param: The root logical screen x coordinate.
param: The root logical screen y coordinate.
param: Receives the x coordinate in the current view.
param: Receives the y coordinate in the current view.
End Rem
Function ScreenToView(screenX:Int, screenY:Int, x:Int Var, y:Int Var)
	Default2DContext().ScreenToView(screenX, screenY, x, y)
End Function

Rem
bbdoc: Tests whether a root logical screen point lies inside the current viewport.
param: The root logical screen x coordinate.
param: The root logical screen y coordinate.
returns: True when the transformed point is visible.
End Rem
Function PointInView:Int(screenX:Int, screenY:Int)
	Return Default2DContext().PointInView(screenX, screenY)
End Function

Rem
bbdoc: Restricts default-context drawing to a rectangle in the current view.
param: The logical left edge.
param: The logical top edge.
param: The viewport width in pixels.
param: The viewport height in pixels.
End Rem
Function SetViewport(x:Int, y:Int, width:Int, height:Int)
	Default2DContext().SetViewport(x, y, width, height)
End Function

Rem
bbdoc: Restores the default-context viewport to the complete current view.
End Rem
Function ResetViewport()
	Default2DContext().ResetViewport()
End Function

Rem
bbdoc: Enables or disables automatic dirty-region tracking in the default context.
param: True to record drawing bounds, or False to disable tracking.
End Rem
Function SetDirtyTracking(enabled:Int = True)
	Default2DContext().SetDirtyTracking(enabled)
End Function

Rem
bbdoc: Reports whether default-context dirty tracking is enabled.
returns: True when drawing operations accumulate dirty rectangles.
End Rem
Function DirtyTracking:Int()
	Return Default2DContext().DirtyTracking()
End Function

Rem
bbdoc: Clears the default context's accumulated dirty regions.
End Rem
Function ResetDirty()
	Default2DContext().ResetDirty()
End Function

Rem
bbdoc: Returns the bounding rectangle of all default-context dirty regions.
param: Receives the physical left edge.
param: Receives the physical top edge.
param: Receives the physical width.
param: Receives the physical height.
returns: False when no drawing has been recorded.
End Rem
Function DirtyRect:Int(x:Int Var, y:Int Var, width:Int Var, height:Int Var)
	Return Default2DContext().DirtyRect(x, y, width, height)
End Function

Rem
bbdoc: Returns the number of independently tracked default-context dirty rectangles.
returns: A value from zero through EmbeddedGraphicsDirtyMaximum.
End Rem
Function DirtyRegionCount:Int()
	Return Default2DContext().DirtyRegionCount()
End Function

Rem
bbdoc: Returns one default-context dirty rectangle.
param: The zero-based dirty-region index.
param: Receives the physical left edge.
param: Receives the physical top edge.
param: Receives the physical width.
param: Receives the physical height.
returns: False when the index is outside the current dirty-region list.
End Rem
Function DirtyRegion:Int(index:Int, x:Int Var, y:Int Var, width:Int Var, height:Int Var)
	Return Default2DContext().DirtyRegion(index, x, y, width, height)
End Function

Rem
bbdoc: Adds a current-view rectangle to the default context's dirty regions.
param: The left edge relative to the current origin.
param: The top edge relative to the current origin.
param: The rectangle width in pixels.
param: The rectangle height in pixels.
End Rem
Function InvalidateRect(x:Int, y:Int, width:Int, height:Int)
	Default2DContext().InvalidateRect(x, y, width, height)
End Function

Rem
bbdoc: Marks the complete current default-context view dirty.
End Rem
Function InvalidateAll()
	Default2DContext().InvalidateAll()
End Function

Rem
bbdoc: Fills the default-context viewport with its clear color.
End Rem
Function Cls()
	Default2DContext().Cls()
End Function

Rem
bbdoc: Draws one pixel using the current color.
param: The x coordinate relative to the current origin.
param: The y coordinate relative to the current origin.
End Rem
Function Plot(x:Int, y:Int)
	Default2DContext().Plot(x, y)
End Function

Rem
bbdoc: Draws a clipped one-pixel line including both endpoints.
param: The starting x coordinate.
param: The starting y coordinate.
param: The ending x coordinate.
param: The ending y coordinate.
End Rem
Function DrawLine(x0:Int, y0:Int, x1:Int, y1:Int)
	Default2DContext().DrawLine(x0, y0, x1, y1)
End Function

Rem
bbdoc: Draws the one-pixel outline of a rectangle.
param: The left coordinate.
param: The top coordinate.
param: The rectangle width in pixels.
param: The rectangle height in pixels.
End Rem
Function DrawRect(x:Int, y:Int, width:Int, height:Int)
	Default2DContext().DrawRect(x, y, width, height)
End Function

Rem
bbdoc: Draws a circle using the current color.
param: The centre x coordinate.
param: The centre y coordinate.
param: The radius in pixels.
End Rem
Function DrawCircle(centerX:Int, centerY:Int, radius:Int)
	Default2DContext().DrawCircle(centerX, centerY, radius)
End Function

Rem
bbdoc: Draws a filled circle using the current color.
param: The centre x coordinate.
param: The centre y coordinate.
param: The radius in pixels.
End Rem
Function FillCircle(centerX:Int, centerY:Int, radius:Int)
	Default2DContext().FillCircle(centerX, centerY, radius)
End Function

Rem
bbdoc: Draws an ellipse from its centre and radii.
param: The centre x coordinate.
param: The centre y coordinate.
param: The horizontal radius in pixels.
param: The vertical radius in pixels.
End Rem
Function DrawEllipse(centerX:Int, centerY:Int, radiusX:Int, radiusY:Int)
	Default2DContext().DrawEllipse(centerX, centerY, radiusX, radiusY)
End Function

Rem
bbdoc: Draws a filled ellipse from its centre and radii.
param: The centre x coordinate.
param: The centre y coordinate.
param: The horizontal radius in pixels.
param: The vertical radius in pixels.
End Rem
Function FillEllipse(centerX:Int, centerY:Int, radiusX:Int, radiusY:Int)
	Default2DContext().FillEllipse(centerX, centerY, radiusX, radiusY)
End Function

Rem
bbdoc: Draws the three one-pixel edges of a triangle.
param: The first vertex x coordinate.
param: The first vertex y coordinate.
param: The second vertex x coordinate.
param: The second vertex y coordinate.
param: The third vertex x coordinate.
param: The third vertex y coordinate.
End Rem
Function DrawTriangle(x0:Int, y0:Int, x1:Int, y1:Int, x2:Int, y2:Int)
	Default2DContext().DrawTriangle(x0, y0, x1, y1, x2, y2)
End Function

Rem
bbdoc: Draws a filled triangle using the current color.
param: The first vertex x coordinate.
param: The first vertex y coordinate.
param: The second vertex x coordinate.
param: The second vertex y coordinate.
param: The third vertex x coordinate.
param: The third vertex y coordinate.
End Rem
Function FillTriangle(x0:Int, y0:Int, x1:Int, y1:Int, x2:Int, y2:Int)
	Default2DContext().FillTriangle(x0, y0, x1, y1, x2, y2)
End Function

Rem
bbdoc: Draws the one-pixel outline of a rounded rectangle.
param: The left coordinate.
param: The top coordinate.
param: The rectangle width in pixels.
param: The rectangle height in pixels.
param: The corner radius in pixels.
End Rem
Function DrawRoundRect(x:Int, y:Int, width:Int, height:Int, radius:Int)
	Default2DContext().DrawRoundRect(x, y, width, height, radius)
End Function

Rem
bbdoc: Draws a filled rounded rectangle.
param: The left coordinate.
param: The top coordinate.
param: The rectangle width in pixels.
param: The rectangle height in pixels.
param: The corner radius in pixels.
End Rem
Function FillRoundRect(x:Int, y:Int, width:Int, height:Int, radius:Int)
	Default2DContext().FillRoundRect(x, y, width, height, radius)
End Function

Rem
bbdoc: Fills a clipped rectangle using the current color.
param: The left coordinate.
param: The top coordinate.
param: The rectangle width in pixels.
param: The rectangle height in pixels.
End Rem
Function FillRect(x:Int, y:Int, width:Int, height:Int)
	Default2DContext().FillRect(x, y, width, height)
End Function

Rem
bbdoc: Draws text using the default context's bitmap font and color.
param: The UTF-8 text to draw.
param: The left coordinate of the first line.
param: The top coordinate of the first line.
param: The positive integer pixel scale.
returns: The logical x coordinate immediately following the final glyph.
End Rem
Function DrawText:Int(text:String, x:Int, y:Int, scale:Int = 1)
	Return Default2DContext().DrawText(text, x, y, scale)
End Function

Rem
bbdoc: Measures the widest line using the default context's bitmap font.
param: The UTF-8 text to measure.
param: The positive integer pixel scale.
returns: The width in logical pixels, or zero when no font is selected.
End Rem
Function TextWidth:Int(text:String, scale:Int = 1)
	Return Default2DContext().TextWidth(text, scale)
End Function

Rem
bbdoc: Returns the scaled line height of the default context's bitmap font.
param: The positive integer pixel scale.
returns: The line height in pixels, or zero for no font or an invalid scale.
End Rem
Function FontHeight:Int(scale:Int = 1)
	Return Default2DContext().FontHeight(scale)
End Function

Rem
bbdoc: Measures text wrapped to a fixed width using the default context's font.
param: The UTF-8 text to measure.
param: The maximum line width in pixels.
param: Receives the widest resulting line.
param: Receives the total height of the resulting lines.
param: The positive integer pixel scale.
returns: The number of resulting lines.
End Rem
Function TextBoxSize:Int(text:String, width:Int, measuredWidth:Int Var, ..
		measuredHeight:Int Var, scale:Int = 1)
	Return Default2DContext().TextBoxSize(text, width, measuredWidth, measuredHeight, scale)
End Function

Rem
bbdoc: Draws aligned, word-wrapped text inside a fixed rectangle.
param: The UTF-8 text to draw.
param: The text-box left coordinate.
param: The text-box top coordinate.
param: The text-box width in pixels.
param: The text-box height in pixels.
param: A TextAlign value applied independently to each line.
param: The positive integer pixel scale.
param: True to add an ellipsis when text exceeds the available lines.
returns: The number of lines drawn.
End Rem
Function DrawTextBox:Int(text:String, x:Int, y:Int, width:Int, height:Int, ..
		alignment:Int = TextAlignLeft, scale:Int = 1, ellipsis:Int = True)
	Return Default2DContext().DrawTextBox(text, x, y, width, height, alignment, scale, ellipsis)
End Function

Rem
bbdoc: Draws an image with optional flipping, opacity, and color-key transparency.
param: The firmware-resident image to draw.
param: The destination left coordinate.
param: The destination top coordinate.
param: A bitwise combination of ImageFlip constants.
param: Source opacity from 0 through 255.
param: An $RRGGBB transparent source color, or ImageColorKeyDisabled.
End Rem
Function DrawImage(image:TEmbeddedImage, x:Int, y:Int, drawFlags:Int = 0, ..
		opacity:Int = 255, colorKey:UInt = ImageColorKeyDisabled)
	Default2DContext().DrawImage(image, x, y, drawFlags, opacity, colorKey)
End Function

Rem
bbdoc: Draws an image scaled to a destination rectangle using nearest-neighbour sampling.
param: The firmware-resident image to draw.
param: The destination left coordinate.
param: The destination top coordinate.
param: The destination width in pixels.
param: The destination height in pixels.
param: A bitwise combination of ImageFlip constants.
param: Source opacity from 0 through 255.
param: An $RRGGBB transparent source color, or ImageColorKeyDisabled.
End Rem
Function DrawImageRect(image:TEmbeddedImage, x:Int, y:Int, width:Int, height:Int, ..
		drawFlags:Int = 0, opacity:Int = 255, colorKey:UInt = ImageColorKeyDisabled)
	Default2DContext().DrawImageRect(image, x, y, width, height, drawFlags, opacity, colorKey)
End Function

Rem
bbdoc: Draws an unscaled rectangular region of an image.
param: The firmware-resident image to draw.
param: The destination left coordinate.
param: The destination top coordinate.
param: The source-region left coordinate.
param: The source-region top coordinate.
param: The region width in pixels.
param: The region height in pixels.
param: A bitwise combination of ImageFlip constants.
param: Source opacity from 0 through 255.
param: An $RRGGBB transparent source color, or ImageColorKeyDisabled.
End Rem
Function DrawImageRegion(image:TEmbeddedImage, x:Int, y:Int, sourceX:Int, sourceY:Int, ..
		width:Int, height:Int, drawFlags:Int = 0, opacity:Int = 255, ..
		colorKey:UInt = ImageColorKeyDisabled)
	Default2DContext().DrawImageRegion(image, x, y, sourceX, sourceY, width, height, ..
		drawFlags, opacity, colorKey)
End Function

Rem
bbdoc: Presents the default context's complete render target.
param: The destination display, or Null to use the bound display.
returns: A positive value on success, or a DisplayError value on failure.
End Rem
Function Present:Int(display:TDisplay = Null)
	Return Default2DContext().Present(display)
End Function

Rem
bbdoc: Presents a complete frame whose render-buffer contents may be discarded.
param: The destination display, or Null to use the bound display.
returns: A positive value on success, or a DisplayError value on failure.
End Rem
Function PresentDiscard:Int(display:TDisplay = Null)
	Return Default2DContext().PresentDiscard(display)
End Function

Rem
bbdoc: Presents the default context's accumulated dirty rectangles.
param: The destination display, or Null to use the bound display.
returns: A positive value on success, or a DisplayError value on failure.
End Rem
Function PresentDirty:Int(display:TDisplay = Null)
	Return Default2DContext().PresentDirty(display)
End Function
?
