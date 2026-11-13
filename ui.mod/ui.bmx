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
Import Embedded.Drivers.Display.Image
Import Embedded.Drivers.Touch
Import Embedded.Graphics2D
Import "native/ui_math.c"

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
Const UIToastInfo:Int = 0
Const UIToastSuccess:Int = 1
Const UIToastWarning:Int = 2
Const UIToastError:Int = 3
Const UIToastDefaultDuration:Int = 2500
Const UIToastQueueMaximum:Int = 8
Const UIPageStackMaximum:Int = 16
Const UIToastTopLeft:Int = 0
Const UIToastTopCenter:Int = 1
Const UIToastTopRight:Int = 2
Const UIToastCenterLeft:Int = 3
Const UIToastCenter:Int = 4
Const UIToastCenterRight:Int = 5
Const UIToastBottomLeft:Int = 6
Const UIToastBottomCenter:Int = 7
Const UIToastBottomRight:Int = 8
Const UIGaugeSweepDegrees:Int = 270
Const UIGaugeStartDegrees:Int = 135
Const UIDialDragHorizontal:Int = 0
Const UIDialDragVertical:Int = 1

Global EVENT_UIACTION:Int = AllocUserEventId("UIAction")
Global EVENT_UIVALUECHANGED:Int = AllocUserEventId("UIValueChanged")
Global EVENT_UIFOCUSCHANGED:Int = AllocUserEventId("UIFocusChanged")
Global EVENT_UISELECTIONCHANGED:Int = AllocUserEventId("UISelectionChanged")
Global EVENT_UIPAGECHANGED:Int = AllocUserEventId("UIPageChanged")

Extern "C"
	Function _UISin:Double(degrees:Double) = "bmx_ui_sin"
	Function _UICos:Double(degrees:Double) = "bmx_ui_cos"
End Extern

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

Function _UIRounded:Int(value:Double)
	If value >= 0.0 Then Return Int(value + 0.5)
	Return Int(value - 0.5)
End Function

Function _UIDrawArc(graphics:TEmbedded2DContext, centerX:Int, centerY:Int, radius:Int, ..
		startDegrees:Int, sweepDegrees:Int, width:Int)
	If Not graphics Or radius <= 0 Or sweepDegrees = 0 Then Return
	If width < 1 Then width = 1
	If width > radius Then width = radius
	Local segmentCount:Int = Max(Abs(sweepDegrees) / 5, 1)
	For Local ring:Int = 0 Until width
		Local ringRadius:Int = radius - ring
		Local previousX:Int = centerX + _UIRounded(_UICos(Double(startDegrees)) * Double(ringRadius))
		Local previousY:Int = centerY + _UIRounded(_UISin(Double(startDegrees)) * Double(ringRadius))
		For Local segment:Int = 1 To segmentCount
			Local angle:Double = Double(startDegrees) + ..
				Double(sweepDegrees) * Double(segment) / Double(segmentCount)
			Local x:Int = centerX + _UIRounded(_UICos(angle) * Double(ringRadius))
			Local y:Int = centerY + _UIRounded(_UISin(angle) * Double(ringRadius))
			graphics.DrawLine(previousX, previousY, x, y)
			previousX = x
			previousY = y
		Next
	Next
End Function

Function _UIDrawImageRect(graphics:TEmbedded2DContext, image:TEmbeddedImage, ..
		x:Int, y:Int, width:Int, height:Int)
	If graphics And image And width > 0 And height > 0 Then ..
		graphics.DrawImageRect(image, x, y, width, height)
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
	Field focusIndicatorVisible:Int = True

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

	Rem
	bbdoc: Controls whether this widget draws the theme focus indicator.
	about: Hiding the indicator does not remove the widget from focus traversal.
	End Rem
	Method SetFocusIndicatorVisible(value:Int)
		value = value <> 0
		If focusIndicatorVisible = value Then Return
		focusIndicatorVisible = value
		_Invalidate()
	End Method

	Method FocusIndicatorVisible:Int()
		Return focusIndicatorVisible
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
		Local container:TUIContainer = TUIContainer(Self)
		If container Then
			For Local child:TUIWidget = EachIn uiChildren
				child._Attach(context, container)
			Next
		End If
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

	Method TabView:TUITabView() Final
		Local widget:TUITabView = New TUITabView
		Add(widget)
		Return widget
	End Method

	Method PageStack:TUIPageStack() Final
		Local widget:TUIPageStack = New TUIPageStack
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

	Method ComboBox:TUIComboBox() Final
		Local widget:TUIComboBox = New TUIComboBox
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

	Method RadioGroup:TUIRadioGroup() Final
		Local widget:TUIRadioGroup = New TUIRadioGroup
		Add(widget)
		Return widget
	End Method

	Method Stepper:TUIStepper(minimum:Int = 0, maximum:Int = 100, value:Int = 0, step:Int = 1) Final
		Local widget:TUIStepper = New TUIStepper
		widget.SetRange(minimum, maximum)
		widget.SetStep(step)
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Method DecimalStepper:TUIStepper(minimum:Double = 0.0, maximum:Double = 100.0, ..
			value:Double = 0.0, step:Double = 1.0, decimalPlaces:Int = 1) Final
		Local widget:TUIStepper = New TUIStepper
		widget.ConfigureDecimal(minimum, maximum, value, step, decimalPlaces)
		Add(widget)
		Return widget
	End Method

	Method SegmentedControl:TUISegmentedControl() Final
		Local widget:TUISegmentedControl = New TUISegmentedControl
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

	Method StatusIndicator:TUIStatusIndicator(text:String = "", active:Int = False) Final
		Local widget:TUIStatusIndicator = New TUIStatusIndicator
		widget.SetText(text)
		widget.SetActive(active)
		Add(widget)
		Return widget
	End Method

	Method ArcGauge:TUIArcGauge(minimum:Int = 0, maximum:Int = 100, value:Int = 0) Final
		Local widget:TUIArcGauge = New TUIArcGauge
		widget.SetRange(minimum, maximum)
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Method Sparkline:TUISparkline(capacity:Int = 32) Final
		Local widget:TUISparkline = New TUISparkline
		widget.SetCapacity(capacity)
		Add(widget)
		Return widget
	End Method

	Method RotaryDial:TUIRotaryDial(minimum:Int = 0, maximum:Int = 100, value:Int = 0) Final
		Local widget:TUIRotaryDial = New TUIRotaryDial
		widget.SetRange(minimum, maximum)
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local contentWidth:Int
		Local contentHeight:Int
		Local visibleCount:Int
		Local childAvailableWidth:Int = Max(availableWidth - paddingLeft - paddingRight, 0)
		Local childAvailableHeight:Int = Max(availableHeight - paddingTop - paddingBottom, 0)
		For Local child:TUIWidget = EachIn uiChildren
			If Not child.Visible() Then Continue
			Local childWidth:Int
			Local childHeight:Int
			child.PreferredSize(childAvailableWidth, childAvailableHeight, childWidth, childHeight)
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

Type TUIList Extends TUIScrollView
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

Type TUIPopupMenu Extends TUIList
	Public
	Field comboOwner:TUIComboBox

	Public
	Method New()
		Super.New()
		SetBackgroundVisible(True)
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then Return Context().Theme().control
		Return Super.DefaultStyle()
	End Method

	Method _SelectItem(item:TUIListItem) Override
		If comboOwner Then
			_SetSelectedItem(item, False)
			comboOwner._SelectFromPopup(SelectedIndex())
		Else
			Super._SelectItem(item)
		End If
		If Context() Then Context().DismissOverlay()
	End Method
End Type

Type TUIComboBox Extends TUIWidget Final
	Private
	Field itemNames:String[] = New String[0]
	Field selectedIndex:Int = -1
	Field popup:TUIPopupMenu
	Field changeHandler(combo:TUIComboBox)

	Public
	Method New()
		clickable = True
		focusable = True
	End Method

	Method AddItem:Int(text:String)
		If Not text Then text = ""
		itemNames = itemNames[..itemNames.Length + 1]
		itemNames[itemNames.Length - 1] = text
		If popup Then popup.Item(text)
		If selectedIndex < 0 Then selectedIndex = 0
		_RequestLayout()
		Return itemNames.Length - 1
	End Method

	Method ItemCount:Int()
		Return itemNames.Length
	End Method

	Method ItemText:String(index:Int)
		If index < 0 Or index >= itemNames.Length Then Return ""
		Return itemNames[index]
	End Method

	Method SelectedIndex:Int()
		Return selectedIndex
	End Method

	Method SelectedText:String()
		Return ItemText(selectedIndex)
	End Method

	Method ActivePopup:TUIPopupMenu()
		If Context() And Context().ActiveOverlay() = popup Then Return popup
		Return Null
	End Method

	Method SetSelectedIndex(value:Int)
		_SetSelectedIndex(value, False)
	End Method

	Method OnChange(handler(combo:TUIComboBox))
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
		Local textWidth:Int
		Local lineHeight:Int = 16
		If style.font Then
			lineHeight = style.font.LineHeight() * style.fontScale
			For Local text:String = EachIn itemNames
				Local candidate:Int = style.font.TextWidth(text, style.fontScale)
				If candidate > textWidth Then textWidth = candidate
			Next
		End If
		width = textWidth + lineHeight + style.paddingLeft + style.paddingRight
		height = lineHeight + style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		graphics.SetColorValue(style.background)
		If style.cornerRadius > 0 Then
			graphics.FillRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		Else
			graphics.FillRect(X(), Y(), Width(), Height())
		End If
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			graphics.DrawRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		End If
		If style.font Then
			graphics.SetFont(style.font)
			graphics.SetColorValue(style.foreground)
			Local textHeight:Int = style.font.LineHeight() * style.fontScale
			graphics.DrawText(SelectedText(), X() + style.paddingLeft, ..
				Y() + (Height() - textHeight) / 2, style.fontScale)
		End If
		Local arrowSize:Int = Max(Height() / 6, 3)
		Local arrowX:Int = X() + Width() - style.paddingRight - arrowSize
		Local arrowY:Int = Y() + Height() / 2
		graphics.SetColorValue(style.foreground)
		graphics.DrawLine(arrowX - arrowSize, arrowY - arrowSize / 2, arrowX, arrowY + arrowSize / 2)
		graphics.DrawLine(arrowX, arrowY + arrowSize / 2, arrowX + arrowSize, arrowY - arrowSize / 2)
	End Method

	Public
	Method _Activate()
		If Not Context() Or itemNames.Length = 0 Then Return
		If popup And Context().ActiveOverlay() = popup Then
			Context().DismissOverlay()
			Return
		End If
		If Not popup Then
			popup = New TUIPopupMenu
			popup.comboOwner = Self
			For Local text:String = EachIn itemNames
				popup.Item(text)
			Next
		End If
		popup.SetSelectedIndex(selectedIndex)
		If Context().ShowOverlay(popup, X(), Y() + Height(), Width()) Then
			Local item:TUIListItem = popup.ItemAt(selectedIndex)
			If item Then Context().SetFocus(item)
		End If
	End Method

	Method _SelectFromPopup(index:Int)
		_SetSelectedIndex(index, True)
	End Method

	Method _SetSelectedIndex(value:Int, notify:Int)
		If itemNames.Length = 0 Then value = -1
		If value < -1 Then value = -1
		If value >= itemNames.Length Then value = itemNames.Length - 1
		If selectedIndex = value Then Return
		selectedIndex = value
		_Invalidate()
		If notify Then
			If changeHandler Then changeHandler(Self)
			EmitEvent(CreateEvent(EVENT_UISELECTIONCHANGED, Self, selectedIndex))
		End If
	End Method
End Type

Rem
bbdoc: One retained page owned by a TUIPageStack.
End Rem
Type TUIPage Extends TUIContainer Final
	Public
	Field pageOwner:TUIPageStack
	Field pageName:String

	Public
	Method New()
		layoutDirection = 2
	End Method

	Method SetName(name:String)
		If Not name Then name = ""
		pageName = name
	End Method

	Method Name:String()
		Return pageName
	End Method
End Type

Rem
bbdoc: Retained last-in, first-out navigation container.
about: Pages remain allocated while hidden. Push and Pop preserve the previous
page's focused widget so non-touch navigation resumes where the user left it.
End Rem
Type TUIPageStack Extends TUIContainer Final
	Private
	Field navigationPages:TUIPage[] = New TUIPage[0]
	Field pageHistory:TUIPage[UIPageStackMaximum]
	Field focusHistory:TUIWidget[UIPageStackMaximum]
	Field historyDepth:Int
	Field changeHandler(stack:TUIPageStack)

	Public
	Method New()
		layoutDirection = 0
	End Method

	Method Page:TUIPage(name:String = "")
		Local page:TUIPage = New TUIPage
		page.pageOwner = Self
		page.SetName(name)
		page.SetVisible(False)
		navigationPages = navigationPages[..navigationPages.Length + 1]
		navigationPages[navigationPages.Length - 1] = page
		Add(page)
		If historyDepth = 0 Then Push(page)
		Return page
	End Method

	Method PageCount:Int()
		Return navigationPages.Length
	End Method

	Method PageAt:TUIPage(index:Int)
		If index < 0 Or index >= navigationPages.Length Then Return Null
		Return navigationPages[index]
	End Method

	Method Depth:Int()
		Return historyDepth
	End Method

	Method CurrentPage:TUIPage()
		If historyDepth = 0 Then Return Null
		Return pageHistory[historyDepth - 1]
	End Method

	Method CanPop:Int()
		Return historyDepth > 1
	End Method

	Method OnPageChanged(handler(stack:TUIPageStack))
		changeHandler = handler
	End Method

	Method Push:Int(page:TUIPage)
		If Not page Or page.pageOwner <> Self Or page = CurrentPage() Or ..
				historyDepth >= UIPageStackMaximum Then Return False
		For Local index:Int = 0 Until historyDepth
			If pageHistory[index] = page Then Return False
		Next
		Local previous:TUIPage = CurrentPage()
		If previous Then
			focusHistory[historyDepth - 1] = _FocusedDescendant(previous)
			previous.SetVisible(False)
		End If
		pageHistory[historyDepth] = page
		focusHistory[historyDepth] = Null
		historyDepth :+ 1
		page.SetVisible(True)
		_RequestLayout()
		_NotifyChanged()
		Return True
	End Method

	Method Pop:Int()
		If historyDepth <= 1 Then Return False
		Local outgoing:TUIPage = CurrentPage()
		outgoing.SetVisible(False)
		historyDepth :- 1
		pageHistory[historyDepth] = Null
		focusHistory[historyDepth] = Null
		Local incoming:TUIPage = CurrentPage()
		incoming.SetVisible(True)
		_RequestLayout()
		If Context() Then
			Local restore:TUIWidget = focusHistory[historyDepth - 1]
			If restore Then Context().DeferFocus(restore)
		End If
		_NotifyChanged()
		Return True
	End Method

	Method Replace:Int(page:TUIPage)
		If Not page Or page.pageOwner <> Self Or page = CurrentPage() Then Return False
		For Local index:Int = 0 Until historyDepth - 1
			If pageHistory[index] = page Then Return False
		Next
		If historyDepth = 0 Then Return Push(page)
		CurrentPage().SetVisible(False)
		pageHistory[historyDepth - 1] = page
		focusHistory[historyDepth - 1] = Null
		page.SetVisible(True)
		_RequestLayout()
		_NotifyChanged()
		Return True
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local page:TUIPage = CurrentPage()
		If page Then page.PreferredSize(availableWidth, availableHeight, width, height)
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Public
	Method _LayoutChildren() Override
		Local page:TUIPage = CurrentPage()
		If Not page Then Return
		page._SetBounds(X() + paddingLeft, Y() + paddingTop, ..
			Max(Width() - paddingLeft - paddingRight, 0), ..
			Max(Height() - paddingTop - paddingBottom, 0))
		page._LayoutChildren()
	End Method

	Private
	Method _FocusedDescendant:TUIWidget(page:TUIPage)
		If Not Context() Then Return Null
		Local widget:TUIWidget = Context().FocusedWidget()
		Local current:TUIWidget = widget
		While current
			If current = page Then Return widget
			current = current.Parent()
		Wend
		Return Null
	End Method

	Method _NotifyChanged()
		_Invalidate()
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIPAGECHANGED, Self, Depth()))
	End Method
End Type

Type TUITabPage Extends TUIContainer Final
	Public
	Method New()
		layoutDirection = 2
	End Method
End Type

Type TUITabButton Extends TUIWidget Final
	Public
	Field tabOwner:TUITabView
	Field tabIndex:Int
	Field tabText:String

	Public
	Method New()
		clickable = True
		focusable = True
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then
			If Not Enabled() Then Return Context().Theme().buttonDisabled
			If Pressed() Then Return Context().Theme().buttonPressed
			If tabOwner And tabOwner.SelectedIndex() = tabIndex Then Return Context().Theme().controlActive
			Return Context().Theme().button
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
			textWidth = style.font.TextWidth(tabText, style.fontScale)
		End If
		width = textWidth + style.paddingLeft + style.paddingRight
		height = lineHeight + style.paddingTop + style.paddingBottom
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		graphics.SetColorValue(style.background)
		If style.cornerRadius > 0 Then
			graphics.FillRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		Else
			graphics.FillRect(X(), Y(), Width(), Height())
		End If
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			graphics.DrawRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		End If
		If style.font Then
			graphics.SetFont(style.font)
			graphics.SetColorValue(style.foreground)
			Local textWidth:Int = style.font.TextWidth(tabText, style.fontScale)
			Local textHeight:Int = style.font.LineHeight() * style.fontScale
			graphics.DrawText(tabText, X() + (Width() - textWidth) / 2, ..
				Y() + (Height() - textHeight) / 2, style.fontScale)
		End If
	End Method

	Method _Activate()
		If tabOwner Then tabOwner._SelectIndex(tabIndex, True)
	End Method
End Type

Type TUITabView Extends TUIContainer Final
	Public
	Field tabButtons:TUITabButton[] = New TUITabButton[0]
	Field tabPages:TUITabPage[] = New TUITabPage[0]
	Field selectedTab:Int = -1
	Field selectionHandler(tabView:TUITabView)

	Public
	Method New()
		gap = 3
	End Method

	Method Page:TUITabPage(title:String)
		Local button:TUITabButton = New TUITabButton
		button.tabOwner = Self
		button.tabIndex = tabButtons.Length
		button.tabText = title
		Local page:TUITabPage = New TUITabPage
		tabButtons = tabButtons[..tabButtons.Length + 1]
		tabPages = tabPages[..tabPages.Length + 1]
		tabButtons[tabButtons.Length - 1] = button
		tabPages[tabPages.Length - 1] = page
		Add(button)
		Add(page)
		If selectedTab < 0 Then
			selectedTab = 0
		Else
			page.SetVisible(False)
		End If
		Return page
	End Method

	Method PageCount:Int()
		Return tabPages.Length
	End Method

	Method PageAt:TUITabPage(index:Int)
		If index < 0 Or index >= tabPages.Length Then Return Null
		Return tabPages[index]
	End Method

	Method TabButtonAt:TUITabButton(index:Int)
		If index < 0 Or index >= tabButtons.Length Then Return Null
		Return tabButtons[index]
	End Method

	Method SelectedIndex:Int()
		Return selectedTab
	End Method

	Method SelectedPage:TUITabPage()
		Return PageAt(selectedTab)
	End Method

	Method SetSelectedIndex(value:Int)
		_SelectIndex(value, False)
	End Method

	Method OnSelectionChanged(handler(tabView:TUITabView))
		selectionHandler = handler
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local headerWidth:Int
		Local headerHeight:Int
		For Local button:TUITabButton = EachIn tabButtons
			Local itemWidth:Int
			Local itemHeight:Int
			button.PreferredSize(availableWidth, availableHeight, itemWidth, itemHeight)
			headerWidth :+ itemWidth
			If itemHeight > headerHeight Then headerHeight = itemHeight
		Next
		If tabButtons.Length > 1 Then headerWidth :+ gap * (tabButtons.Length - 1)
		Local pageWidth:Int
		Local pageHeight:Int
		For Local page:TUITabPage = EachIn tabPages
			Local itemWidth:Int
			Local itemHeight:Int
			page.PreferredSize(availableWidth, availableHeight, itemWidth, itemHeight)
			If itemWidth > pageWidth Then pageWidth = itemWidth
			If itemHeight > pageHeight Then pageHeight = itemHeight
		Next
		width = Max(headerWidth, pageWidth) + paddingLeft + paddingRight
		height = headerHeight + pageHeight + paddingTop + paddingBottom
		If headerHeight > 0 And pageHeight > 0 Then height :+ gap
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Public
	Method _SelectIndex(value:Int, notify:Int)
		If value < 0 Or value >= tabPages.Length Or selectedTab = value Then Return
		Local previous:Int = selectedTab
		selectedTab = value
		If previous >= 0 Then tabPages[previous].SetVisible(False)
		tabPages[selectedTab].SetVisible(True)
		_Invalidate()
		_RequestLayout()
		If notify Then
			If selectionHandler Then selectionHandler(Self)
			EmitEvent(CreateEvent(EVENT_UISELECTIONCHANGED, Self, selectedTab))
		End If
	End Method

	Method _LayoutChildren() Override
		Local contentX:Int = X() + paddingLeft
		Local contentY:Int = Y() + paddingTop
		Local contentWidth:Int = Max(Width() - paddingLeft - paddingRight, 0)
		Local contentHeight:Int = Max(Height() - paddingTop - paddingBottom, 0)
		Local headerHeight:Int
		For Local button:TUITabButton = EachIn tabButtons
			Local itemWidth:Int
			Local itemHeight:Int
			button.PreferredSize(contentWidth, contentHeight, itemWidth, itemHeight)
			If itemHeight > headerHeight Then headerHeight = itemHeight
		Next
		Local buttonCount:Int = tabButtons.Length
		Local buttonWidth:Int
		If buttonCount > 0 Then buttonWidth = Max((contentWidth - gap * (buttonCount - 1)) / buttonCount, 0)
		Local cursorX:Int = contentX
		For Local button:TUITabButton = EachIn tabButtons
			button._SetBounds(cursorX, contentY, buttonWidth, headerHeight)
			cursorX :+ buttonWidth + gap
		Next
		Local pageY:Int = contentY + headerHeight
		If headerHeight > 0 Then pageY :+ gap
		Local pageHeight:Int = Max(contentY + contentHeight - pageY, 0)
		For Local page:TUITabPage = EachIn tabPages
			page._SetBounds(contentX, pageY, contentWidth, pageHeight)
			If page.Visible() Then page._LayoutChildren()
		Next
	End Method
End Type

Type TUILabel Extends TUIWidget Final
	Public
	Field labelText:String

	Private
	Field wordWrap:Int
	Field wrappedLines:String[] = New String[0]
	Field wrappedWidth:Int = -1
	Field wrappedFont:TBitmapFont
	Field wrappedScale:Int

	Public
	Method SetText(text:String)
		If Not text Then text = ""
		If labelText = text Then Return
		_Invalidate()
		labelText = text
		wrappedWidth = -1
		_RequestLayout()
	End Method

	Method Text:String()
		Return labelText
	End Method

	Method SetWordWrap(value:Int)
		value = value <> 0
		If wordWrap = value Then Return
		wordWrap = value
		wrappedWidth = -1
		_RequestLayout()
		_Invalidate()
	End Method

	Method WordWrap:Int()
		Return wordWrap
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
			If wordWrap Then
				Local contentWidth:Int = availableWidth - style.paddingLeft - style.paddingRight
				If requestedWidth >= 0 Then contentWidth = requestedWidth - style.paddingLeft - style.paddingRight
				If contentWidth < 1 Then contentWidth = 1
				_Wrap(contentWidth, style)
				For Local line:String = EachIn wrappedLines
					width = Max(width, style.font.TextWidth(line, style.fontScale))
				Next
				height = style.font.LineHeight() * style.fontScale * Max(wrappedLines.Length, 1)
			Else
				width = style.font.TextWidth(labelText, style.fontScale)
				Local lineCount:Int = 1
				For Local index:Int = 0 Until labelText.length
					If labelText[index] = 10 Then lineCount :+ 1
				Next
				height = style.font.LineHeight() * style.fontScale * lineCount
			End If
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
		If wordWrap Then
			Local contentWidth:Int = Max(Width() - style.paddingLeft - style.paddingRight, 1)
			_Wrap(contentWidth, style)
			Local y:Int = Y() + style.paddingTop
			Local lineHeight:Int = style.font.LineHeight() * style.fontScale
			For Local line:String = EachIn wrappedLines
				graphics.DrawText(line, X() + style.paddingLeft, y, style.fontScale)
				y :+ lineHeight
			Next
		Else
			graphics.DrawText(labelText, X() + style.paddingLeft, Y() + style.paddingTop, style.fontScale)
		End If
	End Method

	Private
	Method _Wrap(maxWidth:Int, style:TUIStyle)
		If wrappedWidth = maxWidth And wrappedFont = style.font And wrappedScale = style.fontScale Then Return
		wrappedWidth = maxWidth
		wrappedFont = style.font
		wrappedScale = style.fontScale
		wrappedLines = New String[0]
		Local line:String
		Local word:String
		For Local index:Int = 0 To labelText.Length
			Local character:Int = 10
			If index < labelText.Length Then character = labelText[index]
			If character = 32 Or character = 10 Then
				If word.Length Then
					Local candidate:String = word
					If line.Length Then candidate = line + " " + word
					If line.Length And style.font.TextWidth(candidate, style.fontScale) > maxWidth Then
						_AppendWrappedLine(line)
						line = word
					Else
						line = candidate
					End If
					word = ""
				End If
				If character = 10 Then
					_AppendWrappedLine(line)
					line = ""
				End If
			Else
				word :+ Chr(character)
			End If
		Next
		If wrappedLines.Length = 0 Then _AppendWrappedLine("")
	End Method

	Method _AppendWrappedLine(line:String)
		wrappedLines = wrappedLines[..wrappedLines.Length + 1]
		wrappedLines[wrappedLines.Length - 1] = line
	End Method
End Type

Type TUIButton Extends TUIWidget
	Public
	Field buttonText:String
	Field clickHandler(button:TUIButton)
	Field normalImage:TEmbeddedImage
	Field pressedImage:TEmbeddedImage
	Field disabledImage:TEmbeddedImage
	Field imageReplacesChrome:Int

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

	Rem
	bbdoc: Sets optional normal, pressed, and disabled button artwork.
	about: Missing state images fall back to the normal image. When replaceChrome
	is true the image replaces the themed background and border; button text is
	still drawn over it.
	End Rem
	Method SetStateImages(normal:TEmbeddedImage, pressed:TEmbeddedImage = Null, ..
			disabled:TEmbeddedImage = Null, replaceChrome:Int = True)
		normalImage = normal
		pressedImage = pressed
		disabledImage = disabled
		imageReplacesChrome = replaceChrome <> 0
		_Invalidate()
		_RequestLayout()
	End Method

	Method NormalImage:TEmbeddedImage()
		Return normalImage
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
		If normalImage Then
			If normalImage.Width() > width Then width = normalImage.Width()
			If normalImage.Height() > height Then height = normalImage.Height()
		End If
		width :+ style.paddingLeft + style.paddingRight
		height :+ style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local stateImage:TEmbeddedImage = normalImage
		If Not Enabled() And disabledImage Then
			stateImage = disabledImage
		Else If Pressed() And pressedImage Then
			stateImage = pressedImage
		End If
		If style.backgroundVisible And Not (stateImage And imageReplacesChrome) Then
			graphics.SetColorValue(style.background)
			If style.cornerRadius > 0 Then
				graphics.FillRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
			Else
				graphics.FillRect(X(), Y(), Width(), Height())
			End If
		End If
		If style.borderWidth > 0 And Not (stateImage And imageReplacesChrome) Then
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
		If stateImage Then _UIDrawImageRect(graphics, stateImage, X(), Y(), Width(), Height())
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

Type TUIRadioGroup Extends TUIContainer Final
	Private
	Field options:TUIRadioButton[] = New TUIRadioButton[0]
	Field selectedIndex:Int = -1
	Field selectionHandler(group:TUIRadioGroup)

	Public
	Method New()
		layoutDirection = 2
		gap = 2
	End Method

	Method Option:TUIRadioButton(text:String = "")
		Local option:TUIRadioButton = New TUIRadioButton
		option._Configure(Self, options.Length)
		option.SetText(text)
		options = options[..options.Length + 1]
		options[options.Length - 1] = option
		Add(option)
		If selectedIndex < 0 Then selectedIndex = 0
		Return option
	End Method

	Method OptionCount:Int()
		Return options.Length
	End Method

	Method OptionAt:TUIRadioButton(index:Int)
		If index < 0 Or index >= options.Length Then Return Null
		Return options[index]
	End Method

	Method SelectedIndex:Int()
		Return selectedIndex
	End Method

	Method SetSelectedIndex(value:Int)
		_SelectIndex(value, False)
	End Method

	Method OnSelectionChanged(handler(group:TUIRadioGroup))
		selectionHandler = handler
	End Method

	Public
	Method _SelectIndex(value:Int, notify:Int)
		If options.Length = 0 Then value = -1
		If value < -1 Then value = -1
		If value >= options.Length Then value = options.Length - 1
		If selectedIndex = value Then Return
		Local previous:Int = selectedIndex
		selectedIndex = value
		If previous >= 0 Then options[previous]._Invalidate()
		If selectedIndex >= 0 Then options[selectedIndex]._Invalidate()
		If notify Then
			If selectionHandler Then selectionHandler(Self)
			EmitEvent(CreateEvent(EVENT_UISELECTIONCHANGED, Self, selectedIndex))
		End If
	End Method
End Type

Type TUIRadioButton Extends TUIWidget Final
	Private
	Field radioText:String
	Field radioOwner:TUIRadioGroup
	Field radioIndex:Int

	Public
	Method _Configure(owner:TUIRadioGroup, index:Int)
		radioOwner = owner
		radioIndex = index
	End Method

	Method New()
		clickable = True
		focusable = True
	End Method

	Method SetText(text:String)
		If Not text Then text = ""
		If radioText = text Then Return
		radioText = text
		_Invalidate()
		_RequestLayout()
	End Method

	Method Text:String()
		Return radioText
	End Method

	Method Selected:Int()
		Return radioOwner And radioOwner.SelectedIndex() = radioIndex
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
			textWidth = style.font.TextWidth(radioText, style.fontScale)
		End If
		Local circleSize:Int = 16 * style.fontScale
		Local labelGap:Int = Max(style.fontScale * 4, 6)
		width = circleSize + labelGap + textWidth + style.paddingLeft + style.paddingRight
		height = Max(lineHeight, circleSize) + style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local diameter:Int = Max(Min(Height() - style.paddingTop - style.paddingBottom, ..
			16 * style.fontScale), 8)
		Local centerX:Int = X() + style.paddingLeft + diameter / 2
		Local centerY:Int = Y() + Height() / 2
		graphics.SetColorValue(style.border)
		graphics.FillCircle(centerX, centerY, diameter / 2)
		graphics.SetColorValue(style.background)
		graphics.FillCircle(centerX, centerY, Max(diameter / 2 - Max(style.borderWidth, 1), 1))
		If Selected() Then
			graphics.SetColorValue(style.foreground)
			graphics.FillCircle(centerX, centerY, Max(diameter / 5, 2))
		End If
		If style.font And radioText.Length Then
			graphics.SetFont(style.font)
			graphics.SetColorValue(style.foreground)
			Local textHeight:Int = style.font.LineHeight() * style.fontScale
			graphics.DrawText(radioText, centerX + diameter / 2 + Max(style.fontScale * 4, 6), ..
				Y() + (Height() - textHeight) / 2, style.fontScale)
		End If
	End Method

	Public
	Method _Activate()
		If radioOwner Then radioOwner._SelectIndex(radioIndex, True)
	End Method

	Method _Move(delta:Int)
		If Not radioOwner Or delta = 0 Then Return
		Local nextIndex:Int = radioOwner.SelectedIndex() + delta
		If nextIndex < 0 Then nextIndex = 0
		If nextIndex >= radioOwner.OptionCount() Then nextIndex = radioOwner.OptionCount() - 1
		radioOwner._SelectIndex(nextIndex, True)
		If Context() Then Context().SetFocus(radioOwner.OptionAt(nextIndex))
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

Type TUIStepper Extends TUIRangeWidget Final
	Private
	Field stepValue:Int = 1
	Field decimalPlaces:Int
	Field decimalScale:Int = 1
	Field changeHandler(stepper:TUIStepper)

	Public
	Method New()
		clickable = True
		focusable = True
	End Method

	Method SetStep(value:Int)
		If value < 1 Then value = 1
		stepValue = value
	End Method

	Method Step:Int()
		Return stepValue
	End Method

	Method ConfigureDecimal(minimum:Double, maximum:Double, value:Double, step:Double, places:Int = 1)
		If places < 1 Then places = 1
		If places > 6 Then places = 6
		decimalPlaces = places
		decimalScale = 1
		For Local index:Int = 0 Until decimalPlaces
			decimalScale :* 10
		Next
		SetRange(_DecimalUnits(minimum), _DecimalUnits(maximum))
		stepValue = Max(Abs(_DecimalUnits(step)), 1)
		SetValue(_DecimalUnits(value))
	End Method

	Method SetDecimalRange(minimum:Double, maximum:Double)
		SetRange(_DecimalUnits(minimum), _DecimalUnits(maximum))
	End Method

	Method SetDecimalValue(value:Double)
		SetValue(_DecimalUnits(value))
	End Method

	Method DecimalValue:Double()
		Return Double(currentValue) / Double(decimalScale)
	End Method

	Method SetDecimalStep(value:Double)
		stepValue = Max(Abs(_DecimalUnits(value)), 1)
	End Method

	Method DecimalPlaces:Int()
		Return decimalPlaces
	End Method

	Method ValueText:String()
		Return _ValueText()
	End Method

	Method OnChange(handler(stepper:TUIStepper))
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
		Local lineHeight:Int = 16
		If style.font Then lineHeight = style.font.LineHeight() * style.fontScale
		width = lineHeight * 6 + style.paddingLeft + style.paddingRight
		height = lineHeight + style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		graphics.SetColorValue(style.background)
		graphics.FillRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		graphics.SetColorValue(style.border)
		If style.borderWidth > 0 Then graphics.DrawRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		Local partWidth:Int = Width() / 3
		graphics.DrawLine(X() + partWidth, Y(), X() + partWidth, Y() + Height() - 1)
		graphics.DrawLine(X() + partWidth * 2, Y(), X() + partWidth * 2, Y() + Height() - 1)
		If style.font Then
			graphics.SetFont(style.font)
			graphics.SetColorValue(style.foreground)
			Local textHeight:Int = style.font.LineHeight() * style.fontScale
			_DrawCenteredText(graphics, "-", X(), partWidth, textHeight, style)
			_DrawCenteredText(graphics, _ValueText(), X() + partWidth, partWidth, textHeight, style)
			_DrawCenteredText(graphics, "+", X() + partWidth * 2, Width() - partWidth * 2, textHeight, style)
		End If
	End Method

	Private
	Method _DecimalUnits:Int(value:Double)
		If value >= 0.0 Then Return Int(value * Double(decimalScale) + 0.5)
		Return Int(value * Double(decimalScale) - 0.5)
	End Method

	Method _ValueText:String()
		If decimalPlaces <= 0 Then Return String(currentValue)
		Local units:Int = currentValue
		Local sign:String
		If units < 0 Then
			sign = "-"
			units = -units
		End If
		Local fraction:Int = units Mod decimalScale
		Local fractionText:String = String(fraction)
		While fractionText.Length < decimalPlaces
			fractionText = "0" + fractionText
		Wend
		Return sign + String(units / decimalScale) + "." + fractionText
	End Method

	Method _DrawCenteredText(graphics:TEmbedded2DContext, text:String, x:Int, width:Int, ..
			textHeight:Int, style:TUIStyle)
		Local textWidth:Int = style.font.TextWidth(text, style.fontScale)
		graphics.DrawText(text, x + (width - textWidth) / 2, Y() + (Height() - textHeight) / 2, style.fontScale)
	End Method

	Public
	Method _Activate()
		_SetUserValue(currentValue + stepValue)
	End Method

	Method _ActivateAt(x:Int)
		Local partWidth:Int = Max(Width() / 3, 1)
		If x < X() + partWidth Then
			_SetUserValue(currentValue - stepValue)
		Else If x >= X() + partWidth * 2 Then
			_SetUserValue(currentValue + stepValue)
		End If
	End Method

	Method _Adjust(delta:Int)
		_SetUserValue(currentValue + delta * stepValue)
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

Type TUISegmentedControl Extends TUIWidget Final
	Private
	Field itemNames:String[] = New String[0]
	Field selectedIndex:Int = -1
	Field selectionHandler(control:TUISegmentedControl)

	Public
	Method New()
		clickable = True
		focusable = True
	End Method

	Method AddItem:Int(text:String)
		If Not text Then text = ""
		itemNames = itemNames[..itemNames.Length + 1]
		itemNames[itemNames.Length - 1] = text
		If selectedIndex < 0 Then selectedIndex = 0
		_RequestLayout()
		Return itemNames.Length - 1
	End Method

	Method ItemCount:Int()
		Return itemNames.Length
	End Method

	Method ItemText:String(index:Int)
		If index < 0 Or index >= itemNames.Length Then Return ""
		Return itemNames[index]
	End Method

	Method SelectedIndex:Int()
		Return selectedIndex
	End Method

	Method SetSelectedIndex(value:Int)
		_SetSelectedIndex(value, False)
	End Method

	Method OnSelectionChanged(handler(control:TUISegmentedControl))
		selectionHandler = handler
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
		Local lineHeight:Int = 16
		Local widest:Int
		If style.font Then
			lineHeight = style.font.LineHeight() * style.fontScale
			For Local text:String = EachIn itemNames
				widest = Max(widest, style.font.TextWidth(text, style.fontScale))
			Next
		End If
		width = (widest + style.paddingLeft + style.paddingRight) * Max(itemNames.Length, 1)
		height = lineHeight + style.paddingTop + style.paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local active:TUIStyle = style
		If Context() And Context().Theme() And Enabled() Then active = Context().Theme().controlActive
		graphics.SetColorValue(style.background)
		graphics.FillRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		If itemNames.Length = 0 Then Return
		Local partWidth:Int = Width() / itemNames.Length
		For Local index:Int = 0 Until itemNames.Length
			Local partX:Int = X() + index * partWidth
			Local partRight:Int = X() + (index + 1) * partWidth
			If index = itemNames.Length - 1 Then partRight = X() + Width()
			If index = selectedIndex Then
				graphics.SetColorValue(active.background)
				graphics.FillRect(partX, Y(), partRight - partX, Height())
			End If
			If index > 0 Then
				graphics.SetColorValue(style.border)
				graphics.DrawLine(partX, Y(), partX, Y() + Height() - 1)
			End If
			If style.font Then
				Local text:String = itemNames[index]
				Local textWidth:Int = style.font.TextWidth(text, style.fontScale)
				Local textHeight:Int = style.font.LineHeight() * style.fontScale
				graphics.SetFont(style.font)
				If index = selectedIndex Then graphics.SetColorValue(active.foreground) Else graphics.SetColorValue(style.foreground)
				graphics.DrawText(text, partX + (partRight - partX - textWidth) / 2, ..
					Y() + (Height() - textHeight) / 2, style.fontScale)
			End If
		Next
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			graphics.DrawRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		End If
	End Method

	Public
	Method _Activate()
		If itemNames.Length = 0 Then Return
		_SetSelectedIndex((selectedIndex + 1) Mod itemNames.Length, True)
	End Method

	Method _ActivateAt(x:Int)
		If itemNames.Length = 0 Or Width() <= 0 Then Return
		Local index:Int = Int(Long(x - X()) * itemNames.Length / Width())
		_SetSelectedIndex(index, True)
	End Method

	Method _Adjust(delta:Int)
		_SetSelectedIndex(selectedIndex + delta, True)
	End Method

	Method _SetSelectedIndex(value:Int, notify:Int)
		If itemNames.Length = 0 Then value = -1
		If value < 0 And itemNames.Length > 0 Then value = 0
		If value >= itemNames.Length Then value = itemNames.Length - 1
		If selectedIndex = value Then Return
		selectedIndex = value
		_Invalidate()
		If notify Then
			If selectionHandler Then selectionHandler(Self)
			EmitEvent(CreateEvent(EVENT_UISELECTIONCHANGED, Self, selectedIndex))
		End If
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

Rem
bbdoc: Compact labelled state lamp for status dashboards.
End Rem
Type TUIStatusIndicator Extends TUIWidget Final
	Private
	Field indicatorText:String
	Field active:Int
	Field inactiveImage:TEmbeddedImage
	Field activeImage:TEmbeddedImage

	Public
	Method SetText(text:String)
		If Not text Then text = ""
		If indicatorText = text Then Return
		indicatorText = text
		_RequestLayout()
	End Method

	Method Text:String()
		Return indicatorText
	End Method

	Method SetActive(value:Int)
		value = value <> 0
		If active = value Then Return
		active = value
		_Invalidate()
	End Method

	Method Active:Int()
		Return active
	End Method

	Method SetStateImages(inactive:TEmbeddedImage, active:TEmbeddedImage = Null)
		inactiveImage = inactive
		activeImage = active
		_Invalidate()
		_RequestLayout()
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then
			If active Then Return Context().Theme().controlActive
			Return Context().Theme().control
		End If
		Return Super.DefaultStyle()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local lampSize:Int = 14 * style.fontScale
		If inactiveImage Then lampSize = Max(lampSize, Max(inactiveImage.Width(), inactiveImage.Height()))
		width = lampSize + style.paddingLeft + style.paddingRight
		height = lampSize + style.paddingTop + style.paddingBottom
		If style.font And indicatorText.Length Then
			width :+ Max(style.fontScale * 4, 6) + style.font.TextWidth(indicatorText, style.fontScale)
			height = Max(height, style.font.LineHeight() * style.fontScale + ..
				style.paddingTop + style.paddingBottom)
		End If
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local lampSize:Int = Max(Min(Height() - style.paddingTop - style.paddingBottom, ..
			14 * style.fontScale), 6)
		Local lampX:Int = X() + style.paddingLeft
		Local lampY:Int = Y() + (Height() - lampSize) / 2
		Local image:TEmbeddedImage = inactiveImage
		If active And activeImage Then image = activeImage
		If image Then
			_UIDrawImageRect(graphics, image, lampX, lampY, lampSize, lampSize)
		Else
			graphics.SetColorValue(style.border)
			graphics.FillCircle(lampX + lampSize / 2, lampY + lampSize / 2, lampSize / 2)
			graphics.SetColorValue(style.background)
			graphics.FillCircle(lampX + lampSize / 2, lampY + lampSize / 2, ..
				Max(lampSize / 2 - Max(style.borderWidth, 1), 1))
		End If
		If style.font And indicatorText.Length Then
			graphics.SetFont(style.font)
			graphics.SetColorValue(style.foreground)
			Local textHeight:Int = style.font.LineHeight() * style.fontScale
			graphics.DrawText(indicatorText, lampX + lampSize + Max(style.fontScale * 4, 6), ..
				Y() + (Height() - textHeight) / 2, style.fontScale)
		End If
	End Method
End Type

Rem
bbdoc: Read-only circular dashboard gauge with an optional image face.
End Rem
Type TUIArcGauge Extends TUIRangeWidget Final
	Private
	Field labelText:String
	Field unitText:String
	Field showValue:Int = True
	Field arcWidth:Int = 6
	Field tickCount:Int = 10
	Field faceImage:TEmbeddedImage

	Public
	Method SetLabel(text:String)
		If Not text Then text = ""
		If labelText = text Then Return
		labelText = text
		_Invalidate()
	End Method

	Method SetUnit(text:String)
		If Not text Then text = ""
		If unitText = text Then Return
		unitText = text
		_Invalidate()
	End Method

	Method SetShowValue(value:Int)
		showValue = value <> 0
		_Invalidate()
	End Method

	Method SetArcWidth(value:Int)
		arcWidth = Max(value, 1)
		_Invalidate()
	End Method

	Method SetTickCount(value:Int)
		tickCount = Max(value, 0)
		_Invalidate()
	End Method

	Method SetFaceImage(image:TEmbeddedImage)
		faceImage = image
		_Invalidate()
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then Return Context().Theme().progress
		Return Super.DefaultStyle()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		width = 120 * style.fontScale
		height = 100 * style.fontScale
		If faceImage Then
			width = Max(width, faceImage.Width())
			height = Max(height, faceImage.Height())
		End If
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local activeStyle:TUIStyle = style
		If Context() And Context().Theme() Then activeStyle = Context().Theme().progressFill
		If faceImage Then _UIDrawImageRect(graphics, faceImage, X(), Y(), Width(), Height())
		Local textReserve:Int
		If style.font And labelText.Length Then textReserve = style.font.LineHeight() * style.fontScale
		Local diameter:Int = Min(Width() - style.paddingLeft - style.paddingRight, ..
			Height() - style.paddingTop - style.paddingBottom - textReserve)
		Local radius:Int = Max(diameter / 2 - arcWidth - 2, 4)
		Local centerX:Int = X() + Width() / 2
		Local centerY:Int = Y() + style.paddingTop + diameter / 2
		graphics.SetColorValue(style.background)
		_UIDrawArc(graphics, centerX, centerY, radius, UIGaugeStartDegrees, UIGaugeSweepDegrees, arcWidth)
		Local valueSweep:Int = Fraction(UIGaugeSweepDegrees)
		If valueSweep > 0 Then
			graphics.SetColorValue(activeStyle.background)
			_UIDrawArc(graphics, centerX, centerY, radius, UIGaugeStartDegrees, valueSweep, arcWidth)
		End If
		If tickCount > 0 Then
			graphics.SetColorValue(style.border)
			For Local tick:Int = 0 To tickCount
				Local angle:Double = Double(UIGaugeStartDegrees) + ..
					Double(UIGaugeSweepDegrees * tick) / Double(tickCount)
				Local outerRadius:Int = radius + arcWidth + 2
				Local innerRadius:Int = radius + arcWidth
				graphics.DrawLine(centerX + _UIRounded(_UICos(angle) * innerRadius), ..
					centerY + _UIRounded(_UISin(angle) * innerRadius), ..
					centerX + _UIRounded(_UICos(angle) * outerRadius), ..
					centerY + _UIRounded(_UISin(angle) * outerRadius))
			Next
		End If
		If style.font Then
			graphics.SetFont(style.font)
			graphics.SetColorValue(style.foreground)
			If showValue Then
				Local valueText:String = String(Value()) + unitText
				Local valueWidth:Int = style.font.TextWidth(valueText, style.fontScale)
				graphics.DrawText(valueText, centerX - valueWidth / 2, ..
					centerY - style.font.LineHeight() * style.fontScale / 2, style.fontScale)
			End If
			If labelText.Length Then
				Local labelWidth:Int = style.font.TextWidth(labelText, style.fontScale)
				graphics.DrawText(labelText, centerX - labelWidth / 2, ..
					Y() + Height() - style.paddingBottom - style.font.LineHeight() * style.fontScale, ..
					style.fontScale)
			End If
		End If
	End Method
End Type

Rem
bbdoc: Allocation-free rolling line graph for sampled dashboard values.
End Rem
Type TUISparkline Extends TUIWidget Final
	Private
	Field samples:Int[] = New Int[0]
	Field sampleStart:Int
	Field sampleCount:Int
	Field minimumValue:Int
	Field maximumValue:Int = 100
	Field autoRange:Int = True

	Public
	Method SetCapacity(value:Int)
		value = Max(value, 2)
		If samples.Length = value Then Return
		samples = New Int[value]
		sampleStart = 0
		sampleCount = 0
		_Invalidate()
	End Method

	Method Capacity:Int()
		Return samples.Length
	End Method

	Method Count:Int()
		Return sampleCount
	End Method

	Method Clear()
		sampleStart = 0
		sampleCount = 0
		_Invalidate()
	End Method

	Method AddValue(value:Int)
		If samples.Length < 2 Then SetCapacity(32)
		Local index:Int
		If sampleCount < samples.Length Then
			index = (sampleStart + sampleCount) Mod samples.Length
			sampleCount :+ 1
		Else
			index = sampleStart
			sampleStart = (sampleStart + 1) Mod samples.Length
		End If
		samples[index] = value
		_Invalidate()
	End Method

	Method ValueAt:Int(index:Int)
		If index < 0 Or index >= sampleCount Then Return 0
		Return samples[(sampleStart + index) Mod samples.Length]
	End Method

	Method SetRange(minimum:Int, maximum:Int)
		If maximum <= minimum Then maximum = minimum + 1
		minimumValue = minimum
		maximumValue = maximum
		autoRange = False
		_Invalidate()
	End Method

	Method SetAutoRange(value:Int)
		autoRange = value <> 0
		_Invalidate()
	End Method

	Method AutoRange:Int()
		Return autoRange
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then Return Context().Theme().progress
		Return Super.DefaultStyle()
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		width = 120 * style.fontScale
		height = 48 * style.fontScale
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local activeStyle:TUIStyle = style
		If Context() And Context().Theme() Then activeStyle = Context().Theme().progressFill
		graphics.SetColorValue(style.background)
		graphics.FillRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			graphics.DrawRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		End If
		If sampleCount = 0 Then Return
		Local minimum:Int = minimumValue
		Local maximum:Int = maximumValue
		If autoRange Then
			minimum = ValueAt(0)
			maximum = minimum
			For Local index:Int = 1 Until sampleCount
				Local value:Int = ValueAt(index)
				If value < minimum Then minimum = value
				If value > maximum Then maximum = value
			Next
			If maximum <= minimum Then maximum = minimum + 1
		End If
		Local left:Int = X() + Max(style.paddingLeft, 2)
		Local top:Int = Y() + Max(style.paddingTop, 2)
		Local graphWidth:Int = Max(Width() - Max(style.paddingLeft, 2) - Max(style.paddingRight, 2) - 1, 1)
		Local graphHeight:Int = Max(Height() - Max(style.paddingTop, 2) - Max(style.paddingBottom, 2) - 1, 1)
		Local previousX:Int = left
		Local previousY:Int = top + graphHeight - ..
			Int(Long(ValueAt(0) - minimum) * graphHeight / Long(maximum - minimum))
		graphics.SetColorValue(activeStyle.background)
		For Local index:Int = 1 Until sampleCount
			Local x:Int = left + Int(Long(index) * graphWidth / Long(Max(sampleCount - 1, 1)))
			Local y:Int = top + graphHeight - ..
				Int(Long(ValueAt(index) - minimum) * graphHeight / Long(maximum - minimum))
			graphics.DrawLine(previousX, previousY, x, y)
			previousX = x
			previousY = y
		Next
		If sampleCount = 1 Then graphics.DrawLine(previousX, previousY, previousX, previousY)
	End Method
End Type

Rem
bbdoc: Focusable rotary value control adjusted with a linear drag gesture.
about: Horizontal dragging is the default. Applications can select vertical
dragging; both modes avoid the discontinuity of angle-following knobs near
their end stop.
End Rem
Type TUIRotaryDial Extends TUIRangeWidget Final
	Private
	Field faceImage:TEmbeddedImage
	Field dragStartX:Int
	Field dragStartY:Int
	Field dragStartValue:Int
	Field dragging:Int
	Field dragDirection:Int = UIDialDragHorizontal
	Field stepValue:Int = 1
	Field changeHandler(dial:TUIRotaryDial)

	Public
	Method New()
		clickable = True
		focusable = True
	End Method

	Method SetFaceImage(image:TEmbeddedImage)
		faceImage = image
		_Invalidate()
	End Method

	Method SetStep(value:Int)
		stepValue = Max(value, 1)
	End Method

	Method Step:Int()
		Return stepValue
	End Method

	Method SetDragDirection(direction:Int)
		If direction <> UIDialDragVertical Then direction = UIDialDragHorizontal
		dragDirection = direction
	End Method

	Method DragDirection:Int()
		Return dragDirection
	End Method

	Method OnChange(handler(dial:TUIRotaryDial))
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
		width = 96 * style.fontScale
		height = 96 * style.fontScale
		If faceImage Then
			width = Max(width, faceImage.Width())
			height = Max(height, faceImage.Height())
		End If
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		Local activeStyle:TUIStyle = style
		If Context() And Context().Theme() And Enabled() Then activeStyle = Context().Theme().controlActive
		If faceImage Then _UIDrawImageRect(graphics, faceImage, X(), Y(), Width(), Height())
		Local radius:Int = Max(Min(Width(), Height()) / 2 - 8 * style.fontScale, 6)
		Local centerX:Int = X() + Width() / 2
		Local centerY:Int = Y() + Height() / 2
		Local arcWidth:Int = Max(4 * style.fontScale, 2)
		graphics.SetColorValue(style.background)
		_UIDrawArc(graphics, centerX, centerY, radius, UIGaugeStartDegrees, UIGaugeSweepDegrees, arcWidth)
		graphics.SetColorValue(activeStyle.background)
		_UIDrawArc(graphics, centerX, centerY, radius, UIGaugeStartDegrees, Fraction(UIGaugeSweepDegrees), arcWidth)
		Local angle:Double = Double(UIGaugeStartDegrees + Fraction(UIGaugeSweepDegrees))
		Local needleRadius:Int = Max(radius - arcWidth - 3, 2)
		graphics.SetColorValue(activeStyle.foreground)
		graphics.DrawLine(centerX, centerY, ..
			centerX + _UIRounded(_UICos(angle) * needleRadius), ..
			centerY + _UIRounded(_UISin(angle) * needleRadius))
		graphics.FillCircle(centerX, centerY, Max(3 * style.fontScale, 2))
	End Method

	Public
	Method _BeginPointer(x:Int, y:Int)
		dragStartX = x
		dragStartY = y
		dragStartValue = Value()
		dragging = True
	End Method

	Method _TrackPointer(x:Int, y:Int)
		If Not dragging Then _BeginPointer(x, y)
		Local span:Int = Max(Maximum() - Minimum(), 1)
		Local travel:Int
		Local distance:Int
		If dragDirection = UIDialDragVertical Then
			travel = Max(Height(), 32)
			distance = dragStartY - y
		Else
			travel = Max(Width(), 32)
			distance = x - dragStartX
		End If
		Local delta:Int = Int(Long(distance) * span / Long(travel))
		_SetUserValue(dragStartValue + delta)
	End Method

	Method _EndPointer()
		dragging = False
	End Method

	Method _Adjust(delta:Int)
		_SetUserValue(Value() + delta * stepValue)
	End Method

	Method _SetUserValue(value:Int)
		If value < Minimum() Then value = Minimum()
		If value > Maximum() Then value = Maximum()
		If value = Value() Then Return
		SetValue(value)
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIVALUECHANGED, Self, Value()))
	End Method
End Type

Type TUIDialogAction Extends TUIButton Final
	Private
	Field dialogOwner:TUIDialog
	Field actionResult:Int

	Public
	Method _Configure(owner:TUIDialog, result:Int)
		dialogOwner = owner
		actionResult = result
	End Method

	Method Result:Int()
		Return actionResult
	End Method

	Public
	Method _Activate() Override
		Super._Activate()
		If dialogOwner Then dialogOwner.Close(actionResult)
	End Method
End Type

Type TUIDialog Extends TUIContainer Final
	Private
	Field titleLabel:TUILabel
	Field messageLabel:TUILabel
	Field actionRow:TUIRow
	Field dialogResult:Int
	Field resultHandler(dialog:TUIDialog, result:Int)

	Public
	Method New()
		layoutDirection = 2
		gap = 12
		SetPadding(18)
		drawBackground = True
		titleLabel = Label()
		messageLabel = Label()
		messageLabel.SetWordWrap(True)
		actionRow = Row()
		actionRow.SetGap(6)
	End Method

	Method SetTitle(text:String)
		titleLabel.SetText(text)
	End Method

	Method Title:String()
		Return titleLabel.Text()
	End Method

	Method SetMessage(text:String)
		messageLabel.SetText(text)
	End Method

	Method Message:String()
		Return messageLabel.Text()
	End Method

	Method TitleLabel:TUILabel()
		Return titleLabel
	End Method

	Method MessageLabel:TUILabel()
		Return messageLabel
	End Method

	Method Action:TUIDialogAction(text:String, result:Int = 0)
		Local action:TUIDialogAction = New TUIDialogAction
		action._Configure(Self, result)
		action.SetText(text)
		action.SetGrow(1)
		actionRow.Add(action)
		Return action
	End Method

	Method OnResult(handler(dialog:TUIDialog, result:Int))
		resultHandler = handler
	End Method

	Method Result:Int()
		Return dialogResult
	End Method

	Method Show:Int(width:Int = UILayoutAuto, height:Int = UILayoutAuto)
		If Not Context() Then Return False
		Local preferredWidth:Int
		Local preferredHeight:Int
		Local availableWidth:Int = Context().Frame().Width()
		If width >= 0 Then availableWidth = width
		PreferredSize(availableWidth, Context().Frame().Height(), preferredWidth, preferredHeight)
		If width < 0 Then width = preferredWidth
		If height < 0 Then height = preferredHeight
		Local x:Int = (Context().Frame().Width() - width) / 2
		Local y:Int = (Context().Frame().Height() - height) / 2
		Return Context().ShowOverlay(Self, x, y, width, height, False)
	End Method

	Method Close:Int(result:Int = 0)
		If Not Context() Or Context().ActiveOverlay() <> Self Then Return False
		dialogResult = result
		Context().DismissOverlay()
		If resultHandler Then resultHandler(Self, result)
		EmitEvent(CreateEvent(EVENT_UIACTION, Self, result))
		Return True
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then Return Context().Theme().control
		Return Super.DefaultStyle()
	End Method
End Type

Rem
bbdoc: A transient or persistent non-modal notification.
about: Toasts are owned by a TUIContext and are displayed above normal content
and modal overlays without taking focus or participating in touch hit-testing.
End Rem
Type TUIToast Extends TUIContainer Final
	Private
	Field messageLabel:TUILabel
	Field toastKind:Int
	Field toastDuration:Int = UIToastDefaultDuration
	Field toastPlacement:Int = UIToastBottomCenter
	Field toastShownAt:UInt

	Public
	Method New()
		layoutDirection = 2
		SetPaddingEdges(14, 10, 14, 10)
		drawBackground = True
		messageLabel = Label()
		messageLabel.SetWordWrap(True)
	End Method

	Method Message:String()
		Return messageLabel.Text()
	End Method

	Method Kind:Int()
		Return toastKind
	End Method

	Method Duration:Int()
		Return toastDuration
	End Method

	Method Persistent:Int()
		Return toastDuration = 0
	End Method

	Method Placement:Int()
		Return toastPlacement
	End Method

	Method SetPlacement(value:Int)
		If value < UIToastTopLeft Or value > UIToastBottomRight Then value = UIToastBottomCenter
		If toastPlacement = value Then Return
		toastPlacement = value
		If Context() Then Context().RequestLayout()
	End Method

	Method Close:Int()
		If Not Context() Then Return False
		Return Context().DismissToast(Self)
	End Method

	Public
	Method _Configure(message:String, duration:Int, kind:Int, placement:Int)
		If duration < 0 Then duration = 0
		If kind < UIToastInfo Or kind > UIToastError Then kind = UIToastInfo
		toastDuration = duration
		toastKind = kind
		If placement < UIToastTopLeft Or placement > UIToastBottomRight Then placement = UIToastBottomCenter
		toastPlacement = placement
		messageLabel.SetText(message)

		Local style:TUIStyle = TUIStyle.Create($ffffff, $245d86, True)
		style.border = $80c9f4
		Select toastKind
			Case UIToastSuccess
				style.background = $24633f
				style.border = $75d59b
			Case UIToastWarning
				style.foreground = $fff8df
				style.background = $795b17
				style.border = $ffd86a
			Case UIToastError
				style.background = $842f38
				style.border = $ff929b
		End Select
		style.borderWidth = 1
		style.cornerRadius = 6
		If Context() And Context().Theme() Then
			style.font = Context().Theme().label.font
			style.fontScale = Context().Theme().label.fontScale
		End If
		SetStyle(style)
		Local labelStyle:TUIStyle = style.Copy()
		labelStyle.backgroundVisible = False
		labelStyle.borderWidth = 0
		labelStyle.paddingLeft = 0
		labelStyle.paddingTop = 0
		labelStyle.paddingRight = 0
		labelStyle.paddingBottom = 0
		messageLabel.SetStyle(labelStyle)
	End Method

	Method _Show(now:UInt)
		toastShownAt = now
	End Method

	Method _ShownAt:UInt()
		Return toastShownAt
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Super.Draw(graphics)
		Local style:TUIStyle = Style()
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			graphics.DrawRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
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
	Field overlayWidget:TUIContainer
	Field overlayPreviousFocus:TUIWidget
	Field overlayDismissOutside:Int = True
	Field themeValue:TUITheme
	Field layoutPending:Int = True
	Field contextSlot:Int = -1
	Field pressedWidget:TUIWidget
	Field focusedWidget:TUIWidget
	Field deferredFocus:TUIWidget
	Field deferredFocusPending:Int
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
	Field visibleToasts:TUIToast[] = New TUIToast[0]
	Field toastQueue:TUIToast[] = New TUIToast[0]
	Field toastPlacement:Int = UIToastBottomCenter
	Field toastVisibleLimit:Int = 3
	Field toastGap:Int = 8
	Field toastMargin:Int = 12

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
		deferredFocus = Null
		deferredFocusPending = False
		overlayWidget = Null
		overlayPreviousFocus = Null
		visibleToasts = New TUIToast[0]
		toastQueue = New TUIToast[0]
		touchScroll = Null
		pressedContact = -1
	End Method

	Method Root:TUIColumn()
		Return rootWidget
	End Method

	Method Theme:TUITheme()
		Return themeValue
	End Method

	Method ActiveOverlay:TUIContainer()
		Return overlayWidget
	End Method

	Method OverlayVisible:Int()
		Return overlayWidget <> Null
	End Method

	Method PopupMenu:TUIPopupMenu()
		Local menu:TUIPopupMenu = New TUIPopupMenu
		menu._Attach(Self, Null)
		Return menu
	End Method

	Method Dialog:TUIDialog(title:String = "", message:String = "")
		Local dialog:TUIDialog = New TUIDialog
		dialog.SetTitle(title)
		dialog.SetMessage(message)
		dialog._Attach(Self, Null)
		Return dialog
	End Method

	Method Toast:TUIToast(message:String, duration:Int = UIToastDefaultDuration, ..
			kind:Int = UIToastInfo, placement:Int = -1)
		If toastQueue.Length >= UIToastQueueMaximum Then Return Null
		If placement < UIToastTopLeft Or placement > UIToastBottomRight Then placement = toastPlacement
		Local toast:TUIToast = New TUIToast
		toast._Attach(Self, Null)
		toast._Configure(message, duration, kind, placement)
		If visibleToasts.Length >= toastVisibleLimit Then
			toastQueue = toastQueue[..toastQueue.Length + 1]
			toastQueue[toastQueue.Length - 1] = toast
		Else
			_ActivateToast(toast, UInt(MilliSecs()))
		End If
		Return toast
	End Method

	Method ActiveToast:TUIToast()
		If visibleToasts.Length = 0 Then Return Null
		Return visibleToasts[visibleToasts.Length - 1]
	End Method

	Method VisibleToastCount:Int()
		Return visibleToasts.Length
	End Method

	Method PendingToastCount:Int()
		Return toastQueue.Length
	End Method

	Method SetToastPlacement(value:Int)
		If value < UIToastTopLeft Or value > UIToastBottomRight Then value = UIToastBottomCenter
		toastPlacement = value
	End Method

	Method ToastPlacement:Int()
		Return toastPlacement
	End Method

	Method SetToastVisibleLimit(value:Int)
		If value < 1 Then value = 1
		If value > UIToastQueueMaximum Then value = UIToastQueueMaximum
		toastVisibleLimit = value
		While visibleToasts.Length > toastVisibleLimit
			Local toast:TUIToast = visibleToasts[visibleToasts.Length - 1]
			visibleToasts = visibleToasts[..visibleToasts.Length - 1]
			toastQueue = toastQueue[..toastQueue.Length + 1]
			For Local move:Int = toastQueue.Length - 1 Until 0 Step -1
				toastQueue[move] = toastQueue[move - 1]
			Next
			toastQueue[0] = toast
		Wend
		While visibleToasts.Length < toastVisibleLimit And toastQueue.Length
			Local nextToast:TUIToast = toastQueue[0]
			For Local index:Int = 0 Until toastQueue.Length - 1
				toastQueue[index] = toastQueue[index + 1]
			Next
			toastQueue = toastQueue[..toastQueue.Length - 1]
			_ActivateToast(nextToast, UInt(MilliSecs()))
		Wend
		RequestLayout()
	End Method

	Method ToastVisibleLimit:Int()
		Return toastVisibleLimit
	End Method

	Method SetToastGap(value:Int)
		If value < 0 Then value = 0
		toastGap = value
		RequestLayout()
	End Method

	Method ToastGap:Int()
		Return toastGap
	End Method

	Method SetToastMargin(value:Int)
		If value < 0 Then value = 0
		toastMargin = value
		RequestLayout()
	End Method

	Method ToastMargin:Int()
		Return toastMargin
	End Method

	Method DismissToast:Int(toast:TUIToast = Null)
		If toast Then
			For Local index:Int = 0 Until toastQueue.Length
				If toastQueue[index] = toast Then
					For Local move:Int = index Until toastQueue.Length - 1
						toastQueue[move] = toastQueue[move + 1]
					Next
					toastQueue = toastQueue[..toastQueue.Length - 1]
					Return True
				End If
			Next
		End If
		If visibleToasts.Length = 0 Then Return False
		Local removeIndex:Int = visibleToasts.Length - 1
		If toast Then
			removeIndex = -1
			For Local index:Int = 0 Until visibleToasts.Length
				If visibleToasts[index] = toast Then
					removeIndex = index
					Exit
				End If
			Next
			If removeIndex < 0 Then Return False
		End If
		Local old:TUIToast = visibleToasts[removeIndex]
		InvalidateRect(old.X(), old.Y(), old.Width(), old.Height())
		For Local index:Int = removeIndex Until visibleToasts.Length - 1
			visibleToasts[index] = visibleToasts[index + 1]
		Next
		visibleToasts = visibleToasts[..visibleToasts.Length - 1]
		If toastQueue.Length Then
			Local nextToast:TUIToast = toastQueue[0]
			For Local index:Int = 0 Until toastQueue.Length - 1
				toastQueue[index] = toastQueue[index + 1]
			Next
			toastQueue = toastQueue[..toastQueue.Length - 1]
			_ActivateToast(nextToast, UInt(MilliSecs()))
		Else
			RequestLayout()
		End If
		Return True
	End Method

	Method ClearToasts()
		For Local toast:TUIToast = EachIn visibleToasts
			InvalidateRect(toast.X(), toast.Y(), toast.Width(), toast.Height())
		Next
		visibleToasts = New TUIToast[0]
		toastQueue = New TUIToast[0]
	End Method

	Method ShowOverlay:Int(widget:TUIContainer, x:Int, y:Int, width:Int = UILayoutAuto, ..
			height:Int = UILayoutAuto, dismissOnOutside:Int = True)
		If Not widget Or widget.Parent() Then Return False
		If overlayWidget And overlayWidget <> widget Then DismissOverlay()
		If overlayWidget = widget Then Return True
		widget._Attach(Self, Null)
		Local preferredWidth:Int
		Local preferredHeight:Int
		widget.PreferredSize(frame.Width(), frame.Height(), preferredWidth, preferredHeight)
		If width < 0 Then width = preferredWidth
		If height < 0 Then height = preferredHeight
		If width < 1 Then width = 1
		If height < 1 Then height = 1
		If width > frame.Width() Then width = frame.Width()
		If height > frame.Height() Then height = frame.Height()
		If x + width > frame.Width() Then x = frame.Width() - width
		If y + height > frame.Height() Then y = frame.Height() - height
		If x < 0 Then x = 0
		If y < 0 Then y = 0
		overlayPreviousFocus = focusedWidget
		overlayWidget = widget
		overlayDismissOutside = dismissOnOutside <> 0
		widget._SetBounds(x, y, width, height)
		widget._LayoutChildren()
		InvalidateRect(x, y, width, height)
		Local first:TUIWidget
		Local list:TUIList = TUIList(widget)
		If list Then first = list.SelectedItem()
		If Not first Then
			Local cursor:Int
			first = _FocusableAt(widget, 0, cursor)
		End If
		If first Then SetFocus(first) Else ClearFocus()
		Return True
	End Method

	Method DismissOverlay:Int()
		If Not overlayWidget Then Return False
		Local old:TUIContainer = overlayWidget
		Local restore:TUIWidget = overlayPreviousFocus
		overlayWidget = Null
		overlayPreviousFocus = Null
		InvalidateRect(old.X(), old.Y(), old.Width(), old.Height())
		If restore And _CanFocus(restore) Then SetFocus(restore) Else ClearFocus()
		Return True
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

	Rem
	bbdoc: Restores focus during the next presentation after pending layout has completed.
	about: Navigation uses this to keep layout and framebuffer submission out of
	the input callback which changed the visible page.
	End Rem
	Method DeferFocus(widget:TUIWidget)
		deferredFocus = widget
		deferredFocusPending = True
	End Method

	Method ClearFocus()
		SetFocus(Null)
	End Method

	Method FocusNext:Int()
		Local focusRoot:TUIWidget = rootWidget
		If overlayWidget Then focusRoot = overlayWidget
		Local count:Int = _CountFocusable(focusRoot)
		If count <= 0 Then Return False
		Local cursor:Int
		Local index:Int = _FocusableIndex(focusRoot, focusedWidget, cursor)
		Local nextIndex:Int
		If index < 0 Then nextIndex = 0 Else nextIndex = (index + 1) Mod count
		cursor = 0
		Return SetFocus(_FocusableAt(focusRoot, nextIndex, cursor))
	End Method

	Method FocusPrevious:Int()
		Local focusRoot:TUIWidget = rootWidget
		If overlayWidget Then focusRoot = overlayWidget
		Local count:Int = _CountFocusable(focusRoot)
		If count <= 0 Then Return False
		Local cursor:Int
		Local index:Int = _FocusableIndex(focusRoot, focusedWidget, cursor)
		Local previousIndex:Int
		If index < 0 Then previousIndex = count - 1 Else previousIndex = (index + count - 1) Mod count
		cursor = 0
		Return SetFocus(_FocusableAt(focusRoot, previousIndex, cursor))
	End Method

	Method ActivateFocused:Int()
		Local target:TUIWidget = focusedWidget
		If Not _CanFocus(target) Then Return False
		Local dialogAction:TUIDialogAction = TUIDialogAction(target)
		If dialogAction Then
			dialogAction._Activate()
			Return True
		End If
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
		Local radioButton:TUIRadioButton = TUIRadioButton(target)
		If radioButton Then
			radioButton._Activate()
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
		Local combo:TUIComboBox = TUIComboBox(target)
		If combo Then
			combo._Activate()
			Return True
		End If
		Local tabButton:TUITabButton = TUITabButton(target)
		If tabButton Then
			tabButton._Activate()
			Return True
		End If
		Local stepper:TUIStepper = TUIStepper(target)
		If stepper Then
			stepper._Activate()
			Return True
		End If
		Local segmented:TUISegmentedControl = TUISegmentedControl(target)
		If segmented Then
			segmented._Activate()
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
		Local dial:TUIRotaryDial = TUIRotaryDial(focusedWidget)
		If dial Then
			dial._Adjust(delta)
			Return True
		End If
		Local listItem:TUIListItem = TUIListItem(focusedWidget)
		If listItem And listItem.listOwner Then Return listItem.listOwner.MoveSelection(delta)
		Local combo:TUIComboBox = TUIComboBox(focusedWidget)
		If combo And combo.ItemCount() > 0 Then
			combo._SetSelectedIndex(combo.SelectedIndex() + delta, True)
			Return True
		End If
		Local tabButton:TUITabButton = TUITabButton(focusedWidget)
		If tabButton And tabButton.tabOwner Then
			Local nextIndex:Int = tabButton.tabOwner.SelectedIndex() + delta
			If nextIndex < 0 Then nextIndex = 0
			If nextIndex >= tabButton.tabOwner.PageCount() Then nextIndex = tabButton.tabOwner.PageCount() - 1
			tabButton.tabOwner._SelectIndex(nextIndex, True)
			Return True
		End If
		Local stepper:TUIStepper = TUIStepper(focusedWidget)
		If stepper Then
			stepper._Adjust(delta)
			Return True
		End If
		Local segmented:TUISegmentedControl = TUISegmentedControl(focusedWidget)
		If segmented Then
			segmented._Adjust(delta)
			Return True
		End If
		Local radioButton:TUIRadioButton = TUIRadioButton(focusedWidget)
		If radioButton Then
			radioButton._Move(delta)
			Return True
		End If
		Return False
	End Method

	Rem
	bbdoc: Handles one application-level back action.
	about: An active overlay is dismissed first. Otherwise the deepest visible
	page stack is popped. Returns false when there is nowhere to go back to.
	End Rem
	Method Back:Int()
		If overlayWidget Then
			DismissOverlay()
			Return True
		End If
		Return _BackInWidget(rootWidget)
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
		If overlayWidget Then overlayWidget._LayoutChildren()
		If visibleToasts.Length Then _LayoutToasts()
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
			If overlayWidget Then _DrawWidget(overlayWidget, x, y, width, height)
			For Local toast:TUIToast = EachIn visibleToasts
				_DrawWidget(toast, x, y, width, height)
			Next
			graphics.PopState()
		Next
		invalidCount = 0
		Return True
	End Method

	Method Present:Int()
		Local now:UInt = UInt(MilliSecs())
		_UpdateScrollMomentum(rootWidget, now)
		If overlayWidget Then _UpdateScrollMomentum(overlayWidget, now)
		_UpdateToast(now)
		If deferredFocusPending Then
			Local restore:TUIWidget = deferredFocus
			deferredFocus = Null
			deferredFocusPending = False
			If layoutPending Then Layout()
			If restore And _CanFocus(restore) Then SetFocus(restore) Else ClearFocus()
		End If
		Render()
		If display Then Return graphics.PresentDirty(display)
		Return True
	End Method

	Method HitTest:TUIWidget(x:Int, y:Int)
		If layoutPending Then Layout()
		If overlayWidget Then
			If Not overlayWidget.Contains(x, y) Then Return Null
			Return _HitTest(overlayWidget, x, y)
		End If
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
				If overlayWidget And Not overlayWidget.Contains(x, y) Then
					If overlayDismissOutside Then DismissOverlay()
					pressedContact = event.data
					Return
				End If
				Local target:TUIWidget = HitTest(x, y)
				touchScroll = _ContainingScroll(target)
				If Not touchScroll Then
					If overlayWidget Then
						touchScroll = _ScrollAt(overlayWidget, x, y)
					Else
						touchScroll = _ScrollAt(rootWidget, x, y)
					End If
				End If
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
					If slider Then
						slider._TrackPointer(x)
					Else
						Local dial:TUIRotaryDial = TUIRotaryDial(target)
						If dial Then dial._BeginPointer(x, y)
					End If
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
							Local dial:TUIRotaryDial = TUIRotaryDial(pressedWidget)
							If dial Then
								dial._TrackPointer(x, y)
							Else
								pressedArmed = pressedWidget.Contains(x, y)
								pressedWidget._SetPressed(pressedArmed)
							End If
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
						Local dial:TUIRotaryDial = TUIRotaryDial(target)
						If dial Then
							If Not touchScrolled Then dial._TrackPointer(x, y)
							dial._EndPointer()
						End If
						activate = Not touchScrolled And pressedArmed And target.Contains(x, y) And target.Enabled()
						target._SetPressed(False)
					End If
					pressedWidget = Null
					pressedContact = -1
					pressedArmed = False
					touchScroll = Null
					touchScrolled = False
					If activate Then
						Local dialogAction:TUIDialogAction = TUIDialogAction(target)
						If dialogAction Then
							dialogAction._Activate()
						Else
							Local button:TUIButton = TUIButton(target)
							If button Then
								button._Activate()
								EmitEvent(CreateEvent(EVENT_UIACTION, target, 0, 0, x, y))
							Else
								Local checkBox:TUICheckBox = TUICheckBox(target)
								If checkBox Then
									checkBox._Activate()
								Else
									Local radioButton:TUIRadioButton = TUIRadioButton(target)
									If radioButton Then
										radioButton._Activate()
									Else
										Local switchControl:TUISwitch = TUISwitch(target)
										If switchControl Then
											switchControl._Activate()
										Else
											Local listItem:TUIListItem = TUIListItem(target)
											If listItem Then
												listItem._Activate()
											Else
												Local combo:TUIComboBox = TUIComboBox(target)
												If combo Then
													combo._Activate()
												Else
													Local tabButton:TUITabButton = TUITabButton(target)
													If tabButton Then
														tabButton._Activate()
													Else
														Local stepper:TUIStepper = TUIStepper(target)
														If stepper Then
															stepper._ActivateAt(x)
														Else
															Local segmented:TUISegmentedControl = TUISegmentedControl(target)
															If segmented Then segmented._ActivateAt(x)
														End If
													End If
												End If
											End If
										End If
									End If
								End If
							End If
						End If
					End If
				End If
		End Select
	End Method

	Public
	Method _UpdateToast(now:UInt)
		Local index:Int
		While index < visibleToasts.Length
			Local toast:TUIToast = visibleToasts[index]
			If toast.Duration() > 0 And now - toast._ShownAt() >= UInt(toast.Duration()) Then
				Local pendingBefore:Int = toastQueue.Length
				DismissToast(toast)
				If pendingBefore > 0 And visibleToasts.Length Then ..
					visibleToasts[visibleToasts.Length - 1]._Show(now)
			Else
				index :+ 1
			End If
		Wend
	End Method

	Method _ActivateToast(toast:TUIToast, now:UInt)
		visibleToasts = visibleToasts[..visibleToasts.Length + 1]
		visibleToasts[visibleToasts.Length - 1] = toast
		toast._Show(now)
		RequestLayout()
		_LayoutToasts()
	End Method

	Method _LayoutToasts()
		Local maximumWidth:Int = Min(Max(frame.Width() - toastMargin * 2, 1), 420)
		For Local toast:TUIToast = EachIn visibleToasts
			InvalidateRect(toast.X(), toast.Y(), toast.Width(), toast.Height())
			Local width:Int
			Local height:Int
			toast.PreferredSize(maximumWidth, frame.Height() - toastMargin * 2, width, height)
			If width > maximumWidth Then width = maximumWidth
			If width < 1 Then width = 1
			toast.PreferredSize(width, frame.Height() - toastMargin * 2, width, height)
			If height > frame.Height() - toastMargin * 2 Then height = frame.Height() - toastMargin * 2
			If height < 1 Then height = 1
			toast._SetBounds(0, 0, width, height)
		Next

		For Local index:Int = 0 Until visibleToasts.Length
			Local toast:TUIToast = visibleToasts[index]
			Local placement:Int = toast.Placement()
			Local x:Int
			Select placement Mod 3
				Case 0
					x = toastMargin
				Case 1
					x = (frame.Width() - toast.Width()) / 2
				Case 2
					x = frame.Width() - toastMargin - toast.Width()
			End Select
			Local stackHeight:Int = toast.Height()
			For Local later:Int = index + 1 Until visibleToasts.Length
				If visibleToasts[later].Placement() = placement Then ..
					stackHeight :+ toastGap + visibleToasts[later].Height()
			Next
			Local y:Int
			Select placement / 3
				Case 0
					y = toastMargin + stackHeight - toast.Height()
				Case 1
					Local totalHeight:Int = stackHeight
					For Local earlier:Int = 0 Until index
						If visibleToasts[earlier].Placement() = placement Then ..
							totalHeight :+ toastGap + visibleToasts[earlier].Height()
					Next
					y = (frame.Height() - totalHeight) / 2 + stackHeight - toast.Height()
				Case 2
					y = frame.Height() - toastMargin - stackHeight
			End Select
			toast._SetBounds(x, y, toast.Width(), toast.Height())
			toast._LayoutChildren()
			InvalidateRect(toast.X(), toast.Y(), toast.Width(), toast.Height())
		Next
	End Method

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
		If Not themeValue Or themeValue.focusWidth <= 0 Or Not widget.FocusIndicatorVisible() Then Return
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

	Method _BackInWidget:Int(widget:TUIWidget)
		If Not widget Or Not widget.Visible() Then Return False
		For Local index:Int = widget.uiChildren.Length - 1 To 0 Step -1
			If _BackInWidget(widget.uiChildren[index]) Then Return True
		Next
		Local stack:TUIPageStack = TUIPageStack(widget)
		If stack And stack.CanPop() Then Return stack.Pop()
		Return False
	End Method

	Method _CanFocus:Int(widget:TUIWidget)
		If Not widget Or Not widget.Focusable() Or Not widget.Enabled() Or Not widget.Visible() Then Return False
		If overlayWidget And Not _IsDescendant(widget, overlayWidget) Then Return False
		Local parent:TUIContainer = widget.Parent()
		While parent
			If Not parent.Enabled() Or Not parent.Visible() Then Return False
			parent = parent.Parent()
		Wend
		Return True
	End Method

	Method _IsDescendant:Int(widget:TUIWidget, ancestor:TUIWidget)
		Local current:TUIWidget = widget
		While current
			If current = ancestor Then Return True
			current = current.Parent()
		Wend
		Return False
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
