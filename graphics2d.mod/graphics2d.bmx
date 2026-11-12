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

Private

Function ClampColorComponent:Int(value:Int)
	If value < 0 Then Return 0
	If value > 255 Then Return 255
	Return value
End Function

Public

Rem
bbdoc: Stateful allocation-free drawing context for one display buffer.
about: Origins affect drawing coordinates. Viewports are always expressed in
physical target-buffer coordinates and clip every primitive, including text.
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

	Public
	Function Create:TEmbedded2DContext(target:TDisplayBuffer, display:TDisplay = Null)
		Local context:TEmbedded2DContext = New TEmbedded2DContext
		context.SetRenderTarget(target, display)
		Return context
	End Function

	Method SetRenderTarget(target:TDisplayBuffer, display:TDisplay = Null)
		Self.target = target
		boundDisplay = display
		originX = 0
		originY = 0
		ResetViewport()
	End Method

	Method RenderTarget:TDisplayBuffer()
		Return target
	End Method

	Method SetDisplay(display:TDisplay)
		boundDisplay = display
	End Method

	Method Display:TDisplay()
		Return boundDisplay
	End Method

	Method SetFont(font:TBitmapFont)
		currentFont = font
	End Method

	Method Font:TBitmapFont()
		Return currentFont
	End Method

	Method SetColor(red:Int, green:Int, blue:Int)
		drawColor = UInt(ClampColorComponent(red) Shl 16) | ..
			UInt(ClampColorComponent(green) Shl 8) | UInt(ClampColorComponent(blue))
	End Method

	Method SetColorValue(color:UInt)
		drawColor = color & $ffffff
	End Method

	Method Color:UInt()
		Return drawColor
	End Method

	Method SetClsColor(red:Int, green:Int, blue:Int)
		clearColor = UInt(ClampColorComponent(red) Shl 16) | ..
			UInt(ClampColorComponent(green) Shl 8) | UInt(ClampColorComponent(blue))
	End Method

	Method SetClsColorValue(color:UInt)
		clearColor = color & $ffffff
	End Method

	Method ClsColor:UInt()
		Return clearColor
	End Method

	Method SetOrigin(x:Int, y:Int)
		originX = x
		originY = y
	End Method

	Method OriginX:Int()
		Return originX
	End Method

	Method OriginY:Int()
		Return originY
	End Method

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
		If x < 0 Then x = 0
		If y < 0 Then y = 0
		If x1 > target.Width() Then x1 = target.Width()
		If y1 > target.Height() Then y1 = target.Height()
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

	Method ResetViewport()
		If target Then
			viewportX = 0
			viewportY = 0
			viewportWidth = target.Width()
			viewportHeight = target.Height()
		Else
			viewportX = 0
			viewportY = 0
			viewportWidth = 0
			viewportHeight = 0
		End If
	End Method

	Method ViewportX:Int()
		Return viewportX
	End Method

	Method ViewportY:Int()
		Return viewportY
	End Method

	Method ViewportWidth:Int()
		Return viewportWidth
	End Method

	Method ViewportHeight:Int()
		Return viewportHeight
	End Method

	Method Cls()
		If Not target Or viewportWidth <= 0 Or viewportHeight <= 0 Then Return
		If viewportX = 0 And viewportY = 0 And viewportWidth = target.Width() And ..
				viewportHeight = target.Height() Then
			target.Clear(clearColor)
		Else
			target.FillRect(viewportX, viewportY, viewportWidth, viewportHeight, clearColor)
		End If
	End Method

	Method Plot(x:Int, y:Int)
		If Not target Then Return
		x :+ originX
		y :+ originY
		If PointVisible(x, y) Then target.SetPixel(x, y, drawColor)
	End Method

	Method DrawLine(x0:Int, y0:Int, x1:Int, y1:Int)
		If Not target Or viewportWidth <= 0 Or viewportHeight <= 0 Then Return
		x0 :+ originX
		y0 :+ originY
		x1 :+ originX
		y1 :+ originY
		If Not ClipLine(x0, y0, x1, y1) Then Return
		target.DrawLine(x0, y0, x1, y1, drawColor)
	End Method

	Method DrawRect(x:Int, y:Int, width:Int, height:Int)
		If width <= 0 Or height <= 0 Then Return
		DrawLine(x, y, x + width - 1, y)
		DrawLine(x, y + height - 1, x + width - 1, y + height - 1)
		DrawLine(x, y, x, y + height - 1)
		DrawLine(x + width - 1, y, x + width - 1, y + height - 1)
	End Method

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
		If x < x1 And y < y1 Then target.FillRect(x, y, x1 - x, y1 - y, drawColor)
	End Method

	Method DrawText:Int(text:String, x:Int, y:Int, scale:Int = 1)
		If Not target Or Not currentFont Then Return x
		Return currentFont.DrawTextClipped(target, text, x + originX, y + originY, ..
			drawColor, scale, viewportX, viewportY, viewportWidth, viewportHeight) - originX
	End Method

	Method TextWidth:Int(text:String, scale:Int = 1)
		If Not currentFont Then Return 0
		Return currentFont.TextWidth(text, scale)
	End Method

	Method FontHeight:Int(scale:Int = 1)
		If Not currentFont Or scale <= 0 Then Return 0
		Return currentFont.LineHeight() * scale
	End Method

	Method Present:Int(display:TDisplay = Null)
		If Not target Then Return DisplayErrorInvalidArgument
		If Not display Then display = boundDisplay
		If Not display Then Return DisplayErrorInvalidArgument
		Return display.Present(target)
	End Method

	Private
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

Function SetRenderTarget(target:TDisplayBuffer, display:TDisplay = Null)
	Default2DContext().SetRenderTarget(target, display)
End Function

Function RenderTarget:TDisplayBuffer()
	Return Default2DContext().RenderTarget()
End Function

Function SetDisplay(display:TDisplay)
	Default2DContext().SetDisplay(display)
End Function

Function SetFont(font:TBitmapFont)
	Default2DContext().SetFont(font)
End Function

Function SetColor(red:Int, green:Int, blue:Int)
	Default2DContext().SetColor(red, green, blue)
End Function

Function SetColorValue(color:UInt)
	Default2DContext().SetColorValue(color)
End Function

Function SetClsColor(red:Int, green:Int, blue:Int)
	Default2DContext().SetClsColor(red, green, blue)
End Function

Function SetClsColorValue(color:UInt)
	Default2DContext().SetClsColorValue(color)
End Function

Function SetOrigin(x:Int, y:Int)
	Default2DContext().SetOrigin(x, y)
End Function

Function SetViewport(x:Int, y:Int, width:Int, height:Int)
	Default2DContext().SetViewport(x, y, width, height)
End Function

Function ResetViewport()
	Default2DContext().ResetViewport()
End Function

Function Cls()
	Default2DContext().Cls()
End Function

Function Plot(x:Int, y:Int)
	Default2DContext().Plot(x, y)
End Function

Function DrawLine(x0:Int, y0:Int, x1:Int, y1:Int)
	Default2DContext().DrawLine(x0, y0, x1, y1)
End Function

Function DrawRect(x:Int, y:Int, width:Int, height:Int)
	Default2DContext().DrawRect(x, y, width, height)
End Function

Function FillRect(x:Int, y:Int, width:Int, height:Int)
	Default2DContext().FillRect(x, y, width, height)
End Function

Function DrawText:Int(text:String, x:Int, y:Int, scale:Int = 1)
	Return Default2DContext().DrawText(text, x, y, scale)
End Function

Function TextWidth:Int(text:String, scale:Int = 1)
	Return Default2DContext().TextWidth(text, scale)
End Function

Function FontHeight:Int(scale:Int = 1)
	Return Default2DContext().FontHeight(scale)
End Function

Function Present:Int(display:TDisplay = Null)
	Return Default2DContext().Present(display)
End Function
?
