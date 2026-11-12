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
Import BRL.System
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
Const UIScrollDragThreshold:Int = 4
Const UIScrollMinimumMomentum:Int = 60
Const UIScrollMaximumMomentum:Int = 2400
Const UIScrollMomentumDeceleration:Int = 1800

Global EVENT_UIACTION:Int = AllocUserEventId("UIAction")
Global EVENT_UIVALUECHANGED:Int = AllocUserEventId("UIValueChanged")
Global EVENT_UIFOCUSCHANGED:Int = AllocUserEventId("UIFocusChanged")
Global EVENT_UISELECTIONCHANGED:Int = AllocUserEventId("UISelectionChanged")

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
	Field focusColor:UInt = $ffd84a
	Field focusWidth:Int = 2
	Field focusInset:Int = 2

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
	Field focusable:Int

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
		If Not visible And uiContext Then uiContext._ReleaseFocus(Self)
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
		If Not enabled And uiContext Then uiContext._ReleaseFocus(Self)
		_Invalidate()
	End Method

	Method Enabled:Int()
		Return enabled
	End Method

	Method Pressed:Int()
		Return pressed
	End Method

	Method SetFocusable(value:Int)
		value = value <> 0
		If focusable = value Then Return
		focusable = value
		If Not focusable And uiContext Then uiContext._ReleaseFocus(Self)
		_Invalidate()
	End Method

	Method Focusable:Int()
		Return focusable
	End Method

	Method Focused:Int()
		Return uiContext And uiContext.FocusedWidget() = Self
	End Method

	Method RequestFocus:Int()
		If Not uiContext Then Return False
		Return uiContext.SetFocus(Self)
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

	Method DrawOverlay(graphics:TEmbedded2DContext)
	End Method

	Method ClipsChildren:Int()
		Return False
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
		If Not uiContext Or uiWidth <= 0 Or uiHeight <= 0 Then Return
		Local x0:Int = uiX
		Local y0:Int = uiY
		Local x1:Int = uiX + uiWidth
		Local y1:Int = uiY + uiHeight
		Local parent:TUIContainer = uiParent
		While parent
			If parent.ClipsChildren() Then
				If parent.X() > x0 Then x0 = parent.X()
				If parent.Y() > y0 Then y0 = parent.Y()
				If parent.X() + parent.Width() < x1 Then x1 = parent.X() + parent.Width()
				If parent.Y() + parent.Height() < y1 Then y1 = parent.Y() + parent.Height()
			End If
			parent = parent.Parent()
		Wend
		If x0 < x1 And y0 < y1 Then uiContext.InvalidateRect(x0, y0, x1 - x0, y1 - y0)
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

	Method ScrollView:TUIScrollView() Final
		Local widget:TUIScrollView = New TUIScrollView
		Add(widget)
		Return widget
	End Method

	Method List:TUIList() Final
		Local widget:TUIList = New TUIList
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

Type TUIScrollView Extends TUIContainer
	Public
	Field scrollPosition:Int
	Field maximumScroll:Int
	Field contentExtent:Int
	Field showScrollIndicator:Int = True
	Field momentumEnabled:Int
	Field momentumVelocity:Int
	Field momentumRemainder:Int
	Field momentumLastTime:UInt
	Field dragLastTime:UInt
	Field dragActive:Int

	Public
	Method New()
		layoutDirection = 2
	End Method

	Method ScrollY:Int()
		Return scrollPosition
	End Method

	Method MaxScrollY:Int()
		Return maximumScroll
	End Method

	Method ContentHeight:Int()
		Return contentExtent
	End Method

	Method SetScrollY(value:Int)
		_StopMomentum()
		_SetScrollY(value)
	End Method

	Method _SetScrollY(value:Int)
		If value < 0 Then value = 0
		If value > maximumScroll Then value = maximumScroll
		If scrollPosition = value Then Return
		_Invalidate()
		scrollPosition = value
		_RequestLayout()
	End Method

	Method ScrollBy(delta:Int)
		SetScrollY(scrollPosition + delta)
	End Method

	Method SetMomentumEnabled(value:Int)
		momentumEnabled = value <> 0
		If Not momentumEnabled Then _StopMomentum()
	End Method

	Method MomentumEnabled:Int()
		Return momentumEnabled
	End Method

	Method StopMomentum()
		_StopMomentum()
	End Method

	Method SetScrollIndicatorVisible(value:Int)
		value = value <> 0
		If showScrollIndicator = value Then Return
		showScrollIndicator = value
		_Invalidate()
	End Method

	Method ScrollIndicatorVisible:Int()
		Return showScrollIndicator
	End Method

	Method EnsureVisible:Int(widget:TUIWidget)
		If Not widget Then Return False
		Local current:TUIWidget = widget
		While current And current.Parent() <> Self
			current = current.Parent()
		Wend
		If Not current Then Return False
		Local viewportTop:Int = Y() + paddingTop
		Local viewportBottom:Int = Y() + Height() - paddingBottom
		Local nextPosition:Int = scrollPosition
		If widget.Y() < viewportTop Then
			nextPosition :- viewportTop - widget.Y()
		Else If widget.Y() + widget.Height() > viewportBottom Then
			nextPosition :+ widget.Y() + widget.Height() - viewportBottom
		End If
		If nextPosition < 0 Then nextPosition = 0
		If nextPosition > maximumScroll Then nextPosition = maximumScroll
		If nextPosition = scrollPosition Then Return False
		_StopMomentum()
		_SetScrollY(nextPosition)
		Return True
	End Method

	Method ClipsChildren:Int() Override
		Return True
	End Method

	Method DrawOverlay(graphics:TEmbedded2DContext) Override
		If Not showScrollIndicator Or maximumScroll <= 0 Or Height() <= 0 Then Return
		Local viewportHeight:Int = Height()
		Local thumbHeight:Int = Int(Long(viewportHeight) * viewportHeight / Max(contentExtent, 1))
		If thumbHeight < 8 Then thumbHeight = 8
		If thumbHeight > viewportHeight Then thumbHeight = viewportHeight
		Local travel:Int = viewportHeight - thumbHeight
		Local thumbY:Int = Y()
		If travel > 0 Then thumbY :+ Int(Long(scrollPosition) * travel / maximumScroll)
		Local color:UInt = $71818e
		If Context() And Context().Theme() Then color = Context().Theme().control.border
		graphics.SetColorValue(color)
		graphics.FillRoundRect(X() + Width() - 3, thumbY, 3, thumbHeight, 1)
	End Method

	Public
	Method _BeginDrag(now:UInt)
		_StopMomentum()
		dragActive = True
		dragLastTime = now
	End Method

	Method _DragBy(delta:Int, now:UInt)
		If Not dragActive Then _BeginDrag(now)
		Local previous:Int = scrollPosition
		_SetScrollY(scrollPosition + delta)
		Local moved:Int = scrollPosition - previous
		Local elapsed:UInt = now - dragLastTime
		dragLastTime = now
		If moved = 0 Or elapsed = 0 Then Return
		If elapsed > 100 Then elapsed = 100
		Local sample:Int = Int(Long(moved) * 1000 / elapsed)
		If sample > UIScrollMaximumMomentum Then sample = UIScrollMaximumMomentum
		If sample < -UIScrollMaximumMomentum Then sample = -UIScrollMaximumMomentum
		If momentumVelocity <> 0 And (momentumVelocity < 0) <> (sample < 0) Then
			momentumVelocity = sample
		Else
			momentumVelocity = (momentumVelocity + sample * 2) / 3
		End If
	End Method

	Method _EndDrag(now:UInt)
		dragActive = False
		momentumLastTime = now
		momentumRemainder = 0
		If Not momentumEnabled Or Abs(momentumVelocity) < UIScrollMinimumMomentum Then ..
			momentumVelocity = 0
	End Method

	Method _UpdateMomentum(now:UInt)
		If dragActive Or momentumVelocity = 0 Then Return
		Local elapsed:UInt = now - momentumLastTime
		If elapsed = 0 Then Return
		If elapsed > 50 Then elapsed = 50
		momentumLastTime = now
		Local distance:Long = Long(momentumVelocity) * elapsed + momentumRemainder
		Local delta:Int = Int(distance / 1000)
		momentumRemainder = Int(distance Mod 1000)
		If delta <> 0 Then
			Local previous:Int = scrollPosition
			_SetScrollY(scrollPosition + delta)
			If scrollPosition = previous Or scrollPosition = 0 Or scrollPosition = maximumScroll Then
				_StopMomentum()
				Return
			End If
		End If
		Local reduction:Int = Max(Int(Long(UIScrollMomentumDeceleration) * elapsed / 1000), 1)
		If momentumVelocity > 0 Then
			momentumVelocity :- reduction
			If momentumVelocity < UIScrollMinimumMomentum Then momentumVelocity = 0
		Else
			momentumVelocity :+ reduction
			If momentumVelocity > -UIScrollMinimumMomentum Then momentumVelocity = 0
		End If
	End Method

	Method _StopMomentum()
		momentumVelocity = 0
		momentumRemainder = 0
		dragActive = False
	End Method

	Method _LayoutChildren() Override
		Local contentX:Int = X() + paddingLeft
		Local contentWidth:Int = Width() - paddingLeft - paddingRight
		If contentWidth < 0 Then contentWidth = 0
		Local naturalHeight:Int = paddingTop + paddingBottom
		Local visibleCount:Int
		For Local child:TUIWidget = EachIn uiChildren
			If Not child.Visible() Then Continue
			Local preferredWidth:Int
			Local preferredHeight:Int
			child.PreferredSize(contentWidth, Height(), preferredWidth, preferredHeight)
			naturalHeight :+ preferredHeight + child.marginTop + child.marginBottom
			visibleCount :+ 1
		Next
		If visibleCount > 1 Then naturalHeight :+ gap * (visibleCount - 1)
		contentExtent = naturalHeight
		maximumScroll = Max(contentExtent - Height(), 0)
		If scrollPosition > maximumScroll Then scrollPosition = maximumScroll
		If scrollPosition < 0 Then scrollPosition = 0

		Local cursor:Int = Y() + paddingTop - scrollPosition
		For Local child:TUIWidget = EachIn uiChildren
			If Not child.Visible() Then Continue
			Local preferredWidth:Int
			Local preferredHeight:Int
			child.PreferredSize(contentWidth, Height(), preferredWidth, preferredHeight)
			cursor :+ child.marginTop
			Local childWidth:Int = preferredWidth
			If child.alignSelf = UIAlignStretch Or child.requestedWidth = UILayoutFill Then ..
				childWidth = contentWidth - child.marginLeft - child.marginRight
			Local childX:Int = contentX + child.marginLeft
			If child.alignSelf = UIAlignCenter Then childX = contentX + (contentWidth - childWidth) / 2
			If child.alignSelf = UIAlignEnd Then ..
				childX = contentX + contentWidth - childWidth - child.marginRight
			child._SetBounds(childX, cursor, childWidth, preferredHeight)
			Local childContainer:TUIContainer = TUIContainer(child)
			If childContainer Then childContainer._LayoutChildren()
			cursor :+ preferredHeight + child.marginBottom + gap
		Next
	End Method
End Type

Type TUIList Extends TUIScrollView Final
	Public
	Field selectedItem:TUIListItem
	Field selectionHandler(list:TUIList)

	Public
	Method New()
		gap = 2
		SetPadding(2)
	End Method

	Method Item:TUIListItem(text:String = "")
		Local item:TUIListItem = New TUIListItem
		item.listOwner = Self
		item.SetText(text)
		Add(item)
		Return item
	End Method

	Method ItemCount:Int()
		Local count:Int
		For Local child:TUIWidget = EachIn uiChildren
			If TUIListItem(child) Then count :+ 1
		Next
		Return count
	End Method

	Method ItemAt:TUIListItem(index:Int)
		If index < 0 Then Return Null
		Local cursor:Int
		For Local child:TUIWidget = EachIn uiChildren
			Local item:TUIListItem = TUIListItem(child)
			If Not item Then Continue
			If cursor = index Then Return item
			cursor :+ 1
		Next
		Return Null
	End Method

	Method SelectedItem:TUIListItem()
		Return selectedItem
	End Method

	Method SelectedIndex:Int()
		If Not selectedItem Then Return -1
		Local cursor:Int
		For Local child:TUIWidget = EachIn uiChildren
			Local item:TUIListItem = TUIListItem(child)
			If Not item Then Continue
			If item = selectedItem Then Return cursor
			cursor :+ 1
		Next
		Return -1
	End Method

	Method SetSelectedIndex(value:Int)
		_SetSelectedItem(ItemAt(value), False)
	End Method

	Method ClearSelection()
		_SetSelectedItem(Null, False)
	End Method

	Method MoveSelection:Int(delta:Int)
		If delta = 0 Or ItemCount() = 0 Then Return False
		Local index:Int = SelectedIndex()
		If index < 0 Then
			If delta < 0 Then index = ItemCount() - 1 Else index = 0
		Else
			index :+ delta
			If index < 0 Then index = 0
			If index >= ItemCount() Then index = ItemCount() - 1
		End If
		Local item:TUIListItem = ItemAt(index)
		If Not item Then Return False
		If item = selectedItem Then
			EnsureVisible(item)
			If Context() Then Context().SetFocus(item)
			Return False
		End If
		_SetSelectedItem(item, True)
		If Context() Then Context().SetFocus(item)
		Return True
	End Method

	Method OnSelectionChanged(handler(list:TUIList))
		selectionHandler = handler
	End Method

	Public
	Method _SelectItem(item:TUIListItem)
		_SetSelectedItem(item, True)
	End Method

	Method _SetSelectedItem(item:TUIListItem, notify:Int)
		If item And item.listOwner <> Self Then Return
		If selectedItem = item Then Return
		Local previous:TUIListItem = selectedItem
		selectedItem = item
		If previous Then previous._Invalidate()
		If selectedItem Then
			selectedItem._Invalidate()
			EnsureVisible(selectedItem)
		End If
		If notify Then
			If selectionHandler Then selectionHandler(Self)
			EmitEvent(CreateEvent(EVENT_UISELECTIONCHANGED, Self, SelectedIndex(), 0, 0, 0, selectedItem))
		End If
	End Method
End Type

Type TUIListItem Extends TUIWidget Final
	Public
	Field listOwner:TUIList
	Field itemText:String

	Public
	Method New()
		clickable = True
		focusable = True
	End Method

	Method SetText(text:String)
		If Not text Then text = ""
		If itemText = text Then Return
		_Invalidate()
		itemText = text
		_RequestLayout()
	End Method

	Method Text:String()
		Return itemText
	End Method

	Method Selected:Int()
		Return listOwner And listOwner.SelectedItem() = Self
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then
			If Not Enabled() Then Return Context().Theme().controlDisabled
			If Pressed() Then Return Context().Theme().controlPressed
			If Selected() Then Return Context().Theme().controlActive
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
			textWidth = style.font.TextWidth(itemText, style.fontScale)
		End If
		width = textWidth + style.paddingLeft + style.paddingRight
		height = lineHeight + style.paddingTop + style.paddingBottom
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
			graphics.DrawRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		End If
		If style.font And itemText.Length Then
			graphics.SetFont(style.font)
			graphics.SetColorValue(style.foreground)
			Local textHeight:Int = style.font.LineHeight() * style.fontScale
			graphics.DrawText(itemText, X() + style.paddingLeft, ..
				Y() + (Height() - textHeight) / 2, style.fontScale)
		End If
	End Method

	Public
	Method _Activate()
		If listOwner Then listOwner._SelectItem(Self)
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
			Local lineCount:Int = 1
			For Local index:Int = 0 Until labelText.length
				If labelText[index] = 10 Then lineCount :+ 1
			Next
			height = style.font.LineHeight() * style.fontScale * lineCount
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
		focusable = True
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
		focusable = True
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
		Local boxSize:Int = 16 * style.fontScale
		Local labelGap:Int = Max(style.fontScale * 4, 6)
		Local trailingPadding:Int = style.paddingRight
		If checkText.Length Then trailingPadding = Max(trailingPadding, labelGap)
		width = boxSize + style.paddingLeft + trailingPadding
		If checkText.Length Then width :+ textWidth + labelGap
		height = Max(lineHeight, boxSize) + style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local contentHeight:Int = Height() - style.paddingTop - style.paddingBottom
		Local naturalBoxSize:Int = 16 * style.fontScale
		Local boxSize:Int = Max(Min(contentHeight, naturalBoxSize), 8)
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
		focusable = True
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
		focusable = True
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
		_SetUserValue(value)
	End Method

	Method _SetUserValue(value:Int)
		If value < minimumValue Then value = minimumValue
		If value > maximumValue Then value = maximumValue
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
	Field focusedWidget:TUIWidget
	Field pressedContact:Int = -1
	Field pressedArmed:Int
	Field touchScroll:TUIScrollView
	Field touchStartY:Int
	Field touchLastY:Int
	Field touchScrolled:Int
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
		focusedWidget = Null
		touchScroll = Null
		pressedContact = -1
	End Method

	Method Root:TUIColumn()
		Return rootWidget
	End Method

	Method Theme:TUITheme()
		Return themeValue
	End Method

	Method FocusedWidget:TUIWidget()
		Return focusedWidget
	End Method

	Method SetFocus:Int(widget:TUIWidget)
		If widget And (widget.Context() <> Self Or Not _CanFocus(widget)) Then Return False
		If focusedWidget = widget Then Return True
		Local previous:TUIWidget = focusedWidget
		focusedWidget = widget
		If previous Then previous._Invalidate()
		If focusedWidget Then focusedWidget._Invalidate()
		If focusedWidget Then _EnsureWidgetVisible(focusedWidget)
		EmitEvent(CreateEvent(EVENT_UIFOCUSCHANGED, focusedWidget, 0, 0, 0, 0, previous))
		Return True
	End Method

	Method ClearFocus()
		SetFocus(Null)
	End Method

	Method FocusNext:Int()
		Local count:Int = _CountFocusable(rootWidget)
		If count <= 0 Then Return False
		Local cursor:Int
		Local index:Int = _FocusableIndex(rootWidget, focusedWidget, cursor)
		Local nextIndex:Int
		If index < 0 Then nextIndex = 0 Else nextIndex = (index + 1) Mod count
		cursor = 0
		Return SetFocus(_FocusableAt(rootWidget, nextIndex, cursor))
	End Method

	Method FocusPrevious:Int()
		Local count:Int = _CountFocusable(rootWidget)
		If count <= 0 Then Return False
		Local cursor:Int
		Local index:Int = _FocusableIndex(rootWidget, focusedWidget, cursor)
		Local previousIndex:Int
		If index < 0 Then previousIndex = count - 1 Else previousIndex = (index + count - 1) Mod count
		cursor = 0
		Return SetFocus(_FocusableAt(rootWidget, previousIndex, cursor))
	End Method

	Method ActivateFocused:Int()
		Local target:TUIWidget = focusedWidget
		If Not _CanFocus(target) Then Return False
		Local button:TUIButton = TUIButton(target)
		If button Then
			button._Activate()
			EmitEvent(CreateEvent(EVENT_UIACTION, target))
			Return True
		End If
		Local checkBox:TUICheckBox = TUICheckBox(target)
		If checkBox Then
			checkBox._Activate()
			Return True
		End If
		Local switchControl:TUISwitch = TUISwitch(target)
		If switchControl Then
			switchControl._Activate()
			Return True
		End If
		Local listItem:TUIListItem = TUIListItem(target)
		If listItem Then
			listItem._Activate()
			Return True
		End If
		Return False
	End Method

	Method AdjustFocused:Int(delta:Int)
		If delta = 0 Or Not _CanFocus(focusedWidget) Then Return False
		Local slider:TUISlider = TUISlider(focusedWidget)
		If slider Then
			slider._SetUserValue(slider.Value() + delta)
			Return True
		End If
		Local listItem:TUIListItem = TUIListItem(focusedWidget)
		If listItem And listItem.listOwner Then Return listItem.listOwner.MoveSelection(delta)
		Return False
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
		_UpdateScrollMomentum(rootWidget, UInt(MilliSecs()))
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
				If pressedContact >= 0 Or Not event.source Then Return
				Local target:TUIWidget = HitTest(x, y)
				touchScroll = _ContainingScroll(target)
				If Not touchScroll Then touchScroll = _ScrollAt(rootWidget, x, y)
				If Not target And Not touchScroll Then Return
				pressedContact = event.data
				touchStartY = y
				touchLastY = y
				touchScrolled = False
				If touchScroll Then touchScroll._BeginDrag(UInt(MilliSecs()))
				If target And target.Enabled() Then
					SetFocus(target)
					pressedWidget = target
					pressedArmed = True
					target._SetPressed(True)
					Local slider:TUISlider = TUISlider(target)
					If slider Then slider._TrackPointer(x)
				End If
			Case EVENT_TOUCHMOVE
				If pressedContact = event.data Then
					If touchScroll And (touchScrolled Or Abs(y - touchStartY) >= UIScrollDragThreshold) Then
						If Not touchScrolled Then
							touchScrolled = True
							pressedArmed = False
							If pressedWidget Then pressedWidget._SetPressed(False)
						End If
						Local now:UInt = UInt(MilliSecs())
						touchScroll._DragBy(touchLastY - y, now)
						touchLastY = y
					Else If pressedWidget Then
						Local slider:TUISlider = TUISlider(pressedWidget)
						If slider Then
							slider._TrackPointer(x)
						Else
							pressedArmed = pressedWidget.Contains(x, y)
							pressedWidget._SetPressed(pressedArmed)
						End If
					End If
				End If
			Case EVENT_TOUCHUP
				If pressedContact = event.data Then
					If touchScroll Then touchScroll._EndDrag(UInt(MilliSecs()))
					Local target:TUIWidget = pressedWidget
					Local activate:Int
					If target Then
						Local slider:TUISlider = TUISlider(target)
						If slider And Not touchScrolled Then slider._TrackPointer(x)
						activate = Not touchScrolled And pressedArmed And target.Contains(x, y) And target.Enabled()
						target._SetPressed(False)
					End If
					pressedWidget = Null
					pressedContact = -1
					pressedArmed = False
					touchScroll = Null
					touchScrolled = False
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
								If switchControl Then
									switchControl._Activate()
								Else
									Local listItem:TUIListItem = TUIListItem(target)
									If listItem Then listItem._Activate()
								End If
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
		If widget.ClipsChildren() Then
			Local childX:Int = Max(clipX, widget.X())
			Local childY:Int = Max(clipY, widget.Y())
			Local childX1:Int = Min(clipX + clipWidth, widget.X() + widget.Width())
			Local childY1:Int = Min(clipY + clipHeight, widget.Y() + widget.Height())
			If childX < childX1 And childY < childY1 Then
				graphics.PushState()
				graphics.SetViewport(childX, childY, childX1 - childX, childY1 - childY)
				For Local child:TUIWidget = EachIn widget.uiChildren
					_DrawWidget(child, childX, childY, childX1 - childX, childY1 - childY)
				Next
				graphics.PopState()
			End If
		Else
			For Local child:TUIWidget = EachIn widget.uiChildren
				_DrawWidget(child, clipX, clipY, clipWidth, clipHeight)
			Next
		End If
		widget.DrawOverlay(graphics)
		If widget = focusedWidget Then _DrawFocus(widget)
	End Method

	Method _EnsureWidgetVisible(widget:TUIWidget)
		If Not widget Then Return
		If layoutPending Then Layout()
		Local parent:TUIContainer = widget.Parent()
		While parent
			Local scroll:TUIScrollView = TUIScrollView(parent)
			If scroll And scroll.EnsureVisible(widget) Then Layout()
			parent = parent.Parent()
		Wend
	End Method

	Method _ContainingScroll:TUIScrollView(widget:TUIWidget)
		Local current:TUIWidget = widget
		While current
			Local scroll:TUIScrollView = TUIScrollView(current)
			If scroll Then Return scroll
			current = current.Parent()
		Wend
		Return Null
	End Method

	Method _ScrollAt:TUIScrollView(widget:TUIWidget, x:Int, y:Int)
		If Not widget Or Not widget.Visible() Or Not widget.Contains(x, y) Then Return Null
		For Local index:Int = widget.uiChildren.Length - 1 To 0 Step -1
			Local found:TUIScrollView = _ScrollAt(widget.uiChildren[index], x, y)
			If found Then Return found
		Next
		Return TUIScrollView(widget)
	End Method

	Method _UpdateScrollMomentum(widget:TUIWidget, now:UInt)
		If Not widget Or Not widget.Visible() Then Return
		Local scroll:TUIScrollView = TUIScrollView(widget)
		If scroll Then scroll._UpdateMomentum(now)
		For Local child:TUIWidget = EachIn widget.uiChildren
			_UpdateScrollMomentum(child, now)
		Next
	End Method

	Method _DrawFocus(widget:TUIWidget)
		If Not themeValue Or themeValue.focusWidth <= 0 Then Return
		Local inset:Int = Max(themeValue.focusInset, 0)
		Local width:Int = widget.Width() - inset * 2
		Local height:Int = widget.Height() - inset * 2
		If width <= 0 Or height <= 0 Then Return
		graphics.SetColorValue(themeValue.focusColor)
		For Local edge:Int = 0 Until themeValue.focusWidth
			If width - edge * 2 <= 0 Or height - edge * 2 <= 0 Then Exit
			graphics.DrawRoundRect(widget.X() + inset + edge, widget.Y() + inset + edge, ..
				width - edge * 2, height - edge * 2, Max(4 - edge, 0))
		Next
	End Method

	Method _CanFocus:Int(widget:TUIWidget)
		If Not widget Or Not widget.Focusable() Or Not widget.Enabled() Or Not widget.Visible() Then Return False
		Local parent:TUIContainer = widget.Parent()
		While parent
			If Not parent.Enabled() Or Not parent.Visible() Then Return False
			parent = parent.Parent()
		Wend
		Return True
	End Method

	Method _ReleaseFocus(widget:TUIWidget)
		If Not focusedWidget Or Not widget Then Return
		Local current:TUIWidget = focusedWidget
		While current
			If current = widget Then
				ClearFocus()
				Return
			End If
			current = current.Parent()
		Wend
	End Method

	Method _CountFocusable:Int(widget:TUIWidget)
		If Not widget Or Not widget.Visible() Or Not widget.Enabled() Then Return 0
		Local count:Int
		If widget.Focusable() Then count = 1
		For Local child:TUIWidget = EachIn widget.uiChildren
			count :+ _CountFocusable(child)
		Next
		Return count
	End Method

	Method _FocusableAt:TUIWidget(widget:TUIWidget, targetIndex:Int, cursor:Int Var)
		If Not widget Or Not widget.Visible() Or Not widget.Enabled() Then Return Null
		If widget.Focusable() Then
			If cursor = targetIndex Then Return widget
			cursor :+ 1
		End If
		For Local child:TUIWidget = EachIn widget.uiChildren
			Local found:TUIWidget = _FocusableAt(child, targetIndex, cursor)
			If found Then Return found
		Next
		Return Null
	End Method

	Method _FocusableIndex:Int(widget:TUIWidget, target:TUIWidget, cursor:Int Var)
		If Not widget Or Not widget.Visible() Or Not widget.Enabled() Then Return -1
		If widget.Focusable() Then
			If widget = target Then Return cursor
			cursor :+ 1
		End If
		For Local child:TUIWidget = EachIn widget.uiChildren
			Local found:Int = _FocusableIndex(child, target, cursor)
			If found >= 0 Then Return found
		Next
		Return -1
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
