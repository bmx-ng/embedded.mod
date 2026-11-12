' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Lightweight retained user interfaces for embedded displays.
about: Embedded.UI provides a parent-owned widget tree, deterministic row,
column, and stack layout, state-aware styling, touch hit-testing, semantic
events, and automatic dirty-region presentation over Embedded.Graphics2D.
End Rem
Module Embedded.UI
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Font
Import Embedded.Drivers.Touch
Import Embedded.Graphics2D

Const UILayoutAuto:Int = -1
Const UILayoutFill:Int = -2
Const UIAlignStart:Int = 0
Const UIAlignCenter:Int = 1
Const UIAlignEnd:Int = 2
Const UIAlignStretch:Int = 3
Const UIContextMaximum:Int = 4
Const UIInvalidRegionMaximum:Int = 8

Global EVENT_UIACTION:Int = AllocUserEventId("UIAction")
Global EVENT_UIVALUECHANGED:Int = AllocUserEventId("UIValueChanged")

Type TUIStyle
	Field font:TBitmapFont
	Field fontScale:Int = 1
	Field foreground:UInt = $ffffff
	Field background:UInt
	Field border:UInt
	Field backgroundVisible:Int
	Field borderWidth:Int
	Field cornerRadius:Int
	Field paddingLeft:Int
	Field paddingTop:Int
	Field paddingRight:Int
	Field paddingBottom:Int

	Function Create:TUIStyle(foreground:UInt = $ffffff, background:UInt = 0, ..
			backgroundVisible:Int = False)
		Local style:TUIStyle = New TUIStyle
		style.foreground = foreground
		style.background = background
		style.backgroundVisible = backgroundVisible
		Return style
	End Function

	Method Copy:TUIStyle()
		Local result:TUIStyle = New TUIStyle
		result.font = font
		result.fontScale = fontScale
		result.foreground = foreground
		result.background = background
		result.border = border
		result.backgroundVisible = backgroundVisible
		result.borderWidth = borderWidth
		result.cornerRadius = cornerRadius
		result.paddingLeft = paddingLeft
		result.paddingTop = paddingTop
		result.paddingRight = paddingRight
		result.paddingBottom = paddingBottom
		Return result
	End Method

	Method SetPadding(value:Int)
		SetPaddingEdges(value, value, value, value)
	End Method

	Method SetPaddingEdges(left:Int, top:Int, right:Int, bottom:Int)
		paddingLeft = left
		paddingTop = top
		paddingRight = right
		paddingBottom = bottom
	End Method
End Type

Type TUITheme
	Field screen:TUIStyle
	Field container:TUIStyle
	Field label:TUIStyle
	Field button:TUIStyle
	Field buttonPressed:TUIStyle
	Field buttonDisabled:TUIStyle
	Field control:TUIStyle
	Field controlActive:TUIStyle
	Field controlPressed:TUIStyle
	Field controlDisabled:TUIStyle
	Field progress:TUIStyle
	Field progressFill:TUIStyle

	Function Dark:TUITheme(font:TBitmapFont = Null)
		Local theme:TUITheme = New TUITheme
		theme.screen = TUIStyle.Create($e8edf2, $10161d, True)
		theme.container = TUIStyle.Create($e8edf2)
		theme.label = TUIStyle.Create($e8edf2)
		theme.button = TUIStyle.Create($ffffff, $28689b, True)
		theme.button.border = $5ba7df
		theme.button.borderWidth = 1
		theme.button.cornerRadius = 4
		theme.button.SetPaddingEdges(10, 7, 10, 7)
		theme.buttonPressed = theme.button.Copy()
		theme.buttonPressed.background = $174264
		theme.buttonPressed.border = $9bd5ff
		theme.buttonDisabled = theme.button.Copy()
		theme.buttonDisabled.foreground = $86919a
		theme.buttonDisabled.background = $303941
		theme.control = TUIStyle.Create($e8edf2, $26323d, True)
		theme.control.border = $71818e
		theme.control.borderWidth = 1
		theme.control.cornerRadius = 4
		theme.control.SetPaddingEdges(4, 4, 4, 4)
		theme.controlActive = theme.control.Copy()
		theme.controlActive.background = $2d8fca
		theme.controlActive.border = $8dd8ff
		theme.controlPressed = theme.controlActive.Copy()
		theme.controlPressed.background = $1d668f
		theme.controlDisabled = theme.control.Copy()
		theme.controlDisabled.foreground = $86919a
		theme.controlDisabled.background = $303941
		theme.progress = theme.control.Copy()
		theme.progress.background = $202a33
		theme.progressFill = theme.controlActive.Copy()
		theme.progressFill.borderWidth = 0
		theme.SetFont(font)
		Return theme
	End Function

	Method SetFont(font:TBitmapFont, scale:Int = 1)
		If scale < 1 Then scale = 1
		screen.font = font
		container.font = font
		label.font = font
		button.font = font
		buttonPressed.font = font
		buttonDisabled.font = font
		control.font = font
		controlActive.font = font
		controlPressed.font = font
		controlDisabled.font = font
		progress.font = font
		progressFill.font = font
		screen.fontScale = scale
		container.fontScale = scale
		label.fontScale = scale
		button.fontScale = scale
		buttonPressed.fontScale = scale
		buttonDisabled.fontScale = scale
		control.fontScale = scale
		controlActive.fontScale = scale
		controlPressed.fontScale = scale
		controlDisabled.fontScale = scale
		progress.fontScale = scale
		progressFill.fontScale = scale
	End Method
End Type

Private

Global _uiContexts:TUIContext[UIContextMaximum]

Function _UIEventHook:Object(hookId:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If Not event Then Return data
	If event.id <> EVENT_TOUCHDOWN And event.id <> EVENT_TOUCHMOVE And ..
			event.id <> EVENT_TOUCHUP Then Return data
	For Local ui:TUIContext = EachIn _uiContexts
		If ui Then ui._HandleTouchEvent(event)
	Next
	Return data
End Function

Function _ClampNonNegative:Int(value:Int)
	If value < 0 Then Return 0
	Return value
End Function

Public

Type TUIWidget
	Public
	Field uiContext:TUIContext
	Field uiParent:TUIContainer
	Field uiChildren:TUIWidget[] = New TUIWidget[0]
	Field uiStyle:TUIStyle
	Field uiX:Int
	Field uiY:Int
	Field uiWidth:Int
	Field uiHeight:Int
	Field requestedWidth:Int = UILayoutAuto
	Field requestedHeight:Int = UILayoutAuto
	Field growWeight:Int
	Field alignSelf:Int = UIAlignStretch
	Field marginLeft:Int
	Field marginTop:Int
	Field marginRight:Int
	Field marginBottom:Int
	Field visible:Int = True
	Field enabled:Int = True
	Field pressed:Int
	Field clickable:Int

	Public
	Method Context:TUIContext() Final
		Return uiContext
	End Method

	Method Parent:TUIContainer() Final
		Return uiParent
	End Method

	Method ChildCount:Int() Final
		Return uiChildren.Length
	End Method

	Method Child:TUIWidget(index:Int) Final
		If index < 0 Or index >= uiChildren.Length Then Return Null
		Return uiChildren[index]
	End Method

	Method X:Int() Final
		Return uiX
	End Method

	Method Y:Int() Final
		Return uiY
	End Method

	Method Width:Int() Final
		Return uiWidth
	End Method

	Method Height:Int() Final
		Return uiHeight
	End Method

	Method SetWidth(width:Int)
		If width < 0 And width <> UILayoutAuto And width <> UILayoutFill Then width = 0
		If requestedWidth = width Then Return
		requestedWidth = width
		_RequestLayout()
	End Method

	Method SetHeight(height:Int)
		If height < 0 And height <> UILayoutAuto And height <> UILayoutFill Then height = 0
		If requestedHeight = height Then Return
		requestedHeight = height
		_RequestLayout()
	End Method

	Method SetSize(width:Int, height:Int)
		SetWidth(width)
		SetHeight(height)
	End Method

	Method SetGrow(weight:Int = 1)
		weight = _ClampNonNegative(weight)
		If growWeight = weight Then Return
		growWeight = weight
		_RequestLayout()
	End Method

	Method Grow:Int()
		Return growWeight
	End Method

	Method SetAlign(align:Int)
		If align < UIAlignStart Or align > UIAlignStretch Then align = UIAlignStretch
		If alignSelf = align Then Return
		alignSelf = align
		_RequestLayout()
	End Method

	Method SetMargin(value:Int)
		SetMarginEdges(value, value, value, value)
	End Method

	Method SetMarginEdges(left:Int, top:Int, right:Int, bottom:Int)
		marginLeft = _ClampNonNegative(left)
		marginTop = _ClampNonNegative(top)
		marginRight = _ClampNonNegative(right)
		marginBottom = _ClampNonNegative(bottom)
		_RequestLayout()
	End Method

	Method SetVisible(value:Int)
		value = value <> 0
		If visible = value Then Return
		_Invalidate()
		visible = value
		_RequestLayout()
	End Method

	Method Visible:Int()
		Return visible
	End Method

	Method SetEnabled(value:Int)
		value = value <> 0
		If enabled = value Then Return
		enabled = value
		If Not enabled Then pressed = False
		_Invalidate()
	End Method

	Method Enabled:Int()
		Return enabled
	End Method

	Method Pressed:Int()
		Return pressed
	End Method

	Method Style:TUIStyle()
		If Not uiStyle Then uiStyle = DefaultStyle().Copy()
		Return uiStyle
	End Method

	Method SetStyle(style:TUIStyle)
		_Invalidate()
		uiStyle = style
		_RequestLayout()
	End Method

	Method Invalidate()
		_Invalidate()
	End Method

	Method Contains:Int(x:Int, y:Int)
		Return visible And x >= uiX And y >= uiY And x < uiX + uiWidth And y < uiY + uiHeight
	End Method

	Method DefaultStyle:TUIStyle()
		If uiContext And uiContext.Theme() Then Return uiContext.Theme().container
		Return TUIStyle.Create()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var)
		width = 0
		height = 0
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext)
	End Method

	Public
	Method _Attach(context:TUIContext, parent:TUIContainer)
		uiContext = context
		uiParent = parent
	End Method

	Method _SetBounds(x:Int, y:Int, width:Int, height:Int)
		If uiX = x And uiY = y And uiWidth = width And uiHeight = height Then Return
		_Invalidate()
		uiX = x
		uiY = y
		uiWidth = _ClampNonNegative(width)
		uiHeight = _ClampNonNegative(height)
		_Invalidate()
	End Method

	Method _Invalidate()
		If uiContext And uiWidth > 0 And uiHeight > 0 Then ..
			uiContext.InvalidateRect(uiX, uiY, uiWidth, uiHeight)
	End Method

	Method _RequestLayout()
		If uiContext Then uiContext.RequestLayout()
	End Method

	Method _SetPressed(value:Int)
		value = value <> 0
		If pressed = value Then Return
		pressed = value
		_Invalidate()
	End Method
End Type

Type TUIContainer Extends TUIWidget
	Public
	Field layoutDirection:Int
	Field gap:Int
	Field paddingLeft:Int
	Field paddingTop:Int
	Field paddingRight:Int
	Field paddingBottom:Int
	Field drawBackground:Int

	Public
	Method SetGap(value:Int)
		value = _ClampNonNegative(value)
		If gap = value Then Return
		gap = value
		_RequestLayout()
	End Method

	Method Gap:Int()
		Return gap
	End Method

	Method SetPadding(value:Int)
		SetPaddingEdges(value, value, value, value)
	End Method

	Method SetPaddingEdges(left:Int, top:Int, right:Int, bottom:Int)
		paddingLeft = _ClampNonNegative(left)
		paddingTop = _ClampNonNegative(top)
		paddingRight = _ClampNonNegative(right)
		paddingBottom = _ClampNonNegative(bottom)
		_RequestLayout()
	End Method

	Method SetBackgroundVisible(value:Int)
		drawBackground = value <> 0
		_Invalidate()
	End Method

	Method Add:TUIWidget(widget:TUIWidget)
		If Not widget Or widget.Parent() Then Return Null
		uiChildren = uiChildren[..uiChildren.Length + 1]
		uiChildren[uiChildren.Length - 1] = widget
		widget._Attach(Context(), Self)
		_RequestLayout()
		Return widget
	End Method

	Method Row:TUIRow() Final
		Local widget:TUIRow = New TUIRow
		Add(widget)
		Return widget
	End Method

	Method Column:TUIColumn() Final
		Local widget:TUIColumn = New TUIColumn
		Add(widget)
		Return widget
	End Method

	Method Stack:TUIStack() Final
		Local widget:TUIStack = New TUIStack
		Add(widget)
		Return widget
	End Method

	Method Label:TUILabel(text:String = "") Final
		Local widget:TUILabel = New TUILabel
		widget.SetText(text)
		Add(widget)
		Return widget
	End Method

	Method Button:TUIButton(text:String = "") Final
		Local widget:TUIButton = New TUIButton
		widget.SetText(text)
		Add(widget)
		Return widget
	End Method

	Method CheckBox:TUICheckBox(text:String = "", checked:Int = False) Final
		Local widget:TUICheckBox = New TUICheckBox
		widget.SetText(text)
		widget.SetChecked(checked)
		Add(widget)
		Return widget
	End Method

	Method Switch:TUISwitch(value:Int = False) Final
		Local widget:TUISwitch = New TUISwitch
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Method Slider:TUISlider(minimum:Int = 0, maximum:Int = 100, value:Int = 0) Final
		Local widget:TUISlider = New TUISlider
		widget.SetRange(minimum, maximum)
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Method ProgressBar:TUIProgressBar(minimum:Int = 0, maximum:Int = 100, value:Int = 0) Final
		Local widget:TUIProgressBar = New TUIProgressBar
		widget.SetRange(minimum, maximum)
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local contentWidth:Int
		Local contentHeight:Int
		Local visibleCount:Int
		For Local child:TUIWidget = EachIn uiChildren
			If Not child.Visible() Then Continue
			Local childWidth:Int
			Local childHeight:Int
			child.PreferredSize(availableWidth, availableHeight, childWidth, childHeight)
			If layoutDirection = 1 Then
				contentWidth :+ childWidth + child.marginLeft + child.marginRight
				If childHeight + child.marginTop + child.marginBottom > contentHeight Then ..
					contentHeight = childHeight + child.marginTop + child.marginBottom
			Else If layoutDirection = 2 Then
				If childWidth + child.marginLeft + child.marginRight > contentWidth Then ..
					contentWidth = childWidth + child.marginLeft + child.marginRight
				contentHeight :+ childHeight + child.marginTop + child.marginBottom
			Else
				If childWidth + child.marginLeft + child.marginRight > contentWidth Then ..
					contentWidth = childWidth + child.marginLeft + child.marginRight
				If childHeight + child.marginTop + child.marginBottom > contentHeight Then ..
					contentHeight = childHeight + child.marginTop + child.marginBottom
			End If
			visibleCount :+ 1
		Next
		If visibleCount > 1 And layoutDirection <> 0 Then
			If layoutDirection = 1 Then
				contentWidth :+ gap * (visibleCount - 1)
			Else
				contentHeight :+ gap * (visibleCount - 1)
			End If
		End If
		width = contentWidth + paddingLeft + paddingRight
		height = contentHeight + paddingTop + paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		If drawBackground Or style.backgroundVisible Then
			graphics.SetColorValue(style.background)
			If style.cornerRadius > 0 Then
				graphics.FillRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
			Else
				graphics.FillRect(X(), Y(), Width(), Height())
			End If
		End If
	End Method

	Public
	Method _LayoutChildren()
		Local contentX:Int = X() + paddingLeft
		Local contentY:Int = Y() + paddingTop
		Local contentWidth:Int = Width() - paddingLeft - paddingRight
		Local contentHeight:Int = Height() - paddingTop - paddingBottom
		If contentWidth < 0 Then contentWidth = 0
		If contentHeight < 0 Then contentHeight = 0
		If layoutDirection = 0 Then
			For Local child:TUIWidget = EachIn uiChildren
				If Not child.Visible() Then Continue
				Local preferredWidth:Int
				Local preferredHeight:Int
				child.PreferredSize(contentWidth, contentHeight, preferredWidth, preferredHeight)
				Local childWidth:Int = contentWidth - child.marginLeft - child.marginRight
				Local childHeight:Int = contentHeight - child.marginTop - child.marginBottom
				If child.requestedWidth >= 0 Then childWidth = child.requestedWidth
				If child.requestedHeight >= 0 Then childHeight = child.requestedHeight
				child._SetBounds(contentX + child.marginLeft, contentY + child.marginTop, childWidth, childHeight)
				Local childContainer:TUIContainer = TUIContainer(child)
				If childContainer Then childContainer._LayoutChildren()
			Next
			Return
		End If

		Local visibleCount:Int
		Local fixed:Int
		Local totalGrow:Int
		For Local child:TUIWidget = EachIn uiChildren
			If Not child.Visible() Then Continue
			Local preferredWidth:Int
			Local preferredHeight:Int
			child.PreferredSize(contentWidth, contentHeight, preferredWidth, preferredHeight)
			If layoutDirection = 1 Then
				fixed :+ child.marginLeft + child.marginRight
				If child.growWeight > 0 Or child.requestedWidth = UILayoutFill Then
					totalGrow :+ Max(child.growWeight, 1)
				Else
					fixed :+ preferredWidth
				End If
			Else
				fixed :+ child.marginTop + child.marginBottom
				If child.growWeight > 0 Or child.requestedHeight = UILayoutFill Then
					totalGrow :+ Max(child.growWeight, 1)
				Else
					fixed :+ preferredHeight
				End If
			End If
			visibleCount :+ 1
		Next
		If visibleCount > 1 Then fixed :+ gap * (visibleCount - 1)
		Local mainAvailable:Int
		If layoutDirection = 1 Then mainAvailable = contentWidth Else mainAvailable = contentHeight
		Local flexible:Int = mainAvailable - fixed
		If flexible < 0 Then flexible = 0
		Local cursor:Int
		If layoutDirection = 1 Then cursor = contentX Else cursor = contentY
		For Local child:TUIWidget = EachIn uiChildren
			If Not child.Visible() Then Continue
			Local preferredWidth:Int
			Local preferredHeight:Int
			child.PreferredSize(contentWidth, contentHeight, preferredWidth, preferredHeight)
			Local childX:Int
			Local childY:Int
			Local childWidth:Int
			Local childHeight:Int
			If layoutDirection = 1 Then
				cursor :+ child.marginLeft
				childWidth = preferredWidth
				If child.growWeight > 0 Or child.requestedWidth = UILayoutFill Then ..
					childWidth = flexible * Max(child.growWeight, 1) / Max(totalGrow, 1)
				childHeight = preferredHeight
				If child.alignSelf = UIAlignStretch Or child.requestedHeight = UILayoutFill Then ..
					childHeight = contentHeight - child.marginTop - child.marginBottom
				childX = cursor
				childY = contentY + child.marginTop
				If child.alignSelf = UIAlignCenter Then childY = contentY + (contentHeight - childHeight) / 2
				If child.alignSelf = UIAlignEnd Then childY = contentY + contentHeight - childHeight - child.marginBottom
				cursor :+ childWidth + child.marginRight + gap
			Else
				cursor :+ child.marginTop
				childHeight = preferredHeight
				If child.growWeight > 0 Or child.requestedHeight = UILayoutFill Then ..
					childHeight = flexible * Max(child.growWeight, 1) / Max(totalGrow, 1)
				childWidth = preferredWidth
				If child.alignSelf = UIAlignStretch Or child.requestedWidth = UILayoutFill Then ..
					childWidth = contentWidth - child.marginLeft - child.marginRight
				childX = contentX + child.marginLeft
				childY = cursor
				If child.alignSelf = UIAlignCenter Then childX = contentX + (contentWidth - childWidth) / 2
				If child.alignSelf = UIAlignEnd Then childX = contentX + contentWidth - childWidth - child.marginRight
				cursor :+ childHeight + child.marginBottom + gap
			End If
			child._SetBounds(childX, childY, childWidth, childHeight)
			Local childContainer:TUIContainer = TUIContainer(child)
			If childContainer Then childContainer._LayoutChildren()
		Next
	End Method
End Type

Type TUIRow Extends TUIContainer Final
	Method New()
		layoutDirection = 1
	End Method
End Type

Type TUIColumn Extends TUIContainer Final
	Method New()
		layoutDirection = 2
	End Method
End Type

Type TUIStack Extends TUIContainer Final
	Method New()
		layoutDirection = 0
	End Method
End Type

Type TUILabel Extends TUIWidget Final
	Public
	Field labelText:String

	Public
	Method SetText(text:String)
		If Not text Then text = ""
		If labelText = text Then Return
		_Invalidate()
		labelText = text
		_RequestLayout()
	End Method

	Method Text:String()
		Return labelText
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then Return Context().Theme().label
		Return Super.DefaultStyle()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		width = 0
		height = 0
		If style.font Then
			width = style.font.TextWidth(labelText, style.fontScale)
			height = style.font.LineHeight() * style.fontScale
		End If
		width :+ style.paddingLeft + style.paddingRight
		height :+ style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		If Not style.font Then Return
		graphics.SetFont(style.font)
		graphics.SetColorValue(style.foreground)
		graphics.DrawText(labelText, X() + style.paddingLeft, Y() + style.paddingTop, style.fontScale)
	End Method
End Type

Type TUIButton Extends TUIWidget Final
	Public
	Field buttonText:String
	Field clickHandler(button:TUIButton)

	Public
	Method New()
		clickable = True
	End Method

	Method SetText(text:String)
		If Not text Then text = ""
		If buttonText = text Then Return
		_Invalidate()
		buttonText = text
		_RequestLayout()
	End Method

	Method Text:String()
		Return buttonText
	End Method

	Method OnClick(handler(button:TUIButton))
		clickHandler = handler
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then
			If Not Enabled() Then Return Context().Theme().buttonDisabled
			If Pressed() Then Return Context().Theme().buttonPressed
			Return Context().Theme().button
		End If
		Return Super.DefaultStyle()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		width = 0
		height = 0
		If style.font Then
			width = style.font.TextWidth(buttonText, style.fontScale)
			height = style.font.LineHeight() * style.fontScale
		End If
		width :+ style.paddingLeft + style.paddingRight
		height :+ style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		If style.backgroundVisible Then
			graphics.SetColorValue(style.background)
			If style.cornerRadius > 0 Then
				graphics.FillRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
			Else
				graphics.FillRect(X(), Y(), Width(), Height())
			End If
		End If
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			For Local edge:Int = 0 Until style.borderWidth
				If style.cornerRadius > 0 Then
					graphics.DrawRoundRect(X() + edge, Y() + edge, Width() - edge * 2, ..
						Height() - edge * 2, Max(style.cornerRadius - edge, 0))
				Else
					graphics.DrawRect(X() + edge, Y() + edge, Width() - edge * 2, Height() - edge * 2)
				End If
			Next
		End If
		If style.font Then
			graphics.SetFont(style.font)
			graphics.SetColorValue(style.foreground)
			Local textWidth:Int = style.font.TextWidth(buttonText, style.fontScale)
			Local textHeight:Int = style.font.LineHeight() * style.fontScale
			graphics.DrawText(buttonText, X() + (Width() - textWidth) / 2, ..
				Y() + (Height() - textHeight) / 2, style.fontScale)
		End If
	End Method

	Public
	Method _Activate()
		If clickHandler Then clickHandler(Self)
	End Method
End Type

Type TUICheckBox Extends TUIWidget Final
	Public
	Field checkText:String
	Field checked:Int
	Field changeHandler(checkBox:TUICheckBox)

	Public
	Method New()
		clickable = True
	End Method

	Method SetText(text:String)
		If Not text Then text = ""
		If checkText = text Then Return
		_Invalidate()
		checkText = text
		_RequestLayout()
	End Method

	Method Text:String()
		Return checkText
	End Method

	Method SetChecked(value:Int)
		value = value <> 0
		If checked = value Then Return
		checked = value
		_Invalidate()
	End Method

	Method Checked:Int()
		Return checked
	End Method

	Method OnChange(handler(checkBox:TUICheckBox))
		changeHandler = handler
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then
			If Not Enabled() Then Return Context().Theme().controlDisabled
			If Pressed() Then Return Context().Theme().controlPressed
			If checked Then Return Context().Theme().controlActive
			Return Context().Theme().control
		End If
		Return Super.DefaultStyle()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local lineHeight:Int = 16
		Local textWidth:Int
		If style.font Then
			lineHeight = style.font.LineHeight() * style.fontScale
			textWidth = style.font.TextWidth(checkText, style.fontScale)
		End If
		Local boxSize:Int = lineHeight
		width = boxSize + style.paddingLeft + style.paddingRight
		If checkText.Length Then width :+ textWidth + Max(style.fontScale * 4, 6)
		height = Max(lineHeight, boxSize) + style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local contentHeight:Int = Height() - style.paddingTop - style.paddingBottom
		Local boxSize:Int = Max(Min(contentHeight, 24 * style.fontScale), 8)
		Local boxX:Int = X() + style.paddingLeft
		Local boxY:Int = Y() + (Height() - boxSize) / 2
		graphics.SetColorValue(style.background)
		If style.cornerRadius > 0 Then
			graphics.FillRoundRect(boxX, boxY, boxSize, boxSize, Min(style.cornerRadius, boxSize / 3))
		Else
			graphics.FillRect(boxX, boxY, boxSize, boxSize)
		End If
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			graphics.DrawRoundRect(boxX, boxY, boxSize, boxSize, Min(style.cornerRadius, boxSize / 3))
		End If
		If checked Then
			graphics.SetColorValue(style.foreground)
			Local inset:Int = Max(boxSize / 5, 2)
			graphics.DrawLine(boxX + inset, boxY + boxSize / 2, boxX + boxSize * 2 / 5, boxY + boxSize - inset)
			graphics.DrawLine(boxX + boxSize * 2 / 5, boxY + boxSize - inset, boxX + boxSize - inset, boxY + inset)
		End If
		If style.font And checkText.Length Then
			graphics.SetFont(style.font)
			graphics.SetColorValue(style.foreground)
			Local textHeight:Int = style.font.LineHeight() * style.fontScale
			graphics.DrawText(checkText, boxX + boxSize + Max(style.fontScale * 4, 6), ..
				Y() + (Height() - textHeight) / 2, style.fontScale)
		End If
	End Method

	Public
	Method _Activate()
		SetChecked(Not checked)
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIVALUECHANGED, Self, checked))
	End Method
End Type

Type TUISwitch Extends TUIWidget Final
	Public
	Field switchValue:Int
	Field changeHandler(switchControl:TUISwitch)

	Public
	Method New()
		clickable = True
	End Method

	Method SetValue(value:Int)
		value = value <> 0
		If switchValue = value Then Return
		switchValue = value
		_Invalidate()
	End Method

	Method Value:Int()
		Return switchValue
	End Method

	Method OnChange(handler(switchControl:TUISwitch))
		changeHandler = handler
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then
			If Not Enabled() Then Return Context().Theme().controlDisabled
			If Pressed() Then Return Context().Theme().controlPressed
			If switchValue Then Return Context().Theme().controlActive
			Return Context().Theme().control
		End If
		Return Super.DefaultStyle()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local unit:Int = 16 * style.fontScale
		width = unit * 2 + style.paddingLeft + style.paddingRight
		height = unit + style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local trackX:Int = X() + style.paddingLeft
		Local trackY:Int = Y() + style.paddingTop
		Local trackWidth:Int = Width() - style.paddingLeft - style.paddingRight
		Local trackHeight:Int = Height() - style.paddingTop - style.paddingBottom
		Local radius:Int = trackHeight / 2
		graphics.SetColorValue(style.background)
		graphics.FillRoundRect(trackX, trackY, trackWidth, trackHeight, radius)
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			graphics.DrawRoundRect(trackX, trackY, trackWidth, trackHeight, radius)
		End If
		Local thumbRadius:Int = Max(radius - Max(style.borderWidth, 1) - 2, 2)
		Local thumbX:Int = trackX + radius
		If switchValue Then thumbX = trackX + trackWidth - radius
		graphics.SetColorValue(style.foreground)
		graphics.FillCircle(thumbX, trackY + radius, thumbRadius)
	End Method

	Public
	Method _Activate()
		SetValue(Not switchValue)
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIVALUECHANGED, Self, switchValue))
	End Method
End Type

Type TUIRangeWidget Extends TUIWidget
	Public
	Field minimumValue:Int
	Field maximumValue:Int = 100
	Field currentValue:Int

	Public
	Method SetRange(minimum:Int, maximum:Int)
		If maximum < minimum Then maximum = minimum
		If minimumValue = minimum And maximumValue = maximum Then Return
		minimumValue = minimum
		maximumValue = maximum
		If currentValue < minimumValue Then currentValue = minimumValue
		If currentValue > maximumValue Then currentValue = maximumValue
		_Invalidate()
	End Method

	Method Minimum:Int()
		Return minimumValue
	End Method

	Method Maximum:Int()
		Return maximumValue
	End Method

	Method SetValue(value:Int)
		If value < minimumValue Then value = minimumValue
		If value > maximumValue Then value = maximumValue
		If currentValue = value Then Return
		currentValue = value
		_Invalidate()
	End Method

	Method Value:Int()
		Return currentValue
	End Method

	Method Fraction:Int(scale:Int)
		If maximumValue <= minimumValue Then Return 0
		Return Int(Long(currentValue - minimumValue) * scale / Long(maximumValue - minimumValue))
	End Method
End Type

Type TUISlider Extends TUIRangeWidget Final
	Public
	Field changeHandler(slider:TUISlider)

	Public
	Method New()
		clickable = True
	End Method

	Method OnChange(handler(slider:TUISlider))
		changeHandler = handler
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then
			If Not Enabled() Then Return Context().Theme().controlDisabled
			If Pressed() Then Return Context().Theme().controlPressed
			Return Context().Theme().control
		End If
		Return Super.DefaultStyle()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		width = 120 * style.fontScale + style.paddingLeft + style.paddingRight
		height = 20 * style.fontScale + style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local active:TUIStyle = style
		If Context() And Context().Theme() And Enabled() Then active = Context().Theme().controlActive
		Local radius:Int = Max((Height() - style.paddingTop - style.paddingBottom) / 2, 3)
		Local startX:Int = X() + style.paddingLeft + radius
		Local endX:Int = X() + Width() - style.paddingRight - radius
		If endX < startX Then endX = startX
		Local centerY:Int = Y() + Height() / 2
		Local trackHeight:Int = Max(radius / 3, 2)
		Local thumbX:Int = startX + Fraction(endX - startX)
		graphics.SetColorValue(style.background)
		graphics.FillRoundRect(startX, centerY - trackHeight / 2, endX - startX, trackHeight, trackHeight / 2)
		If thumbX > startX Then
			graphics.SetColorValue(active.background)
			graphics.FillRoundRect(startX, centerY - trackHeight / 2, thumbX - startX, trackHeight, trackHeight / 2)
		End If
		graphics.SetColorValue(active.foreground)
		graphics.FillCircle(thumbX, centerY, Max(radius - 2, 2))
	End Method

	Public
	Method _TrackPointer(x:Int)
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local radius:Int = Max((Height() - style.paddingTop - style.paddingBottom) / 2, 3)
		Local startX:Int = X() + style.paddingLeft + radius
		Local endX:Int = X() + Width() - style.paddingRight - radius
		Local value:Int = minimumValue
		If endX > startX Then
			If x < startX Then x = startX
			If x > endX Then x = endX
			value = minimumValue + Int((Long(x - startX) * Long(maximumValue - minimumValue) + ..
				Long(endX - startX) / 2) / Long(endX - startX))
		End If
		If value = currentValue Then Return
		SetValue(value)
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIVALUECHANGED, Self, currentValue))
	End Method
End Type

Type TUIProgressBar Extends TUIRangeWidget Final
	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then Return Context().Theme().progress
		Return Super.DefaultStyle()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		width = 120 * style.fontScale + style.paddingLeft + style.paddingRight
		height = 12 * style.fontScale + style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local fill:TUIStyle = style
		If Context() And Context().Theme() Then fill = Context().Theme().progressFill
		Local barX:Int = X() + style.paddingLeft
		Local barY:Int = Y() + style.paddingTop
		Local barWidth:Int = Width() - style.paddingLeft - style.paddingRight
		Local barHeight:Int = Height() - style.paddingTop - style.paddingBottom
		Local radius:Int = Min(style.cornerRadius, barHeight / 2)
		graphics.SetColorValue(style.background)
		graphics.FillRoundRect(barX, barY, barWidth, barHeight, radius)
		Local fillWidth:Int = Fraction(barWidth)
		If fillWidth > 0 Then
			graphics.SetColorValue(fill.background)
			graphics.FillRoundRect(barX, barY, fillWidth, barHeight, radius)
		End If
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			graphics.DrawRoundRect(barX, barY, barWidth, barHeight, radius)
		End If
	End Method
End Type

Type TUIContext
	Public
	Field display:TDisplay
	Field frame:TDisplayBuffer
	Field graphics:TEmbedded2DContext
	Field touch:TTouchDevice
	Field rootWidget:TUIColumn
	Field themeValue:TUITheme
	Field layoutPending:Int = True
	Field contextSlot:Int = -1
	Field pressedWidget:TUIWidget
	Field pressedContact:Int = -1
	Field pressedArmed:Int
	Field invalidCount:Int
	Field invalidX0:Int[UIInvalidRegionMaximum]
	Field invalidY0:Int[UIInvalidRegionMaximum]
	Field invalidX1:Int[UIInvalidRegionMaximum]
	Field invalidY1:Int[UIInvalidRegionMaximum]

	Public
	Function Create:TUIContext(display:TDisplay, touch:TTouchDevice = Null, theme:TUITheme = Null)
		If Not display Then Return Null
		Local frame:TDisplayBuffer = display.CreateBuffer()
		If Not frame Then Return Null
		Return CreateWithBuffer(frame, display, touch, theme)
	End Function

	Function CreateWithBuffer:TUIContext(frame:TDisplayBuffer, display:TDisplay = Null, ..
			touch:TTouchDevice = Null, theme:TUITheme = Null)
		If Not frame Then Return Null
		Local result:TUIContext = New TUIContext
		result.display = display
		result.frame = frame
		result.graphics = TEmbedded2DContext.Create(frame, display)
		result.graphics.SetDirtyTracking(True)
		result.touch = touch
		If theme Then result.themeValue = theme Else result.themeValue = TUITheme.Dark()
		result.rootWidget = New TUIColumn
		result.rootWidget._Attach(result, Null)
		result.rootWidget.uiStyle = result.themeValue.screen
		result.rootWidget.drawBackground = True
		For Local slot:Int = 0 Until UIContextMaximum
			If Not _uiContexts[slot] Then
				_uiContexts[slot] = result
				result.contextSlot = slot
				Exit
			End If
		Next
		If result.contextSlot < 0 Then Return Null
		result.InvalidateAll()
		Return result
	End Function

	Method Close()
		If contextSlot >= 0 And contextSlot < UIContextMaximum And _uiContexts[contextSlot] = Self Then ..
			_uiContexts[contextSlot] = Null
		contextSlot = -1
		pressedWidget = Null
	End Method

	Method Root:TUIColumn()
		Return rootWidget
	End Method

	Method Theme:TUITheme()
		Return themeValue
	End Method

	Method SetTheme(theme:TUITheme)
		If Not theme Then Return
		themeValue = theme
		rootWidget.uiStyle = theme.screen
		InvalidateAll()
		RequestLayout()
	End Method

	Method Graphics:TEmbedded2DContext()
		Return graphics
	End Method

	Method Frame:TDisplayBuffer()
		Return frame
	End Method

	Method RequestLayout()
		layoutPending = True
	End Method

	Method InvalidateAll()
		invalidCount = 1
		invalidX0[0] = 0
		invalidY0[0] = 0
		invalidX1[0] = frame.Width()
		invalidY1[0] = frame.Height()
	End Method

	Method InvalidateRect(x:Int, y:Int, width:Int, height:Int)
		If width <= 0 Or height <= 0 Then Return
		Local x1:Int = x + width
		Local y1:Int = y + height
		If x < 0 Then x = 0
		If y < 0 Then y = 0
		If x1 > frame.Width() Then x1 = frame.Width()
		If y1 > frame.Height() Then y1 = frame.Height()
		If x >= x1 Or y >= y1 Then Return
		Local index:Int
		While index < invalidCount
			If x <= invalidX1[index] And x1 >= invalidX0[index] And ..
					y <= invalidY1[index] And y1 >= invalidY0[index] Then
				If invalidX0[index] < x Then x = invalidX0[index]
				If invalidY0[index] < y Then y = invalidY0[index]
				If invalidX1[index] > x1 Then x1 = invalidX1[index]
				If invalidY1[index] > y1 Then y1 = invalidY1[index]
				invalidCount :- 1
				invalidX0[index] = invalidX0[invalidCount]
				invalidY0[index] = invalidY0[invalidCount]
				invalidX1[index] = invalidX1[invalidCount]
				invalidY1[index] = invalidY1[invalidCount]
				index = 0
				Continue
			End If
			index :+ 1
		Wend
		If invalidCount >= UIInvalidRegionMaximum Then
			InvalidateAll()
			Return
		End If
		invalidX0[invalidCount] = x
		invalidY0[invalidCount] = y
		invalidX1[invalidCount] = x1
		invalidY1[invalidCount] = y1
		invalidCount :+ 1
	End Method

	Method Layout()
		rootWidget._SetBounds(0, 0, graphics.Width(), graphics.Height())
		rootWidget._LayoutChildren()
		layoutPending = False
	End Method

	Method Render:Int()
		If layoutPending Then Layout()
		If invalidCount = 0 Then Return False
		graphics.ResetDirty()
		For Local index:Int = 0 Until invalidCount
			Local x:Int = invalidX0[index]
			Local y:Int = invalidY0[index]
			Local width:Int = invalidX1[index] - x
			Local height:Int = invalidY1[index] - y
			graphics.PushState()
			graphics.SetViewport(x, y, width, height)
			_DrawWidget(rootWidget, x, y, width, height)
			graphics.PopState()
		Next
		invalidCount = 0
		Return True
	End Method

	Method Present:Int()
		Render()
		If display Then Return graphics.PresentDirty(display)
		Return True
	End Method

	Method HitTest:TUIWidget(x:Int, y:Int)
		If layoutPending Then Layout()
		Return _HitTest(rootWidget, x, y)
	End Method

	Method _HandleTouchEvent(event:TEvent)
		If touch And event.source <> touch Then Return
		Local x:Int
		Local y:Int
		If frame.Width() > 1 Then x = Int((Long(event.x) * (frame.Width() - 1) + 5000) / 10000)
		If frame.Height() > 1 Then y = Int((Long(event.y) * (frame.Height() - 1) + 5000) / 10000)
		Select event.id
			Case EVENT_TOUCHDOWN
				If pressedWidget Or Not event.source Then Return
				Local target:TUIWidget = HitTest(x, y)
				If target And target.Enabled() Then
					pressedWidget = target
					pressedContact = event.data
					pressedArmed = True
					target._SetPressed(True)
					Local slider:TUISlider = TUISlider(target)
					If slider Then slider._TrackPointer(x)
				End If
			Case EVENT_TOUCHMOVE
				If pressedWidget And pressedContact = event.data Then
					Local slider:TUISlider = TUISlider(pressedWidget)
					If slider Then
						slider._TrackPointer(x)
					Else
						pressedArmed = pressedWidget.Contains(x, y)
						pressedWidget._SetPressed(pressedArmed)
					End If
				End If
			Case EVENT_TOUCHUP
				If pressedWidget And pressedContact = event.data Then
					Local target:TUIWidget = pressedWidget
					Local slider:TUISlider = TUISlider(target)
					If slider Then slider._TrackPointer(x)
					Local activate:Int = pressedArmed And target.Contains(x, y) And target.Enabled()
					target._SetPressed(False)
					pressedWidget = Null
					pressedContact = -1
					pressedArmed = False
					If activate Then
						Local button:TUIButton = TUIButton(target)
						If button Then
							button._Activate()
							EmitEvent(CreateEvent(EVENT_UIACTION, target, 0, 0, x, y))
						Else
							Local checkBox:TUICheckBox = TUICheckBox(target)
							If checkBox Then
								checkBox._Activate()
							Else
								Local switchControl:TUISwitch = TUISwitch(target)
								If switchControl Then switchControl._Activate()
							End If
						End If
					End If
				End If
		End Select
	End Method

	Public
	Method _DrawWidget(widget:TUIWidget, clipX:Int, clipY:Int, clipWidth:Int, clipHeight:Int)
		If Not widget Or Not widget.Visible() Or Not _Intersects(widget, clipX, clipY, clipWidth, clipHeight) Then Return
		widget.Draw(graphics)
		For Local child:TUIWidget = EachIn widget.uiChildren
			_DrawWidget(child, clipX, clipY, clipWidth, clipHeight)
		Next
	End Method

	Method _HitTest:TUIWidget(widget:TUIWidget, x:Int, y:Int)
		If Not widget Or Not widget.Contains(x, y) Then Return Null
		For Local index:Int = widget.uiChildren.Length - 1 To 0 Step -1
			Local found:TUIWidget = _HitTest(widget.uiChildren[index], x, y)
			If found Then Return found
		Next
		If widget.clickable Then Return widget
		Return Null
	End Method

	Method _Intersects:Int(widget:TUIWidget, x:Int, y:Int, width:Int, height:Int)
		Return widget.X() < x + width And widget.X() + widget.Width() > x And ..
			widget.Y() < y + height And widget.Y() + widget.Height() > y
	End Method
End Type

AddHook EmitEventHook, _UIEventHook
?
