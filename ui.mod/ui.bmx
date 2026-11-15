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
Import Embedded.Graphics2D
Import "native/ui_math.c"

Rem
bbdoc: Requests the natural measured size for one layout dimension.
End Rem
Const UILayoutAuto:Int = -1
Rem
bbdoc: Requests all available space for one layout dimension.
End Rem
Const UILayoutFill:Int = -2
Rem
bbdoc: Aligns a widget with the leading edge of its layout axis.
End Rem
Const UIAlignStart:Int = 0
Rem
bbdoc: Centers a widget on its layout axis.
End Rem
Const UIAlignCenter:Int = 1
Rem
bbdoc: Aligns a widget with the trailing edge of its layout axis.
End Rem
Const UIAlignEnd:Int = 2
Rem
bbdoc: Stretches a widget across the available cross-axis space.
End Rem
Const UIAlignStretch:Int = 3
Rem
bbdoc: Maximum number of independent dirty rectangles retained by a UI context.
End Rem
Const UIInvalidRegionMaximum:Int = 8
Rem
bbdoc: Pointer travel in pixels required to turn a touch gesture into scrolling.
End Rem
Const UIScrollDragThreshold:Int = 4
Rem
bbdoc: Minimum release velocity in pixels per second that starts inertial scrolling.
End Rem
Const UIScrollMinimumMomentum:Int = 60
Rem
bbdoc: Maximum inertial scrolling velocity in pixels per second.
End Rem
Const UIScrollMaximumMomentum:Int = 2400
Rem
bbdoc: Inertial scrolling deceleration in pixels per second squared.
End Rem
Const UIScrollMomentumDeceleration:Int = 1800
Rem
bbdoc: Identifies an informational toast notification.
End Rem
Const UIToastInfo:Int = 0
Rem
bbdoc: Identifies a successful-operation toast notification.
End Rem
Const UIToastSuccess:Int = 1
Rem
bbdoc: Identifies a warning toast notification.
End Rem
Const UIToastWarning:Int = 2
Rem
bbdoc: Identifies an error toast notification.
End Rem
Const UIToastError:Int = 3
Rem
bbdoc: Default toast lifetime in milliseconds.
End Rem
Const UIToastDefaultDuration:Int = 2500
Rem
bbdoc: Maximum number of pending toast notifications in one context.
End Rem
Const UIToastQueueMaximum:Int = 8
Rem
bbdoc: Maximum number of pages retained by one page stack.
End Rem
Const UIPageStackMaximum:Int = 16
Rem
bbdoc: Maximum number of columns supported by one grid.
End Rem
Const UIGridMaximumColumns:Int = 12
Rem
bbdoc: Places toast notifications at the top-left of the display.
End Rem
Const UIToastTopLeft:Int = 0
Rem
bbdoc: Places toast notifications at the top-center of the display.
End Rem
Const UIToastTopCenter:Int = 1
Rem
bbdoc: Places toast notifications at the top-right of the display.
End Rem
Const UIToastTopRight:Int = 2
Rem
bbdoc: Places toast notifications at the center-left of the display.
End Rem
Const UIToastCenterLeft:Int = 3
Rem
bbdoc: Places toast notifications at the center of the display.
End Rem
Const UIToastCenter:Int = 4
Rem
bbdoc: Places toast notifications at the center-right of the display.
End Rem
Const UIToastCenterRight:Int = 5
Rem
bbdoc: Places toast notifications at the bottom-left of the display.
End Rem
Const UIToastBottomLeft:Int = 6
Rem
bbdoc: Places toast notifications at the bottom-center of the display.
End Rem
Const UIToastBottomCenter:Int = 7
Rem
bbdoc: Places toast notifications at the bottom-right of the display.
End Rem
Const UIToastBottomRight:Int = 8
Rem
bbdoc: Default angular span of an arc gauge in degrees.
End Rem
Const UIGaugeSweepDegrees:Int = 270
Rem
bbdoc: Default starting angle of an arc gauge in degrees.
End Rem
Const UIGaugeStartDegrees:Int = 135
Rem
bbdoc: Selects horizontal pointer movement for rotary-dial interaction.
End Rem
Const UIDialDragHorizontal:Int = 0
Rem
bbdoc: Selects vertical pointer movement for rotary-dial interaction.
End Rem
Const UIDialDragVertical:Int = 1

Rem
bbdoc: Event emitted when a button-like widget or dialog action is activated.
about: The event source is the activated widget. Pointer activation also records
the display coordinates in the event's `x` and `y` fields. Dialogs place their
result value in `data`.
End Rem
Global EVENT_UIACTION:Int = AllocUserEventId("UIAction")
Rem
bbdoc: Event emitted after the value of a control changes interactively.
about: The event source is the changed widget and `data` contains its current
integer or Boolean value.
End Rem
Global EVENT_UIVALUECHANGED:Int = AllocUserEventId("UIValueChanged")
Rem
bbdoc: Event emitted after keyboard or pointer focus moves to another widget.
about: The event source is the newly focused widget, or `Null` when focus is
cleared. The previous focused widget is available through `extra`.
End Rem
Global EVENT_UIFOCUSCHANGED:Int = AllocUserEventId("UIFocusChanged")
Rem
bbdoc: Event emitted after a selectable widget changes its selection.
about: The event source is the changed widget and `data` contains its selected
index. A list also supplies the selected item through `extra`.
End Rem
Global EVENT_UISELECTIONCHANGED:Int = AllocUserEventId("UISelectionChanged")
Rem
bbdoc: Event emitted after a page stack changes its visible page.
about: The event source is the page stack and `data` contains its current depth.
End Rem
Global EVENT_UIPAGECHANGED:Int = AllocUserEventId("UIPageChanged")

Private

Extern "C"
	Function _UISin:Double(degrees:Double) = "bmx_ui_sin"
	Function _UICos:Double(degrees:Double) = "bmx_ui_cos"
End Extern

Public

Rem
bbdoc: Mutable colors, typography, borders, and padding for one widget state.
about: Styles are commonly shared through a TUITheme. Use Copy before changing
a shared style when only one widget or state should be affected.
End Rem
Type TUIStyle
	Rem
	bbdoc: Bitmap font used to draw text, or Null to use the graphics default.
	End Rem
	Field font:TBitmapFont
	Rem
	bbdoc: Positive integer scale applied when drawing the style's font.
	End Rem
	Field fontScale:Int = 1
	Rem
	bbdoc: Foreground text and mark color in `$RRGGBB` form.
	End Rem
	Field foreground:UInt = $ffffff
	Rem
	bbdoc: Background fill color in `$RRGGBB` form.
	End Rem
	Field background:UInt
	Rem
	bbdoc: Border color in `$RRGGBB` form.
	End Rem
	Field border:UInt
	Rem
	bbdoc: True when the background color should be drawn.
	End Rem
	Field backgroundVisible:Int
	Rem
	bbdoc: Border thickness in pixels, or zero for no border.
	End Rem
	Field borderWidth:Int
	Rem
	bbdoc: Corner radius in pixels.
	End Rem
	Field cornerRadius:Int
	Rem
	bbdoc: Inner spacing at the left edge in pixels.
	End Rem
	Field paddingLeft:Int
	Rem
	bbdoc: Inner spacing at the top edge in pixels.
	End Rem
	Field paddingTop:Int
	Rem
	bbdoc: Inner spacing at the right edge in pixels.
	End Rem
	Field paddingRight:Int
	Rem
	bbdoc: Inner spacing at the bottom edge in pixels.
	End Rem
	Field paddingBottom:Int

	Rem
	bbdoc: Creates a style with the requested foreground and optional background.
	param: Foreground color in `$RRGGBB` form.
	param: Background color in `$RRGGBB` form.
	param: True to draw the background color.
	returns: A new mutable style.
	End Rem
	Function Create:TUIStyle(foreground:UInt = $ffffff, background:UInt = 0, ..
			backgroundVisible:Int = False)
		Local style:TUIStyle = New TUIStyle
		style.foreground = foreground
		style.background = background
		style.backgroundVisible = backgroundVisible
		Return style
	End Function

	Rem
	bbdoc: Creates an independent copy of this style.
	returns: A new style containing the same visual properties.
	End Rem
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

	Rem
	bbdoc: Sets equal padding on all four edges.
	param: Non-negative padding in pixels.
	End Rem
	Method SetPadding(value:Int)
		SetPaddingEdges(value, value, value, value)
	End Method

	Rem
	bbdoc: Sets the padding of each edge independently.
	param: Left padding in pixels.
	param: Top padding in pixels.
	param: Right padding in pixels.
	param: Bottom padding in pixels.
	End Rem
	Method SetPaddingEdges(left:Int, top:Int, right:Int, bottom:Int)
		paddingLeft = left
		paddingTop = top
		paddingRight = right
		paddingBottom = bottom
	End Method
End Type

Rem
bbdoc: State-aware style collection and interaction metrics for a UI context.
about: A theme supplies the default appearance for containers, text, controls,
cards, headers, navigation, focus, and disabled or pressed states. Individual
widgets may override those styles without changing the theme.
End Rem
Type TUITheme
	Rem
	bbdoc: Style used to clear and draw the screen background.
	End Rem
	Field screen:TUIStyle
	Rem
	bbdoc: Default style for layout containers.
	End Rem
	Field container:TUIStyle
	Rem
	bbdoc: Default style for labels.
	End Rem
	Field label:TUIStyle
	Rem
	bbdoc: Normal button style.
	End Rem
	Field button:TUIStyle
	Rem
	bbdoc: Pressed button style.
	End Rem
	Field buttonPressed:TUIStyle
	Rem
	bbdoc: Disabled button style.
	End Rem
	Field buttonDisabled:TUIStyle
	Rem
	bbdoc: Normal selection-control style.
	End Rem
	Field control:TUIStyle
	Rem
	bbdoc: Active or selected control style.
	End Rem
	Field controlActive:TUIStyle
	Rem
	bbdoc: Pressed control style.
	End Rem
	Field controlPressed:TUIStyle
	Rem
	bbdoc: Disabled control style.
	End Rem
	Field controlDisabled:TUIStyle
	Rem
	bbdoc: Unfilled progress-track style.
	End Rem
	Field progress:TUIStyle
	Rem
	bbdoc: Filled progress-track style.
	End Rem
	Field progressFill:TUIStyle
	Rem
	bbdoc: Default card style.
	End Rem
	Field card:TUIStyle
	Rem
	bbdoc: Default header style.
	End Rem
	Field header:TUIStyle
	Rem
	bbdoc: Default navigation-region style.
	End Rem
	Field navigation:TUIStyle
	Rem
	bbdoc: Focus-outline color in `$RRGGBB` form.
	End Rem
	Field focusColor:UInt = $ffd84a
	Rem
	bbdoc: Focus-outline thickness in pixels.
	End Rem
	Field focusWidth:Int = 2
	Rem
	bbdoc: Gap in pixels between a widget and its focus outline.
	End Rem
	Field focusInset:Int = 2
	Rem
	bbdoc: Minimum automatically measured button height in pixels.
	End Rem
	Field buttonMinimumHeight:Int
	Rem
	bbdoc: Minimum automatically measured selection-row height in pixels.
	End Rem
	Field selectionMinimumHeight:Int

	Rem
	bbdoc: Creates the standard dark embedded UI theme.
	param: Optional bitmap font applied throughout the theme.
	returns: A new fully initialized theme.
	End Rem
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
		theme.card = theme.control.Copy()
		theme.card.background = $17222c
		theme.card.border = $40566a
		theme.card.cornerRadius = 6
		theme.header = TUIStyle.Create($e8edf2)
		theme.navigation = TUIStyle.Create($e8edf2, $17222c, True)
		theme.navigation.border = $40566a
		theme.navigation.borderWidth = 1
		theme.navigation.cornerRadius = 6
		theme.SetFont(font)
		Return theme
	End Function

	Rem
	bbdoc: Applies one font and scale to every style in this theme.
	param: Bitmap font to use, or Null to use the graphics default.
	param: Positive integer glyph scale; values below one are clamped to one.
	End Rem
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
		card.font = font
		header.font = font
		navigation.font = font
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
		card.fontScale = scale
		header.fontScale = scale
		navigation.fontScale = scale
	End Method

	Rem
	bbdoc: Sets the minimum automatically measured button height.
	param: Minimum height in pixels; negative values are clamped to zero.
	about: This keeps touch targets finger-sized independently of the selected
	font. A button with an explicit height still uses that requested height.
	End Rem
	Method SetButtonMinimumHeight(height:Int)
		buttonMinimumHeight = _ClampNonNegative(height)
	End Method

	Rem
	bbdoc: Sets the minimum automatically measured selection-control height.
	param: Minimum height in pixels; negative values are clamped to zero.
	about: This applies to combo boxes and selectable list or popup rows, keeping
	the closed control and its dropdown choices finger-sized independently of the
	font. An explicit widget height still takes precedence.
	End Rem
	Method SetSelectionMinimumHeight(height:Int)
		selectionMinimumHeight = _ClampNonNegative(height)
	End Method
End Type

Private

Global _uiControlFactory:TUIControlFactory

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
	graphics.DrawArc(centerX, centerY, radius, startDegrees, sweepDegrees, width)
End Function

Function _UIDrawImageRect(graphics:TEmbedded2DContext, image:TEmbeddedImage, ..
		x:Int, y:Int, width:Int, height:Int)
	If graphics And image And width > 0 And height > 0 Then ..
		graphics.DrawImageRect(image, x, y, width, height)
End Function

Public

Rem
bbdoc: Base class for every retained UI element.
about: A widget stores requested layout properties and the bounds assigned by
its parent. Applications normally configure widgets through their methods;
subclasses override PreferredSize, Draw, and the optional interaction hooks to
provide new visual elements or controls.
End Rem
Type TUIWidget
	Public
	Rem
	bbdoc: Context currently owning this widget, or Null while detached.
	End Rem
	Field uiContext:TUIContext
	Rem
	bbdoc: Parent container, or Null for a root or detached widget.
	End Rem
	Field uiParent:TUIContainer
	Rem
	bbdoc: Child widget array used by container subclasses.
	about: Applications should use ChildCount and Child to inspect this array,
and TUIContainer.Add to attach children.
	End Rem
	Field uiChildren:TUIWidget[] = New TUIWidget[0]
	Rem
	bbdoc: Optional widget-specific style override.
	End Rem
	Field uiStyle:TUIStyle
	Rem
	bbdoc: Assigned left coordinate in display pixels.
	End Rem
	Field uiX:Int
	Rem
	bbdoc: Assigned top coordinate in display pixels.
	End Rem
	Field uiY:Int
	Rem
	bbdoc: Assigned width in display pixels.
	End Rem
	Field uiWidth:Int
	Rem
	bbdoc: Assigned height in display pixels.
	End Rem
	Field uiHeight:Int
	Rem
	bbdoc: Requested width in pixels, UILayoutAuto, or UILayoutFill.
	End Rem
	Field requestedWidth:Int = UILayoutAuto
	Rem
	bbdoc: Requested height in pixels, UILayoutAuto, or UILayoutFill.
	End Rem
	Field requestedHeight:Int = UILayoutAuto
	Rem
	bbdoc: Relative share of spare space on the parent container's main axis.
	End Rem
	Field growWeight:Int
	Rem
	bbdoc: Cross-axis alignment requested from the parent container.
	End Rem
	Field alignSelf:Int = UIAlignStretch
	Rem
	bbdoc: Outer spacing at the left edge in pixels.
	End Rem
	Field marginLeft:Int
	Rem
	bbdoc: Outer spacing at the top edge in pixels.
	End Rem
	Field marginTop:Int
	Rem
	bbdoc: Outer spacing at the right edge in pixels.
	End Rem
	Field marginRight:Int
	Rem
	bbdoc: Outer spacing at the bottom edge in pixels.
	End Rem
	Field marginBottom:Int
	Rem
	bbdoc: True when the widget participates in layout and drawing.
	End Rem
	Field visible:Int = True
	Rem
	bbdoc: True when the widget may receive focus and interaction.
	End Rem
	Field enabled:Int = True
	Rem
	bbdoc: Current pointer-pressed visual state.
	End Rem
	Field pressed:Int
	Rem
	bbdoc: True when hit testing may treat the widget as clickable.
	End Rem
	Field clickable:Int
	Rem
	bbdoc: True when the widget may receive UI focus.
	End Rem
	Field focusable:Int
	Rem
	bbdoc: True when focus should be represented by the theme outline.
	End Rem
	Field focusIndicatorVisible:Int = True
	Rem
	bbdoc: Number of grid columns occupied by this widget.
	End Rem
	Field gridColumnSpan:Int = 1

	Public
	Rem
	bbdoc: Returns the context currently owning this widget.
	returns: The owning context, or Null while detached.
	End Rem
	Method Context:TUIContext() Final
		Return uiContext
	End Method

	Rem
	bbdoc: Returns this widget's parent container.
	returns: The parent, or Null for a root or detached widget.
	End Rem
	Method Parent:TUIContainer() Final
		Return uiParent
	End Method

	Rem
	bbdoc: Returns the number of direct children.
	returns: The number of entries accessible through Child.
	End Rem
	Method ChildCount:Int() Final
		Return uiChildren.Length
	End Method

	Rem
	bbdoc: Returns one direct child by index.
	param: Zero-based child index.
	returns: The requested widget, or Null when the index is outside the array.
	End Rem
	Method Child:TUIWidget(index:Int) Final
		If index < 0 Or index >= uiChildren.Length Then Return Null
		Return uiChildren[index]
	End Method

	Rem
	bbdoc: Returns the assigned left coordinate in display pixels.
	returns: The current x coordinate.
	End Rem
	Method X:Int() Final
		Return uiX
	End Method

	Rem
	bbdoc: Returns the assigned top coordinate in display pixels.
	returns: The current y coordinate.
	End Rem
	Method Y:Int() Final
		Return uiY
	End Method

	Rem
	bbdoc: Returns the assigned width in display pixels.
	returns: The current width.
	End Rem
	Method Width:Int() Final
		Return uiWidth
	End Method

	Rem
	bbdoc: Returns the assigned height in display pixels.
	returns: The current height.
	End Rem
	Method Height:Int() Final
		Return uiHeight
	End Method

	Rem
	bbdoc: Sets the requested layout width.
	param: Pixel width, UILayoutAuto, or UILayoutFill.
	End Rem
	Method SetWidth(width:Int)
		If width < 0 And width <> UILayoutAuto And width <> UILayoutFill Then width = 0
		If requestedWidth = width Then Return
		requestedWidth = width
		_RequestLayout()
	End Method

	Rem
	bbdoc: Sets the requested layout height.
	param: Pixel height, UILayoutAuto, or UILayoutFill.
	End Rem
	Method SetHeight(height:Int)
		If height < 0 And height <> UILayoutAuto And height <> UILayoutFill Then height = 0
		If requestedHeight = height Then Return
		requestedHeight = height
		_RequestLayout()
	End Method

	Rem
	bbdoc: Sets both requested layout dimensions.
	param: Pixel width, UILayoutAuto, or UILayoutFill.
	param: Pixel height, UILayoutAuto, or UILayoutFill.
	End Rem
	Method SetSize(width:Int, height:Int)
		SetWidth(width)
		SetHeight(height)
	End Method

	Rem
	bbdoc: Sets this widget's relative share of spare main-axis space.
	param: Non-negative growth weight; zero disables weighted growth.
	End Rem
	Method SetGrow(weight:Int = 1)
		weight = _ClampNonNegative(weight)
		If growWeight = weight Then Return
		growWeight = weight
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the current layout growth weight.
	returns: The non-negative growth weight.
	End Rem
	Method Grow:Int()
		Return growWeight
	End Method

	Rem
	bbdoc: Sets this widget's alignment on its parent's cross axis.
	param: One of the UIAlign constants.
	End Rem
	Method SetAlign(align:Int)
		If align < UIAlignStart Or align > UIAlignStretch Then align = UIAlignStretch
		If alignSelf = align Then Return
		alignSelf = align
		_RequestLayout()
	End Method

	Rem
	bbdoc: Sets equal outer spacing on all four edges.
	param: Non-negative margin in pixels.
	End Rem
	Method SetMargin(value:Int)
		SetMarginEdges(value, value, value, value)
	End Method

	Rem
	bbdoc: Sets each outer margin independently.
	param: Left margin in pixels.
	param: Top margin in pixels.
	param: Right margin in pixels.
	param: Bottom margin in pixels.
	End Rem
	Method SetMarginEdges(left:Int, top:Int, right:Int, bottom:Int)
		marginLeft = _ClampNonNegative(left)
		marginTop = _ClampNonNegative(top)
		marginRight = _ClampNonNegative(right)
		marginBottom = _ClampNonNegative(bottom)
		_RequestLayout()
	End Method

	Rem
	bbdoc: Sets the number of columns occupied by this widget in a TUIGrid.
	param: Column count, clamped between one and UIGridMaximumColumns.
	about: Other container types ignore this value.
	End Rem
	Method SetGridSpan(columns:Int)
		If columns < 1 Then columns = 1
		If columns > UIGridMaximumColumns Then columns = UIGridMaximumColumns
		If gridColumnSpan = columns Then Return
		gridColumnSpan = columns
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the grid-column span requested by this widget.
	returns: The positive column count.
	End Rem
	Method GridSpan:Int()
		Return gridColumnSpan
	End Method

	Rem
	bbdoc: Shows or hides this widget.
	param: True to include the widget in layout, drawing, and hit testing.
	End Rem
	Method SetVisible(value:Int)
		value = value <> 0
		If visible = value Then Return
		_Invalidate()
		visible = value
		If Not visible And uiContext Then uiContext._ReleaseFocus(Self)
		_RequestLayout()
	End Method

	Rem
	bbdoc: Reports whether this widget is visible.
	returns: True when the widget participates in layout and drawing.
	End Rem
	Method Visible:Int()
		Return visible
	End Method

	Rem
	bbdoc: Enables or disables interaction with this widget.
	param: True to permit focus and activation.
	End Rem
	Method SetEnabled(value:Int)
		value = value <> 0
		If enabled = value Then Return
		enabled = value
		If Not enabled Then pressed = False
		If Not enabled And uiContext Then uiContext._ReleaseFocus(Self)
		_Invalidate()
	End Method

	Rem
	bbdoc: Reports whether this widget is enabled.
	returns: True when interaction is permitted.
	End Rem
	Method Enabled:Int()
		Return enabled
	End Method

	Rem
	bbdoc: Reports whether this widget is currently pressed.
	returns: True while an armed pointer press is active.
	End Rem
	Method Pressed:Int()
		Return pressed
	End Method

	Rem
	bbdoc: Adds or removes this widget from focus traversal.
	param: True to permit focus.
	End Rem
	Method SetFocusable(value:Int)
		value = value <> 0
		If focusable = value Then Return
		focusable = value
		If Not focusable And uiContext Then uiContext._ReleaseFocus(Self)
		_Invalidate()
	End Method

	Rem
	bbdoc: Reports whether this widget may receive focus.
	returns: True when focus is permitted.
	End Rem
	Method Focusable:Int()
		Return focusable
	End Method

	Rem
	bbdoc: Controls whether this widget draws the theme focus indicator.
	param: True to draw the focus outline while focused.
	about: Hiding the indicator does not remove the widget from focus traversal.
	End Rem
	Method SetFocusIndicatorVisible(value:Int)
		value = value <> 0
		If focusIndicatorVisible = value Then Return
		focusIndicatorVisible = value
		_Invalidate()
	End Method

	Rem
	bbdoc: Reports whether the focus indicator is enabled for this widget.
	returns: True when focused state should be outlined.
	End Rem
	Method FocusIndicatorVisible:Int()
		Return focusIndicatorVisible
	End Method

	Rem
	bbdoc: Reports whether this is the context's focused widget.
	returns: True when this widget currently owns focus.
	End Rem
	Method Focused:Int()
		Return uiContext And uiContext.FocusedWidget() = Self
	End Method

	Rem
	bbdoc: Requests focus for this widget.
	returns: True when focus was assigned.
	End Rem
	Method RequestFocus:Int()
		If Not uiContext Then Return False
		Return uiContext.SetFocus(Self)
	End Method

	Rem
	bbdoc: Returns this widget's mutable style override.
	returns: The existing override, or a new copy of DefaultStyle.
	End Rem
	Method Style:TUIStyle()
		If Not uiStyle Then uiStyle = DefaultStyle().Copy()
		Return uiStyle
	End Method

	Rem
	bbdoc: Replaces this widget's style override.
	param: Custom style, or Null to resume using DefaultStyle.
	End Rem
	Method SetStyle(style:TUIStyle)
		_Invalidate()
		uiStyle = style
		_RequestLayout()
	End Method

	Rem
	bbdoc: Marks this widget's visible bounds for redrawing.
	End Rem
	Method Invalidate()
		_Invalidate()
	End Method

	Rem
	bbdoc: Tests a display coordinate against this widget's visible bounds.
	param: Display x coordinate in pixels.
	param: Display y coordinate in pixels.
	returns: True when the visible widget contains the point.
	End Rem
	Method Contains:Int(x:Int, y:Int)
		Return visible And x >= uiX And y >= uiY And x < uiX + uiWidth And y < uiY + uiHeight
	End Method

	Rem
	bbdoc: Returns the inherited style used when no override is installed.
	returns: The context's container style, or a basic standalone style.
	End Rem
	Method DefaultStyle:TUIStyle()
		If uiContext And uiContext.Theme() Then Return uiContext.Theme().container
		Return TUIStyle.Create()
	End Method

	Rem
	bbdoc: Measures the widget within the available layout space.
	param: Available width in pixels.
	param: Available height in pixels.
	param: Receives the preferred width in pixels.
	param: Receives the preferred height in pixels.
	about: Custom widgets override this method to report their natural size while
honoring explicit requested dimensions.
	End Rem
	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var)
		width = 0
		height = 0
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Rem
	bbdoc: Draws the widget's normal content.
	param: Graphics context configured for the current presentation pass.
	about: Custom widgets should draw only inside their assigned bounds.
	End Rem
	Method Draw(graphics:TEmbedded2DContext)
	End Method

	Rem
	bbdoc: Draws content that must appear after descendant widgets.
	param: Graphics context configured for the current presentation pass.
	End Rem
	Method DrawOverlay(graphics:TEmbedded2DContext)
	End Method

	Rem
	bbdoc: Reports whether descendants are clipped to this widget's bounds.
	returns: True when drawing and invalidation must respect these bounds.
	End Rem
	Method ClipsChildren:Int()
		Return False
	End Method

	Public
	Rem
	bbdoc: Attaches this widget tree to a context and parent.
	param: Owning UI context.
	param: Parent container, or Null for a root widget.
	about: This is an extension hook used by containers and custom adapters.
	End Rem
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

	Rem
	bbdoc: Assigns the bounds calculated by the layout engine.
	param: Left coordinate in pixels.
	param: Top coordinate in pixels.
	param: Width in pixels.
	param: Height in pixels.
	End Rem
	Method _SetBounds(x:Int, y:Int, width:Int, height:Int)
		If uiX = x And uiY = y And uiWidth = width And uiHeight = height Then Return
		_Invalidate()
		uiX = x
		uiY = y
		uiWidth = _ClampNonNegative(width)
		uiHeight = _ClampNonNegative(height)
		_Invalidate()
	End Method

	Rem
	bbdoc: Invalidates the visible, ancestor-clipped portion of this widget.
	End Rem
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

	Rem
	bbdoc: Requests a new measure and layout pass from the owning context.
	End Rem
	Method _RequestLayout()
		If uiContext Then uiContext.RequestLayout()
	End Method

	Rem
	bbdoc: Updates the pressed visual state used by input adapters.
	param: True while the widget is armed by an active pointer.
	End Rem
	Method _SetPressed(value:Int)
		value = value <> 0
		If pressed = value Then Return
		pressed = value
		_Invalidate()
	End Method

	' Optional interaction hooks. Passive widgets retain the no-op defaults;
	' controls override only the operations which they support.
	Rem
	bbdoc: Activates this widget through non-pointer focus input.
	returns: True when the activation was handled.
	End Rem
	Method _ActivateFocused:Int()
		Return False
	End Method

	Rem
	bbdoc: Adjusts this widget through non-pointer focus input.
	param: Signed adjustment amount.
	returns: True when the adjustment was handled.
	End Rem
	Method _AdjustFocused:Int(delta:Int)
		Return False
	End Method

	Rem
	bbdoc: Begins pointer tracking for an interactive widget.
	param: Display x coordinate in pixels.
	param: Display y coordinate in pixels.
	returns: True when the initial pointer position was handled.
	End Rem
	Method _BeginPointer:Int(x:Int, y:Int)
		Return False
	End Method

	Rem
	bbdoc: Updates an active pointer interaction.
	param: Display x coordinate in pixels.
	param: Display y coordinate in pixels.
	returns: True when the position was handled directly.
	End Rem
	Method _TrackPointer:Int(x:Int, y:Int)
		Return False
	End Method

	Rem
	bbdoc: Ends pointer tracking without necessarily activating the widget.
	End Rem
	Method _EndPointer()
	End Method

	Rem
	bbdoc: Activates this widget at a released pointer coordinate.
	param: Display x coordinate in pixels.
	param: Display y coordinate in pixels.
	returns: True when activation was handled.
	End Rem
	Method _ActivatePointer:Int(x:Int, y:Int)
		Return _ActivateFocused()
	End Method
End Type

Rem
bbdoc: Optional constructor provider for interactive widget families.
about: Embedded.UI.Controls installs the standard provider. Keeping concrete
control construction behind this boundary lets display-only firmware omit
controls which it never creates while retaining the fluent container API.
End Rem
Type TUIControlFactory
	Rem
	bbdoc: Creates a list control, or Null when unsupported.
	returns: A new detached list.
	End Rem
	Method CreateList:TUIList()
		Return Null
	End Method

	Rem
	bbdoc: Creates a tab view, or Null when unsupported.
	returns: A new detached tab view.
	End Rem
	Method CreateTabView:TUITabView()
		Return Null
	End Method

	Rem
	bbdoc: Creates a button, or Null when unsupported.
	returns: A new detached button.
	End Rem
	Method CreateButton:TUIButton()
		Return Null
	End Method

	Rem
	bbdoc: Creates a combo box, or Null when unsupported.
	returns: A new detached combo box.
	End Rem
	Method CreateComboBox:TUIComboBox()
		Return Null
	End Method

	Rem
	bbdoc: Creates a check box, or Null when unsupported.
	returns: A new detached check box.
	End Rem
	Method CreateCheckBox:TUICheckBox()
		Return Null
	End Method

	Rem
	bbdoc: Creates a radio group, or Null when unsupported.
	returns: A new detached radio group.
	End Rem
	Method CreateRadioGroup:TUIRadioGroup()
		Return Null
	End Method

	Rem
	bbdoc: Creates a numeric stepper, or Null when unsupported.
	returns: A new detached stepper.
	End Rem
	Method CreateStepper:TUIStepper()
		Return Null
	End Method

	Rem
	bbdoc: Creates a segmented control, or Null when unsupported.
	returns: A new detached segmented control.
	End Rem
	Method CreateSegmentedControl:TUISegmentedControl()
		Return Null
	End Method

	Rem
	bbdoc: Creates a switch, or Null when unsupported.
	returns: A new detached switch.
	End Rem
	Method CreateSwitch:TUISwitch()
		Return Null
	End Method

	Rem
	bbdoc: Creates a slider, or Null when unsupported.
	returns: A new detached slider.
	End Rem
	Method CreateSlider:TUISlider()
		Return Null
	End Method

	Rem
	bbdoc: Creates a rotary dial, or Null when unsupported.
	returns: A new detached dial.
	End Rem
	Method CreateRotaryDial:TUIRotaryDial()
		Return Null
	End Method

	Rem
	bbdoc: Creates a popup menu, or Null when unsupported.
	returns: A new detached popup menu.
	End Rem
	Method CreatePopupMenu:TUIPopupMenu()
		Return Null
	End Method

	Rem
	bbdoc: Creates a dialog, or Null when unsupported.
	returns: A new detached dialog.
	End Rem
	Method CreateDialog:TUIDialog()
		Return Null
	End Method
End Type

Private

Type TUIStandardControlFactory Extends TUIControlFactory Final
	Method CreateList:TUIList() Override
		Return New TUIList
	End Method

	Method CreateTabView:TUITabView() Override
		Return New TUITabView
	End Method

	Method CreateButton:TUIButton() Override
		Return New TUIButton
	End Method

	Method CreateComboBox:TUIComboBox() Override
		Return New TUIComboBox
	End Method

	Method CreateCheckBox:TUICheckBox() Override
		Return New TUICheckBox
	End Method

	Method CreateRadioGroup:TUIRadioGroup() Override
		Return New TUIRadioGroup
	End Method

	Method CreateStepper:TUIStepper() Override
		Return New TUIStepper
	End Method

	Method CreateSegmentedControl:TUISegmentedControl() Override
		Return New TUISegmentedControl
	End Method

	Method CreateSwitch:TUISwitch() Override
		Return New TUISwitch
	End Method

	Method CreateSlider:TUISlider() Override
		Return New TUISlider
	End Method

	Method CreateRotaryDial:TUIRotaryDial() Override
		Return New TUIRotaryDial
	End Method

	Method CreatePopupMenu:TUIPopupMenu() Override
		Return New TUIPopupMenu
	End Method

	Method CreateDialog:TUIDialog() Override
		Return New TUIDialog
	End Method
End Type

Public

Rem
bbdoc: Installs the standard interactive-control constructors.
about: Embedded.UI.Controls calls this automatically. Display-only firmware
can omit that module so the linker can discard the control implementation.
End Rem
Function InstallStandardUIControls()
	If Not _uiControlFactory Then
		RegisterUIControlFactory(New TUIStandardControlFactory)
	End If
End Function

Rem
bbdoc: Installs the interactive-control constructor provider.
param: Provider used by fluent container construction methods.
about: Applications normally obtain this automatically by importing
Embedded.UI.Controls or Embedded.UI.Interactive.
End Rem
Function RegisterUIControlFactory(factory:TUIControlFactory)
	_uiControlFactory = factory
End Function

Rem
bbdoc: Reports whether an interactive-control provider is installed.
returns: True after Embedded.UI.Controls or Embedded.UI.Interactive is imported.
End Rem
Function UIControlsAvailable:Int()
	Return _uiControlFactory <> Null
End Function

Private

Function _UIRequireControls:TUIControlFactory()
	If Not _uiControlFactory Then RuntimeError ..
		"Interactive UI controls require Import Embedded.UI.Controls"
	Return _uiControlFactory
End Function

Public

Rem
bbdoc: Base container that owns child widgets and arranges them as a stack, row, or column.
about: TUIContainer also provides fluent constructors. Interactive constructors
require Embedded.UI.Controls; display-only containers and widgets do not.
End Rem
Type TUIContainer Extends TUIWidget
	Public
	Rem
	bbdoc: Internal layout mode: stack, row, or column.
	End Rem
	Field layoutDirection:Int
	Rem
	bbdoc: Spacing between adjacent visible children in pixels.
	End Rem
	Field gap:Int
	Rem
	bbdoc: Inner spacing at the left edge in pixels.
	End Rem
	Field paddingLeft:Int
	Rem
	bbdoc: Inner spacing at the top edge in pixels.
	End Rem
	Field paddingTop:Int
	Rem
	bbdoc: Inner spacing at the right edge in pixels.
	End Rem
	Field paddingRight:Int
	Rem
	bbdoc: Inner spacing at the bottom edge in pixels.
	End Rem
	Field paddingBottom:Int
	Rem
	bbdoc: True when the container explicitly draws its background.
	End Rem
	Field drawBackground:Int

	Public
	Rem
	bbdoc: Sets the spacing between adjacent visible children.
	param: Non-negative gap in pixels.
	End Rem
	Method SetGap(value:Int)
		value = _ClampNonNegative(value)
		If gap = value Then Return
		gap = value
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the spacing between adjacent visible children.
	returns: The gap in pixels.
	End Rem
	Method Gap:Int()
		Return gap
	End Method

	Rem
	bbdoc: Sets equal inner spacing on all four edges.
	param: Non-negative padding in pixels.
	End Rem
	Method SetPadding(value:Int)
		SetPaddingEdges(value, value, value, value)
	End Method

	Rem
	bbdoc: Sets each inner padding edge independently.
	param: Left padding in pixels.
	param: Top padding in pixels.
	param: Right padding in pixels.
	param: Bottom padding in pixels.
	End Rem
	Method SetPaddingEdges(left:Int, top:Int, right:Int, bottom:Int)
		paddingLeft = _ClampNonNegative(left)
		paddingTop = _ClampNonNegative(top)
		paddingRight = _ClampNonNegative(right)
		paddingBottom = _ClampNonNegative(bottom)
		_RequestLayout()
	End Method

	Rem
	bbdoc: Controls whether the container explicitly draws its style background.
	param: True to draw the background even when the style does not request it.
	End Rem
	Method SetBackgroundVisible(value:Int)
		drawBackground = value <> 0
		_Invalidate()
	End Method

	Rem
	bbdoc: Appends a detached widget to this container.
	param: Widget without an existing parent.
	returns: The attached widget, or Null when it cannot be added.
	End Rem
	Method Add:TUIWidget(widget:TUIWidget)
		If Not widget Or widget.Parent() Then Return Null
		uiChildren = uiChildren[..uiChildren.Length + 1]
		uiChildren[uiChildren.Length - 1] = widget
		widget._Attach(Context(), Self)
		_RequestLayout()
		Return widget
	End Method

	Rem
	bbdoc: Adds a horizontal row container.
	returns: The attached row.
	End Rem
	Method Row:TUIRow() Final
		Local widget:TUIRow = New TUIRow
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a vertical column container.
	returns: The attached column.
	End Rem
	Method Column:TUIColumn() Final
		Local widget:TUIColumn = New TUIColumn
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an overlapping stack container.
	returns: The attached stack.
	End Rem
	Method Stack:TUIStack() Final
		Local widget:TUIStack = New TUIStack
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a vertically scrollable container.
	returns: The attached scroll view.
	End Rem
	Method ScrollView:TUIScrollView() Final
		Local widget:TUIScrollView = New TUIScrollView
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive selectable list.
	returns: The attached list.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method List:TUIList() Final
		Local widget:TUIList = _UIRequireControls().CreateList()
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive tab view.
	returns: The attached tab view.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method TabView:TUITabView() Final
		Local widget:TUITabView = _UIRequireControls().CreateTabView()
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a bounded navigation page stack.
	returns: The attached page stack.
	End Rem
	Method PageStack:TUIPageStack() Final
		Local widget:TUIPageStack = New TUIPageStack
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a responsive equal-cell grid.
	param: Fixed column count, or zero to derive it from available width.
	returns: The attached grid.
	End Rem
	Method Grid:TUIGrid(columns:Int = 0) Final
		Local widget:TUIGrid = New TUIGrid
		widget.SetColumns(columns)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a styled card container.
	param: Optional card title.
	returns: The attached card.
	End Rem
	Method Card:TUICard(title:String = "") Final
		Local widget:TUICard = New TUICard
		widget.SetTitle(title)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a page header.
	param: Header title.
	param: True to reserve and draw the back affordance.
	returns: The attached header.
	End Rem
	Method Header:TUIHeader(title:String = "", showBack:Int = False) Final
		Local widget:TUIHeader = New TUIHeader
		widget.SetTitle(title)
		widget.SetBackVisible(showBack)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a navigation-bar container.
	returns: The attached navigation bar.
	End Rem
	Method NavigationBar:TUINavigationBar() Final
		Local widget:TUINavigationBar = New TUINavigationBar
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a text label.
	param: Initial text.
	returns: The attached label.
	End Rem
	Method Label:TUILabel(text:String = "") Final
		Local widget:TUILabel = New TUILabel
		widget.SetText(text)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive button.
	param: Initial button label.
	returns: The attached button.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method Button:TUIButton(text:String = "") Final
		Local widget:TUIButton = _UIRequireControls().CreateButton()
		widget.SetText(text)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive combo box.
	returns: The attached combo box.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method ComboBox:TUIComboBox() Final
		Local widget:TUIComboBox = _UIRequireControls().CreateComboBox()
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive check box.
	param: Label displayed beside the check mark.
	param: Initial checked state.
	returns: The attached check box.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method CheckBox:TUICheckBox(text:String = "", checked:Int = False) Final
		Local widget:TUICheckBox = _UIRequireControls().CreateCheckBox()
		widget.SetText(text)
		widget.SetChecked(checked)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive radio-button group.
	returns: The attached group.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method RadioGroup:TUIRadioGroup() Final
		Local widget:TUIRadioGroup = _UIRequireControls().CreateRadioGroup()
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an integer stepper control.
	param: Minimum permitted value.
	param: Maximum permitted value.
	param: Initial value.
	param: Positive increment used by each step.
	returns: The attached stepper.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method Stepper:TUIStepper(minimum:Int = 0, maximum:Int = 100, value:Int = 0, step:Int = 1) Final
		Local widget:TUIStepper = _UIRequireControls().CreateStepper()
		widget.SetRange(minimum, maximum)
		widget.SetStep(step)
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a fixed-precision decimal stepper control.
	param: Minimum permitted value.
	param: Maximum permitted value.
	param: Initial value.
	param: Positive increment used by each step.
	param: Number of displayed decimal places.
	returns: The attached stepper.
	about: Decimal values are represented internally as scaled integers. Requires
Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method DecimalStepper:TUIStepper(minimum:Double = 0.0, maximum:Double = 100.0, ..
			value:Double = 0.0, step:Double = 1.0, decimalPlaces:Int = 1) Final
		Local widget:TUIStepper = _UIRequireControls().CreateStepper()
		widget.ConfigureDecimal(minimum, maximum, value, step, decimalPlaces)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive segmented selection control.
	returns: The attached control.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method SegmentedControl:TUISegmentedControl() Final
		Local widget:TUISegmentedControl = _UIRequireControls().CreateSegmentedControl()
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive Boolean switch.
	param: Initial on or off value.
	returns: The attached switch.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method Switch:TUISwitch(value:Int = False) Final
		Local widget:TUISwitch = _UIRequireControls().CreateSwitch()
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive linear slider.
	param: Minimum permitted value.
	param: Maximum permitted value.
	param: Initial value.
	returns: The attached slider.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method Slider:TUISlider(minimum:Int = 0, maximum:Int = 100, value:Int = 0) Final
		Local widget:TUISlider = _UIRequireControls().CreateSlider()
		widget.SetRange(minimum, maximum)
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a read-only linear progress indicator.
	param: Minimum represented value.
	param: Maximum represented value.
	param: Initial value.
	returns: The attached progress bar.
	End Rem
	Method ProgressBar:TUIProgressBar(minimum:Int = 0, maximum:Int = 100, value:Int = 0) Final
		Local widget:TUIProgressBar = New TUIProgressBar
		widget.SetRange(minimum, maximum)
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a labeled read-only status indicator.
	param: Initial status text.
	param: Initial active state.
	returns: The attached indicator.
	End Rem
	Method StatusIndicator:TUIStatusIndicator(text:String = "", active:Int = False) Final
		Local widget:TUIStatusIndicator = New TUIStatusIndicator
		widget.SetText(text)
		widget.SetActive(active)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a read-only arc gauge.
	param: Minimum represented value.
	param: Maximum represented value.
	param: Initial value.
	returns: The attached gauge.
	End Rem
	Method ArcGauge:TUIArcGauge(minimum:Int = 0, maximum:Int = 100, value:Int = 0) Final
		Local widget:TUIArcGauge = New TUIArcGauge
		widget.SetRange(minimum, maximum)
		widget.SetValue(value)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds a compact read-only history graph.
	param: Maximum number of retained samples.
	returns: The attached sparkline.
	End Rem
	Method Sparkline:TUISparkline(capacity:Int = 32) Final
		Local widget:TUISparkline = New TUISparkline
		widget.SetCapacity(capacity)
		Add(widget)
		Return widget
	End Method

	Rem
	bbdoc: Adds an interactive rotary dial.
	param: Minimum permitted value.
	param: Maximum permitted value.
	param: Initial value.
	returns: The attached dial.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method RotaryDial:TUIRotaryDial(minimum:Int = 0, maximum:Int = 100, value:Int = 0) Final
		Local widget:TUIRotaryDial = _UIRequireControls().CreateRotaryDial()
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
	Rem
	bbdoc: Assigns bounds to this container's visible children.
	about: Container subclasses override this extension hook to implement a
specialized layout algorithm, then recursively lay out child containers.
	End Rem
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

Rem
bbdoc: Container that arranges visible children from left to right.
about: Fixed-size children use their preferred widths. UILayoutFill and positive
growth weights divide the remaining horizontal space.
End Rem
Type TUIRow Extends TUIContainer Final
	Rem
	bbdoc: Initializes horizontal child layout.
	End Rem
	Method New()
		layoutDirection = 1
	End Method
End Type

Rem
bbdoc: Container that arranges visible children from top to bottom.
about: Fixed-size children use their preferred heights. UILayoutFill and
positive growth weights divide the remaining vertical space.
End Rem
Type TUIColumn Extends TUIContainer Final
	Rem
	bbdoc: Initializes vertical child layout.
	End Rem
	Method New()
		layoutDirection = 2
	End Method
End Type

Rem
bbdoc: Container that overlays its visible children in the same content area.
about: Children are drawn in insertion order, allowing later children to appear
above earlier children.
End Rem
Type TUIStack Extends TUIContainer Final
	Rem
	bbdoc: Initializes overlapping child layout.
	End Rem
	Method New()
		layoutDirection = 0
	End Method
End Type

Rem
bbdoc: Responsive equal-cell layout for dashboard tiles and compact control groups.
about: Set a fixed column count, or leave it at zero and use the minimum column
width to derive the count from the available space. Children may span columns.
End Rem
Type TUIGrid Extends TUIContainer Final
	Private
	Field configuredColumns:Int
	Field minimumColumnWidth:Int = 120
	Field configuredRowHeight:Int

	Public
	Rem
	bbdoc: Initializes a grid with responsive column selection enabled.
	End Rem
	Method New()
		layoutDirection = 0
	End Method

	Rem
	bbdoc: Sets a fixed column count or enables responsive column selection.
	param: Fixed count from one to UIGridMaximumColumns, or zero for automatic.
	End Rem
	Method SetColumns(columns:Int)
		If columns < 0 Then columns = 0
		If columns > UIGridMaximumColumns Then columns = UIGridMaximumColumns
		If configuredColumns = columns Then Return
		configuredColumns = columns
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the configured column count.
	returns: The fixed count, or zero when columns are selected responsively.
	End Rem
	Method Columns:Int()
		Return configuredColumns
	End Method

	Rem
	bbdoc: Sets the minimum cell width used by responsive column selection.
	param: Positive width in pixels.
	End Rem
	Method SetMinimumColumnWidth(width:Int)
		If width < 1 Then width = 1
		If minimumColumnWidth = width Then Return
		minimumColumnWidth = width
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the responsive minimum column width.
	returns: The positive width in pixels.
	End Rem
	Method MinimumColumnWidth:Int()
		Return minimumColumnWidth
	End Method

	Rem
	bbdoc: Sets a fixed row height or enables content-based row measurement.
	param: Fixed height in pixels, or zero for automatic measurement.
	End Rem
	Method SetRowHeight(height:Int)
		If height < 0 Then height = 0
		If configuredRowHeight = height Then Return
		configuredRowHeight = height
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the configured row height.
	returns: The fixed height in pixels, or zero for automatic measurement.
	End Rem
	Method RowHeight:Int()
		Return configuredRowHeight
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		Local contentWidth:Int = Max(availableWidth - paddingLeft - paddingRight, 0)
		Local columns:Int = _ResolvedColumns(contentWidth)
		Local columnWidth:Int = _ColumnWidth(contentWidth, columns)
		Local rowHeight:Int = _ResolvedRowHeight(columnWidth, availableHeight)
		Local rows:Int = _RowCount(columns)
		width = contentWidth + paddingLeft + paddingRight
		height = rows * rowHeight + Max(rows - 1, 0) * gap + paddingTop + paddingBottom
		If requestedWidth >= 0 Then width = requestedWidth
		If requestedHeight >= 0 Then height = requestedHeight
	End Method

	Method _LayoutChildren() Override
		Local contentX:Int = X() + paddingLeft
		Local contentY:Int = Y() + paddingTop
		Local contentWidth:Int = Max(Width() - paddingLeft - paddingRight, 0)
		Local contentHeight:Int = Max(Height() - paddingTop - paddingBottom, 0)
		Local columns:Int = _ResolvedColumns(contentWidth)
		Local columnWidth:Int = _ColumnWidth(contentWidth, columns)
		Local rowHeight:Int = _ResolvedRowHeight(columnWidth, contentHeight)
		Local column:Int
		Local row:Int
		For Local child:TUIWidget = EachIn uiChildren
			If Not child.Visible() Then Continue
			Local span:Int = Min(Max(child.gridColumnSpan, 1), columns)
			If column > 0 And column + span > columns Then
				row :+ 1
				column = 0
			End If
			Local cellX:Int = contentX + column * (columnWidth + gap)
			Local cellY:Int = contentY + row * (rowHeight + gap)
			Local cellWidth:Int = columnWidth * span + gap * (span - 1)
			If column + span = columns Then cellWidth = Max(contentX + contentWidth - cellX, 0)
			Local childWidth:Int = Max(cellWidth - child.marginLeft - child.marginRight, 0)
			Local childHeight:Int = Max(rowHeight - child.marginTop - child.marginBottom, 0)
			child._SetBounds(cellX + child.marginLeft, cellY + child.marginTop, childWidth, childHeight)
			Local container:TUIContainer = TUIContainer(child)
			If container Then container._LayoutChildren()
			column :+ span
			If column >= columns Then
				row :+ 1
				column = 0
			End If
		Next
	End Method

	Private
	Method _ResolvedColumns:Int(contentWidth:Int)
		If configuredColumns > 0 Then Return configuredColumns
		Return Min(Max((contentWidth + gap) / Max(minimumColumnWidth + gap, 1), 1), ..
			UIGridMaximumColumns)
	End Method

	Method _ColumnWidth:Int(contentWidth:Int, columns:Int)
		Return Max((contentWidth - gap * Max(columns - 1, 0)) / Max(columns, 1), 0)
	End Method

	Method _ResolvedRowHeight:Int(columnWidth:Int, availableHeight:Int)
		If configuredRowHeight > 0 Then Return configuredRowHeight
		Local height:Int
		For Local child:TUIWidget = EachIn uiChildren
			If Not child.Visible() Then Continue
			Local preferredWidth:Int
			Local preferredHeight:Int
			child.PreferredSize(columnWidth * Max(child.gridColumnSpan, 1), availableHeight, ..
				preferredWidth, preferredHeight)
			height = Max(height, preferredHeight + child.marginTop + child.marginBottom)
		Next
		Return height
	End Method

	Method _RowCount:Int(columns:Int)
		Local rows:Int
		Local column:Int
		For Local child:TUIWidget = EachIn uiChildren
			If Not child.Visible() Then Continue
			Local span:Int = Min(Max(child.gridColumnSpan, 1), columns)
			If column > 0 And column + span > columns Then
				rows :+ 1
				column = 0
			End If
			column :+ span
			If column >= columns Then
				rows :+ 1
				column = 0
			End If
		Next
		If column > 0 Then rows :+ 1
		Return rows
	End Method
End Type

Rem
bbdoc: Optional styled content container for dashboard cards and tiles.
End Rem
Type TUICard Extends TUIContainer Final
	Private
	Field titleLabel:TUILabel

	Public
	Rem
	bbdoc: Initializes a padded vertical card with an initially hidden title.
	End Rem
	Method New()
		layoutDirection = 2
		gap = 6
		paddingLeft = 12
		paddingTop = 10
		paddingRight = 12
		paddingBottom = 10
		drawBackground = True
		titleLabel = New TUILabel
		titleLabel.SetVisible(False)
		Add(titleLabel)
	End Method

	Rem
	bbdoc: Sets the optional title displayed at the top of the card.
	param: Title text, or an empty string to hide the title row.
	End Rem
	Method SetTitle(title:String)
		If Not title Then title = ""
		titleLabel.SetText(title)
		titleLabel.SetVisible(title.Length > 0)
	End Method

	Rem
	bbdoc: Returns the current card title.
	returns: The title text, which may be empty.
	End Rem
	Method Title:String()
		Return titleLabel.Text()
	End Method

	Rem
	bbdoc: Returns the label used to draw the card title.
	returns: The retained title label for further styling.
	End Rem
	Method TitleLabel:TUILabel()
		Return titleLabel
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then Return Context().Theme().card
		Return Super.DefaultStyle()
	End Method

	Method ClipsChildren:Int() Override
		Return True
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Super.Draw(graphics)
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			For Local edge:Int = 0 Until style.borderWidth
				graphics.DrawRoundRect(X() + edge, Y() + edge, Width() - edge * 2, ..
					Height() - edge * 2, Max(style.cornerRadius - edge, 0))
			Next
		End If
	End Method
End Type

Private

Function _UIHeaderBack(button:TUIButton)
	Local header:TUIHeader = TUIHeader(button.Parent())
	If header And header.Context() Then header.Context().Back()
End Function

Public

Rem
bbdoc: Optional page header with a title, Back action and trailing actions.
End Rem
Type TUIHeader Extends TUIContainer Final
	Private
	Field backButton:TUIButton
	Field titleLabel:TUILabel

	Public
	Rem
	bbdoc: Initializes a horizontal header with a growing title region.
	End Rem
	Method New()
		layoutDirection = 1
		gap = 10
		titleLabel = New TUILabel
		titleLabel.SetGrow(1)
		titleLabel.SetAlign(UIAlignCenter)
		Add(titleLabel)
	End Method

	Rem
	bbdoc: Sets the page-header title.
	param: Title text.
	End Rem
	Method SetTitle(title:String)
		titleLabel.SetText(title)
	End Method

	Rem
	bbdoc: Returns the current page-header title.
	returns: The title text.
	End Rem
	Method Title:String()
		Return titleLabel.Text()
	End Method

	Rem
	bbdoc: Returns the label used to draw the header title.
	returns: The retained title label for further styling.
	End Rem
	Method TitleLabel:TUILabel()
		Return titleLabel
	End Method

	Rem
	bbdoc: Shows or hides the standard Back button.
	param: True to display the button.
	about: Creating the Back button requires Embedded.UI.Controls or
Embedded.UI.Interactive. Activating it calls TUIContext.Back.
	End Rem
	Method SetBackVisible(value:Int)
		If value Then
			_EnsureBackButton().SetVisible(True)
		Else If backButton Then
			backButton.SetVisible(False)
		End If
	End Method

	Rem
	bbdoc: Returns the standard Back button, creating it when necessary.
	returns: The retained Back button.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method BackButton:TUIButton()
		Return _EnsureBackButton()
	End Method

	Rem
	bbdoc: Adds a trailing action button to the header.
	param: Button label.
	param: Optional activation callback.
	returns: The attached button.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method Action:TUIButton(text:String, handler(button:TUIButton) = Null)
		Local button:TUIButton = Button(text)
		If handler Then button.OnClick(handler)
		Return button
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then Return Context().Theme().header
		Return Super.DefaultStyle()
	End Method

	Private
	Method _EnsureBackButton:TUIButton()
		If backButton Then Return backButton
		backButton = _UIRequireControls().CreateButton()
		backButton.SetText("< Back")
		backButton.SetVisible(False)
		backButton.OnClick(_UIHeaderBack)
		Add(backButton)
		' The title already occupies the first slot; Back belongs before it.
		Local last:Int = uiChildren.Length - 1
		uiChildren[last] = uiChildren[0]
		uiChildren[0] = backButton
		Return backButton
	End Method
End Type

Rem
bbdoc: Optional equal-width action bar suitable for page-level navigation.
End Rem
Type TUINavigationBar Extends TUIContainer Final
	Public
	Rem
	bbdoc: Initializes a padded horizontal navigation bar.
	End Rem
	Method New()
		layoutDirection = 1
		gap = 8
		paddingLeft = 8
		paddingTop = 8
		paddingRight = 8
		paddingBottom = 8
		drawBackground = True
	End Method

	Rem
	bbdoc: Adds an equal-width action button to the navigation bar.
	param: Button label.
	param: Optional activation callback.
	returns: The attached growing button.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method Action:TUIButton(text:String, handler(button:TUIButton) = Null)
		Local button:TUIButton = Button(text)
		button.SetGrow(1)
		If handler Then button.OnClick(handler)
		Return button
	End Method

	Method DefaultStyle:TUIStyle() Override
		If Context() And Context().Theme() Then Return Context().Theme().navigation
		Return Super.DefaultStyle()
	End Method

	Method Draw(graphics:TEmbedded2DContext) Override
		Super.Draw(graphics)
		Local style:TUIStyle = DefaultStyle()
		If uiStyle Then style = uiStyle
		If style.borderWidth > 0 Then
			graphics.SetColorValue(style.border)
			graphics.DrawRoundRect(X(), Y(), Width(), Height(), style.cornerRadius)
		End If
	End Method
End Type

Rem
bbdoc: Vertically scrollable and clipped container with optional inertial movement.
about: Children retain natural vertical sizes and are positioned within a
viewport. Touch adapters use the public drag hooks; applications normally use
SetScrollY, ScrollBy, or EnsureVisible.
End Rem
Type TUIScrollView Extends TUIContainer
	Public
	Rem
	bbdoc: Current vertical content offset in pixels.
	End Rem
	Field scrollPosition:Int
	Rem
	bbdoc: Largest permitted vertical content offset in pixels.
	End Rem
	Field maximumScroll:Int
	Rem
	bbdoc: Total measured content height in pixels.
	End Rem
	Field contentExtent:Int
	Rem
	bbdoc: True when the scroll-position indicator is drawn.
	End Rem
	Field showScrollIndicator:Int = True
	Rem
	bbdoc: True when release velocity may continue scrolling.
	End Rem
	Field momentumEnabled:Int
	Rem
	bbdoc: Current inertial velocity in pixels per second.
	End Rem
	Field momentumVelocity:Int
	Rem
	bbdoc: Subpixel time-integration remainder used by inertial scrolling.
	End Rem
	Field momentumRemainder:Int
	Rem
	bbdoc: Timestamp of the previous inertial update in milliseconds.
	End Rem
	Field momentumLastTime:UInt
	Rem
	bbdoc: Timestamp of the previous drag sample in milliseconds.
	End Rem
	Field dragLastTime:UInt
	Rem
	bbdoc: True while an input adapter is actively dragging this viewport.
	End Rem
	Field dragActive:Int

	Public
	Rem
	bbdoc: Initializes vertical clipped layout.
	End Rem
	Method New()
		layoutDirection = 2
	End Method

	Rem
	bbdoc: Returns the current vertical content offset.
	returns: Offset in pixels from the top of the content.
	End Rem
	Method ScrollY:Int()
		Return scrollPosition
	End Method

	Rem
	bbdoc: Returns the maximum vertical content offset.
	returns: Maximum offset in pixels, or zero when all content fits.
	End Rem
	Method MaxScrollY:Int()
		Return maximumScroll
	End Method

	Rem
	bbdoc: Returns the measured height of the complete content.
	returns: Content extent in pixels.
	End Rem
	Method ContentHeight:Int()
		Return contentExtent
	End Method

	Rem
	bbdoc: Moves the viewport to an absolute vertical offset.
	param: Desired offset in pixels, clamped to the valid range.
	about: Any active inertial movement is stopped.
	End Rem
	Method SetScrollY(value:Int)
		_StopMomentum()
		_SetScrollY(value)
	End Method

	Rem
	bbdoc: Updates the vertical offset without stopping inertial movement.
	param: Desired offset in pixels, clamped to the valid range.
	about: This extension hook is intended for input adapters.
	End Rem
	Method _SetScrollY(value:Int)
		If value < 0 Then value = 0
		If value > maximumScroll Then value = maximumScroll
		If scrollPosition = value Then Return
		_Invalidate()
		scrollPosition = value
		_RequestLayout()
	End Method

	Rem
	bbdoc: Moves the viewport relative to its current offset.
	param: Signed number of pixels to add to the current offset.
	End Rem
	Method ScrollBy(delta:Int)
		SetScrollY(scrollPosition + delta)
	End Method

	Rem
	bbdoc: Enables or disables inertial scrolling after a drag.
	param: True to preserve and decelerate release velocity.
	End Rem
	Method SetMomentumEnabled(value:Int)
		momentumEnabled = value <> 0
		If Not momentumEnabled Then _StopMomentum()
	End Method

	Rem
	bbdoc: Reports whether inertial scrolling is enabled.
	returns: True when release momentum may continue moving the viewport.
	End Rem
	Method MomentumEnabled:Int()
		Return momentumEnabled
	End Method

	Rem
	bbdoc: Stops active inertial movement and any drag state.
	End Rem
	Method StopMomentum()
		_StopMomentum()
	End Method

	Rem
	bbdoc: Shows or hides the narrow scroll-position indicator.
	param: True to draw the indicator when content exceeds the viewport.
	End Rem
	Method SetScrollIndicatorVisible(value:Int)
		value = value <> 0
		If showScrollIndicator = value Then Return
		showScrollIndicator = value
		_Invalidate()
	End Method

	Rem
	bbdoc: Reports whether the scroll-position indicator is enabled.
	returns: True when the indicator may be drawn.
	End Rem
	Method ScrollIndicatorVisible:Int()
		Return showScrollIndicator
	End Method

	Rem
	bbdoc: Scrolls the minimum distance needed to reveal a descendant widget.
	param: Widget contained directly or indirectly by this scroll view.
	returns: True when the viewport offset changed.
	End Rem
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
	Rem
	bbdoc: Begins a drag sample sequence and cancels existing momentum.
	param: Current monotonic time in milliseconds.
	about: Intended for input adapters.
	End Rem
	Method _BeginDrag(now:UInt)
		_StopMomentum()
		dragActive = True
		dragLastTime = now
	End Method

	Rem
	bbdoc: Applies one drag delta and estimates its release velocity.
	param: Signed vertical movement in pixels.
	param: Current monotonic time in milliseconds.
	about: Intended for input adapters.
	End Rem
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

	Rem
	bbdoc: Ends dragging and starts momentum when velocity is sufficient.
	param: Current monotonic time in milliseconds.
	about: Intended for input adapters.
	End Rem
	Method _EndDrag(now:UInt)
		dragActive = False
		momentumLastTime = now
		momentumRemainder = 0
		If Not momentumEnabled Or Abs(momentumVelocity) < UIScrollMinimumMomentum Then ..
			momentumVelocity = 0
	End Method

	Rem
	bbdoc: Advances inertial scrolling to the supplied time.
	param: Current monotonic time in milliseconds.
	about: Input bindings which report UpdatesScrollMomentum call this during
their update path.
	End Rem
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

	Rem
	bbdoc: Clears velocity, integration remainder, and active drag state.
	about: Intended for input adapters and scrolling subclasses.
	End Rem
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

Rem
bbdoc: Scrollable single-selection list of retained TUIListItem widgets.
about: Programmatic selection is silent. Pointer or focus-driven selection
invokes the registered callback and emits EVENT_UISELECTIONCHANGED.
End Rem
Type TUIList Extends TUIScrollView
	Public
	Rem
	bbdoc: Currently selected item, or Null when selection is clear.
	End Rem
	Field selectedItem:TUIListItem
	Rem
	bbdoc: Optional callback invoked after interactive selection changes.
	End Rem
	Field selectionHandler(list:TUIList)

	Public
	Rem
	bbdoc: Initializes a compact list with two-pixel item spacing and padding.
	End Rem
	Method New()
		gap = 2
		SetPadding(2)
	End Method

	Rem
	bbdoc: Creates and appends one selectable list item.
	param: Initial item text.
	returns: The attached item.
	End Rem
	Method Item:TUIListItem(text:String = "")
		Local item:TUIListItem = New TUIListItem
		item.listOwner = Self
		item.SetText(text)
		Add(item)
		Return item
	End Method

	Rem
	bbdoc: Returns the number of list-item children.
	returns: Item count, excluding any non-item children.
	End Rem
	Method ItemCount:Int()
		Local count:Int
		For Local child:TUIWidget = EachIn uiChildren
			If TUIListItem(child) Then count :+ 1
		Next
		Return count
	End Method

	Rem
	bbdoc: Returns one list item by logical item index.
	param: Zero-based item index.
	returns: The item, or Null when the index is invalid.
	End Rem
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

	Rem
	bbdoc: Returns the currently selected item.
	returns: The selected item, or Null when selection is clear.
	End Rem
	Method SelectedItem:TUIListItem()
		Return selectedItem
	End Method

	Rem
	bbdoc: Returns the logical index of the selected item.
	returns: Zero-based index, or -1 when selection is clear.
	End Rem
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

	Rem
	bbdoc: Selects an item without emitting a selection notification.
	param: Zero-based item index; an invalid index clears selection.
	End Rem
	Method SetSelectedIndex(value:Int)
		_SetSelectedItem(ItemAt(value), False)
	End Method

	Rem
	bbdoc: Clears selection without emitting a selection notification.
	End Rem
	Method ClearSelection()
		_SetSelectedItem(Null, False)
	End Method

	Rem
	bbdoc: Moves interactive selection by a signed number of items.
	param: Signed index delta; movement is clamped at the list ends.
	returns: True when selection changed.
	about: The selected item is revealed and focused. A change invokes the
callback and emits EVENT_UISELECTIONCHANGED.
	End Rem
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

	Rem
	bbdoc: Registers the interactive selection-change callback.
	param: Callback receiving this list, or Null to remove it.
	End Rem
	Method OnSelectionChanged(handler(list:TUIList))
		selectionHandler = handler
	End Method

	Public
	Rem
	bbdoc: Selects an item as an interactive action.
	param: Item owned by this list.
	about: Intended for TUIListItem and popup subclasses.
	End Rem
	Method _SelectItem(item:TUIListItem)
		_SetSelectedItem(item, True)
	End Method

	Rem
	bbdoc: Updates selection with optional callback and event notification.
	param: Item owned by this list, or Null to clear selection.
	param: True to notify observers.
	End Rem
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

Rem
bbdoc: One focusable and selectable text row owned by a TUIList.
End Rem
Type TUIListItem Extends TUIWidget Final
	Public
	Rem
	bbdoc: List that owns this item.
	End Rem
	Field listOwner:TUIList
	Rem
	bbdoc: Text displayed by this item.
	End Rem
	Field itemText:String

	Public
	Rem
	bbdoc: Initializes a clickable and focusable list item.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Sets the displayed item text.
	param: Text to display; Null is treated as an empty string.
	End Rem
	Method SetText(text:String)
		If Not text Then text = ""
		If itemText = text Then Return
		_Invalidate()
		itemText = text
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the displayed item text.
	returns: Current text.
	End Rem
	Method Text:String()
		Return itemText
	End Method

	Rem
	bbdoc: Reports whether this item is selected by its owner.
	returns: True when this is the list's selected item.
	End Rem
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
		If Context() And Context().Theme() Then
			height = Max(height, Context().Theme().selectionMinimumHeight)
		End If
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
	Method _ActivateFocused:Int() Override
		_Activate()
		Return True
	End Method

	Method _AdjustFocused:Int(delta:Int) Override
		If listOwner Then Return listOwner.MoveSelection(delta)
		Return False
	End Method

	Rem
	bbdoc: Selects this item through its owning list.
	about: Intended for focus and pointer adapters.
	End Rem
	Method _Activate()
		If listOwner Then listOwner._SelectItem(Self)
	End Method
End Type

Rem
bbdoc: Overlay list used for transient selection menus and combo-box choices.
End Rem
Type TUIPopupMenu Extends TUIList
	Public
	Rem
	bbdoc: Combo box receiving this popup's selection, or Null when standalone.
	End Rem
	Field comboOwner:TUIComboBox

	Public
	Rem
	bbdoc: Initializes a list with a visible background suitable for overlays.
	End Rem
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

Rem
bbdoc: Compact single-selection control that opens its choices in an overlay list.
about: SetSelectedIndex changes the value silently. Pointer, focused adjustment,
or popup selection invokes OnChange and emits EVENT_UISELECTIONCHANGED.
End Rem
Type TUIComboBox Extends TUIWidget Final
	Private
	Field itemNames:String[] = New String[0]
	Field selectedIndex:Int = -1
	Field popup:TUIPopupMenu
	Field changeHandler(combo:TUIComboBox)

	Public
	Rem
	bbdoc: Initializes a clickable and focusable combo box with no items.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Appends one choice.
	param: Text displayed for the choice.
	returns: Zero-based index of the appended choice.
	End Rem
	Method AddItem:Int(text:String)
		If Not text Then text = ""
		itemNames = itemNames[..itemNames.Length + 1]
		itemNames[itemNames.Length - 1] = text
		If popup Then popup.Item(text)
		If selectedIndex < 0 Then selectedIndex = 0
		_RequestLayout()
		Return itemNames.Length - 1
	End Method

	Rem
	bbdoc: Returns the number of choices.
	returns: Choice count.
	End Rem
	Method ItemCount:Int()
		Return itemNames.Length
	End Method

	Rem
	bbdoc: Returns the text of one choice.
	param: Zero-based choice index.
	returns: Choice text, or an empty string for an invalid index.
	End Rem
	Method ItemText:String(index:Int)
		If index < 0 Or index >= itemNames.Length Then Return ""
		Return itemNames[index]
	End Method

	Rem
	bbdoc: Returns the selected choice index.
	returns: Zero-based index, or -1 when there are no choices.
	End Rem
	Method SelectedIndex:Int()
		Return selectedIndex
	End Method

	Rem
	bbdoc: Returns the selected choice text.
	returns: Selected text, or an empty string when no choice is selected.
	End Rem
	Method SelectedText:String()
		Return ItemText(selectedIndex)
	End Method

	Rem
	bbdoc: Returns the popup while this combo box owns the active overlay.
	returns: Active popup, or Null while closed.
	End Rem
	Method ActivePopup:TUIPopupMenu()
		If Context() And Context().ActiveOverlay() = popup Then Return popup
		Return Null
	End Method

	Rem
	bbdoc: Changes selection without invoking the callback or emitting an event.
	param: Desired index, clamped to the available choices.
	End Rem
	Method SetSelectedIndex(value:Int)
		_SetSelectedIndex(value, False)
	End Method

	Rem
	bbdoc: Registers the interactive selection-change callback.
	param: Callback receiving this combo box, or Null to remove it.
	End Rem
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
		If Context() And Context().Theme() Then
			height = Max(height, Context().Theme().selectionMinimumHeight)
		End If
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
	Method _ActivateFocused:Int() Override
		_Activate()
		Return True
	End Method

	Method _AdjustFocused:Int(delta:Int) Override
		If itemNames.Length = 0 Then Return False
		_SetSelectedIndex(selectedIndex + delta, True)
		Return True
	End Method

	Rem
	bbdoc: Opens or closes this combo box's popup choice list.
	about: Intended for focus and pointer activation hooks.
	End Rem
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

	Rem
	bbdoc: Applies a popup selection as a user-generated combo-box change.
	param: Selected popup item index.
	about: Intended for the combo box's owned TUIPopupMenu.
	End Rem
	Method _SelectFromPopup(index:Int)
		_SetSelectedIndex(index, True)
	End Method

	Rem
	bbdoc: Updates combo-box selection with optional observer notification.
	param: Desired choice index.
	param: True to invoke the callback and emit EVENT_UISELECTIONCHANGED.
	End Rem
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
	Rem
	bbdoc: Page stack that owns this page.
	End Rem
	Field pageOwner:TUIPageStack
	Rem
	bbdoc: Application-defined page name.
	End Rem
	Field pageName:String

	Public
	Rem
	bbdoc: Initializes vertical page content layout.
	End Rem
	Method New()
		layoutDirection = 2
	End Method

	Rem
	bbdoc: Sets the application-defined page name.
	param: Name used to identify the page; Null becomes an empty string.
	End Rem
	Method SetName(name:String)
		If Not name Then name = ""
		pageName = name
	End Method

	Rem
	bbdoc: Returns the application-defined page name.
	returns: Current name.
	End Rem
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
	Rem
	bbdoc: Initializes an empty page stack.
	End Rem
	Method New()
		layoutDirection = 0
	End Method

	Rem
	bbdoc: Creates and retains a page owned by this stack.
	param: Optional application-defined page name.
	returns: The new page.
	about: The first page is pushed automatically; later pages begin hidden.
	End Rem
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

	Rem
	bbdoc: Returns the number of pages owned by the stack.
	returns: Retained page count, including pages outside the history.
	End Rem
	Method PageCount:Int()
		Return navigationPages.Length
	End Method

	Rem
	bbdoc: Returns one owned page by creation order.
	param: Zero-based page index.
	returns: The page, or Null when the index is invalid.
	End Rem
	Method PageAt:TUIPage(index:Int)
		If index < 0 Or index >= navigationPages.Length Then Return Null
		Return navigationPages[index]
	End Method

	Rem
	bbdoc: Returns the current navigation-history depth.
	returns: Number of pages in the active history.
	End Rem
	Method Depth:Int()
		Return historyDepth
	End Method

	Rem
	bbdoc: Returns the visible page at the top of the history.
	returns: Current page, or Null when the stack is empty.
	End Rem
	Method CurrentPage:TUIPage()
		If historyDepth = 0 Then Return Null
		Return pageHistory[historyDepth - 1]
	End Method

	Rem
	bbdoc: Reports whether Pop can return to an earlier page.
	returns: True when history contains more than one page.
	End Rem
	Method CanPop:Int()
		Return historyDepth > 1
	End Method

	Rem
	bbdoc: Registers the navigation-change callback.
	param: Callback receiving this page stack, or Null to remove it.
	End Rem
	Method OnPageChanged(handler(stack:TUIPageStack))
		changeHandler = handler
	End Method

	Rem
	bbdoc: Pushes an owned page onto the navigation history.
	param: Page created by this stack and not already in the history.
	returns: True when the page was pushed.
	about: The current focused descendant is remembered, the new page becomes
visible, and EVENT_UIPAGECHANGED is emitted.
	End Rem
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

	Rem
	bbdoc: Removes the current page from history and reveals its predecessor.
	returns: True when a page was popped.
	about: The predecessor's remembered focus is restored after layout and
EVENT_UIPAGECHANGED is emitted.
	End Rem
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

	Rem
	bbdoc: Replaces the current history entry with another owned page.
	param: Page created by this stack and absent from earlier history entries.
	returns: True when replacement succeeded.
	End Rem
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
		' A page transition can replace every pixel in the stack. Invalidate the
		' complete output rather than relying on the outgoing page's retained
		' bounds: the incoming page may request a different layout and buffered
		' displays must receive one authoritative replacement frame.
		If Context() Then Context().InvalidateAll() Else _Invalidate()
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIPAGECHANGED, Self, Depth()))
	End Method
End Type

Rem
bbdoc: Vertically arranged content page owned by a TUITabView.
End Rem
Type TUITabPage Extends TUIContainer Final
	Public
	Rem
	bbdoc: Initializes vertical tab-page layout.
	End Rem
	Method New()
		layoutDirection = 2
	End Method
End Type

Rem
bbdoc: Focusable tab selector owned and configured by a TUITabView.
End Rem
Type TUITabButton Extends TUIWidget Final
	Public
	Rem
	bbdoc: Tab view that owns this selector.
	End Rem
	Field tabOwner:TUITabView
	Rem
	bbdoc: Zero-based page index selected by this button.
	End Rem
	Field tabIndex:Int
	Rem
	bbdoc: Text displayed by this tab selector.
	End Rem
	Field tabText:String

	Public
	Rem
	bbdoc: Initializes a clickable and focusable tab selector.
	End Rem
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

	Rem
	bbdoc: Selects this tab and notifies the owning tab view.
	about: Intended for focus and pointer activation hooks.
	End Rem
	Method _Activate()
		If tabOwner Then tabOwner._SelectIndex(tabIndex, True)
	End Method

	Method _ActivateFocused:Int() Override
		_Activate()
		Return True
	End Method

	Method _AdjustFocused:Int(delta:Int) Override
		If Not tabOwner Then Return False
		Local nextIndex:Int = tabOwner.SelectedIndex() + delta
		If nextIndex < 0 Then nextIndex = 0
		If nextIndex >= tabOwner.PageCount() Then nextIndex = tabOwner.PageCount() - 1
		tabOwner._SelectIndex(nextIndex, True)
		Return True
	End Method
End Type

Rem
bbdoc: Single-selection tab strip with one retained content page per tab.
about: Programmatic selection is silent. Pointer or focus-driven selection
invokes the callback and emits EVENT_UISELECTIONCHANGED.
End Rem
Type TUITabView Extends TUIContainer Final
	Public
	Rem
	bbdoc: Retained tab selectors in creation order.
	End Rem
	Field tabButtons:TUITabButton[] = New TUITabButton[0]
	Rem
	bbdoc: Retained tab pages in creation order.
	End Rem
	Field tabPages:TUITabPage[] = New TUITabPage[0]
	Rem
	bbdoc: Zero-based selected tab index, or -1 while empty.
	End Rem
	Field selectedTab:Int = -1
	Rem
	bbdoc: Optional callback invoked after interactive tab selection.
	End Rem
	Field selectionHandler(tabView:TUITabView)

	Public
	Rem
	bbdoc: Initializes an empty tab view.
	End Rem
	Method New()
		gap = 3
	End Method

	Rem
	bbdoc: Adds one tab selector and its retained content page.
	param: Text displayed by the tab selector.
	returns: The new page container.
	End Rem
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

	Rem
	bbdoc: Returns the number of tabs and pages.
	returns: Tab count.
	End Rem
	Method PageCount:Int()
		Return tabPages.Length
	End Method

	Rem
	bbdoc: Returns one tab page by index.
	param: Zero-based tab index.
	returns: The page, or Null when the index is invalid.
	End Rem
	Method PageAt:TUITabPage(index:Int)
		If index < 0 Or index >= tabPages.Length Then Return Null
		Return tabPages[index]
	End Method

	Rem
	bbdoc: Returns one tab selector by index.
	param: Zero-based tab index.
	returns: The selector, or Null when the index is invalid.
	End Rem
	Method TabButtonAt:TUITabButton(index:Int)
		If index < 0 Or index >= tabButtons.Length Then Return Null
		Return tabButtons[index]
	End Method

	Rem
	bbdoc: Returns the selected tab index.
	returns: Zero-based index, or -1 while empty.
	End Rem
	Method SelectedIndex:Int()
		Return selectedTab
	End Method

	Rem
	bbdoc: Returns the selected content page.
	returns: Selected page, or Null while empty.
	End Rem
	Method SelectedPage:TUITabPage()
		Return PageAt(selectedTab)
	End Method

	Rem
	bbdoc: Selects a tab without invoking the callback or emitting an event.
	param: Valid zero-based tab index.
	End Rem
	Method SetSelectedIndex(value:Int)
		_SelectIndex(value, False)
	End Method

	Rem
	bbdoc: Registers the interactive tab-selection callback.
	param: Callback receiving this tab view, or Null to remove it.
	End Rem
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
	Rem
	bbdoc: Updates the selected tab with optional observer notification.
	param: Valid zero-based tab index.
	param: True to invoke the callback and emit EVENT_UISELECTIONCHANGED.
	about: Intended for tab selectors and input adapters.
	End Rem
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

Rem
bbdoc: Display-only bitmap-font text widget with optional word wrapping.
End Rem
Type TUILabel Extends TUIWidget Final
	Public
	Rem
	bbdoc: Text displayed by the label.
	End Rem
	Field labelText:String

	Private
	Field wordWrap:Int
	Field wrappedLines:String[] = New String[0]
	Field wrappedWidth:Int = -1
	Field wrappedFont:TBitmapFont
	Field wrappedScale:Int

	Public
	Rem
	bbdoc: Sets the label text.
	param: Text to display; Null is treated as an empty string.
	End Rem
	Method SetText(text:String)
		If Not text Then text = ""
		If labelText = text Then Return
		_Invalidate()
		labelText = text
		wrappedWidth = -1
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the current label text.
	returns: Displayed text.
	End Rem
	Method Text:String()
		Return labelText
	End Method

	Rem
	bbdoc: Enables or disables wrapping at spaces and explicit line breaks.
	param: True to wrap text to the available content width.
	End Rem
	Method SetWordWrap(value:Int)
		value = value <> 0
		If wordWrap = value Then Return
		wordWrap = value
		wrappedWidth = -1
		_RequestLayout()
		_Invalidate()
	End Method

	Rem
	bbdoc: Reports whether automatic word wrapping is enabled.
	returns: True when text is wrapped to the available width.
	End Rem
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

Rem
bbdoc: Focusable action control with optional state-specific artwork.
about: Activation invokes OnClick and emits EVENT_UIACTION. Pointer activation
also records its display coordinates in the event.
End Rem
Type TUIButton Extends TUIWidget
	Public
	Rem
	bbdoc: Text drawn over the button chrome or artwork.
	End Rem
	Field buttonText:String
	Rem
	bbdoc: Optional callback invoked on activation.
	End Rem
	Field clickHandler(button:TUIButton)
	Rem
	bbdoc: Artwork used for the normal state.
	End Rem
	Field normalImage:TEmbeddedImage
	Rem
	bbdoc: Optional artwork used while pressed.
	End Rem
	Field pressedImage:TEmbeddedImage
	Rem
	bbdoc: Optional artwork used while disabled.
	End Rem
	Field disabledImage:TEmbeddedImage
	Rem
	bbdoc: True when state artwork replaces the themed background and border.
	End Rem
	Field imageReplacesChrome:Int

	Public
	Rem
	bbdoc: Initializes a clickable and focusable button.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Sets the button label.
	param: Text to display; Null is treated as an empty string.
	End Rem
	Method SetText(text:String)
		If Not text Then text = ""
		If buttonText = text Then Return
		_Invalidate()
		buttonText = text
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the button label.
	returns: Displayed text.
	End Rem
	Method Text:String()
		Return buttonText
	End Method

	Rem
	bbdoc: Registers the activation callback.
	param: Callback receiving this button, or Null to remove it.
	End Rem
	Method OnClick(handler(button:TUIButton))
		clickHandler = handler
	End Method

	Rem
	bbdoc: Sets optional normal, pressed, and disabled button artwork.
	param: Normal-state image, or Null to remove all state artwork.
	param: Pressed-state image, or Null to reuse the normal image.
	param: Disabled-state image, or Null to reuse the normal image.
	param: True to replace the themed background and border with the artwork.
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

	Rem
	bbdoc: Returns the normal-state artwork.
	returns: Configured image, or Null when the button uses only theme chrome.
	End Rem
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
		If Context() And Context().Theme() Then
			height = Max(height, Context().Theme().buttonMinimumHeight)
		End If
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
	Method _ActivateFocused:Int() Override
		_Activate()
		EmitEvent(CreateEvent(EVENT_UIACTION, Self))
		Return True
	End Method

	Method _ActivatePointer:Int(x:Int, y:Int) Override
		_Activate()
		EmitEvent(CreateEvent(EVENT_UIACTION, Self, 0, 0, x, y))
		Return True
	End Method

	Rem
	bbdoc: Invokes this button's registered callback.
	about: Input adapters call the activation hooks rather than this helper so an
	EVENT_UIACTION is also emitted.
	End Rem
	Method _Activate()
		If clickHandler Then clickHandler(Self)
	End Method
End Type

Rem
bbdoc: Labeled Boolean selection control.
about: SetChecked changes state silently. User activation invokes OnChange and
emits EVENT_UIVALUECHANGED with the new Boolean value in `data`.
End Rem
Type TUICheckBox Extends TUIWidget Final
	Public
	Rem
	bbdoc: Text displayed beside the check mark.
	End Rem
	Field checkText:String
	Rem
	bbdoc: Current checked state.
	End Rem
	Field checked:Int
	Rem
	bbdoc: Optional callback invoked after user activation changes the state.
	End Rem
	Field changeHandler(checkBox:TUICheckBox)

	Public
	Rem
	bbdoc: Initializes a clickable and focusable check box.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Sets the label displayed beside the check mark.
	param: Label text; Null is treated as an empty string.
	End Rem
	Method SetText(text:String)
		If Not text Then text = ""
		If checkText = text Then Return
		_Invalidate()
		checkText = text
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the check-box label.
	returns: Displayed text.
	End Rem
	Method Text:String()
		Return checkText
	End Method

	Rem
	bbdoc: Sets the checked state without notifying observers.
	param: True to check the control.
	End Rem
	Method SetChecked(value:Int)
		value = value <> 0
		If checked = value Then Return
		checked = value
		_Invalidate()
	End Method

	Rem
	bbdoc: Returns the checked state.
	returns: True when checked.
	End Rem
	Method Checked:Int()
		Return checked
	End Method

	Rem
	bbdoc: Registers the user-generated value-change callback.
	param: Callback receiving this check box, or Null to remove it.
	End Rem
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
	Method _ActivateFocused:Int() Override
		_Activate()
		Return True
	End Method

	Rem
	bbdoc: Toggles the checked state and notifies observers.
	about: Intended for focus and pointer activation hooks.
	End Rem
	Method _Activate()
		SetChecked(Not checked)
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIVALUECHANGED, Self, checked))
	End Method
End Type

Rem
bbdoc: Vertically arranged single-selection group of radio buttons.
about: SetSelectedIndex changes selection silently. User selection invokes the
callback and emits EVENT_UISELECTIONCHANGED.
End Rem
Type TUIRadioGroup Extends TUIContainer Final
	Private
	Field options:TUIRadioButton[] = New TUIRadioButton[0]
	Field selectedIndex:Int = -1
	Field selectionHandler(group:TUIRadioGroup)

	Public
	Rem
	bbdoc: Initializes an empty vertical radio group.
	End Rem
	Method New()
		layoutDirection = 2
		gap = 2
	End Method

	Rem
	bbdoc: Creates and appends one radio option.
	param: Text displayed beside the option mark.
	returns: The attached radio button.
	End Rem
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

	Rem
	bbdoc: Returns the number of radio options.
	returns: Option count.
	End Rem
	Method OptionCount:Int()
		Return options.Length
	End Method

	Rem
	bbdoc: Returns one radio option by index.
	param: Zero-based option index.
	returns: The option, or Null when the index is invalid.
	End Rem
	Method OptionAt:TUIRadioButton(index:Int)
		If index < 0 Or index >= options.Length Then Return Null
		Return options[index]
	End Method

	Rem
	bbdoc: Returns the selected option index.
	returns: Zero-based index, or -1 while empty or cleared.
	End Rem
	Method SelectedIndex:Int()
		Return selectedIndex
	End Method

	Rem
	bbdoc: Changes selection without invoking the callback or emitting an event.
	param: Desired option index, clamped to the valid range.
	End Rem
	Method SetSelectedIndex(value:Int)
		_SelectIndex(value, False)
	End Method

	Rem
	bbdoc: Registers the user-generated selection-change callback.
	param: Callback receiving this group, or Null to remove it.
	End Rem
	Method OnSelectionChanged(handler(group:TUIRadioGroup))
		selectionHandler = handler
	End Method

	Public
	Rem
	bbdoc: Updates selection with optional observer notification.
	param: Desired option index.
	param: True to invoke the callback and emit EVENT_UISELECTIONCHANGED.
	about: Intended for the group's radio buttons and input adapters.
	End Rem
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

Rem
bbdoc: One focusable labeled option owned by a TUIRadioGroup.
End Rem
Type TUIRadioButton Extends TUIWidget Final
	Private
	Field radioText:String
	Field radioOwner:TUIRadioGroup
	Field radioIndex:Int

	Public
	Rem
	bbdoc: Associates this option with a group and logical index.
	param: Owning radio group.
	param: Zero-based option index.
	about: Intended for TUIRadioGroup.
	End Rem
	Method _Configure(owner:TUIRadioGroup, index:Int)
		radioOwner = owner
		radioIndex = index
	End Method

	Rem
	bbdoc: Initializes a clickable and focusable radio button.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Sets the option label.
	param: Label text; Null is treated as an empty string.
	End Rem
	Method SetText(text:String)
		If Not text Then text = ""
		If radioText = text Then Return
		radioText = text
		_Invalidate()
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the option label.
	returns: Displayed text.
	End Rem
	Method Text:String()
		Return radioText
	End Method

	Rem
	bbdoc: Reports whether this option is selected by its group.
	returns: True when selected.
	End Rem
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
	Method _ActivateFocused:Int() Override
		_Activate()
		Return True
	End Method

	Method _AdjustFocused:Int(delta:Int) Override
		_Move(delta)
		Return True
	End Method

	Rem
	bbdoc: Selects this radio option and notifies the owning group.
	about: Intended for focus and pointer activation hooks.
	End Rem
	Method _Activate()
		If radioOwner Then radioOwner._SelectIndex(radioIndex, True)
	End Method

	Rem
	bbdoc: Moves group selection relative to this option and updates focus.
	param: Signed option-index delta.
	about: Intended for focused input adapters.
	End Rem
	Method _Move(delta:Int)
		If Not radioOwner Or delta = 0 Then Return
		Local nextIndex:Int = radioOwner.SelectedIndex() + delta
		If nextIndex < 0 Then nextIndex = 0
		If nextIndex >= radioOwner.OptionCount() Then nextIndex = radioOwner.OptionCount() - 1
		radioOwner._SelectIndex(nextIndex, True)
		If Context() Then Context().SetFocus(radioOwner.OptionAt(nextIndex))
	End Method
End Type

Rem
bbdoc: Compact Boolean toggle switch.
about: SetValue changes state silently. User activation invokes OnChange and
emits EVENT_UIVALUECHANGED with the new Boolean value in `data`.
End Rem
Type TUISwitch Extends TUIWidget Final
	Public
	Rem
	bbdoc: Current on or off state.
	End Rem
	Field switchValue:Int
	Rem
	bbdoc: Optional callback invoked after user activation changes the state.
	End Rem
	Field changeHandler(switchControl:TUISwitch)

	Public
	Rem
	bbdoc: Initializes a clickable and focusable switch.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Sets the switch state without notifying observers.
	param: True for on, or False for off.
	End Rem
	Method SetValue(value:Int)
		value = value <> 0
		If switchValue = value Then Return
		switchValue = value
		_Invalidate()
	End Method

	Rem
	bbdoc: Returns the switch state.
	returns: True when on.
	End Rem
	Method Value:Int()
		Return switchValue
	End Method

	Rem
	bbdoc: Registers the user-generated value-change callback.
	param: Callback receiving this switch, or Null to remove it.
	End Rem
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
	Method _ActivateFocused:Int() Override
		_Activate()
		Return True
	End Method

	Rem
	bbdoc: Toggles the switch and notifies observers.
	about: Intended for focus and pointer activation hooks.
	End Rem
	Method _Activate()
		SetValue(Not switchValue)
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIVALUECHANGED, Self, switchValue))
	End Method
End Type

Rem
bbdoc: Base widget for controls and indicators that represent a bounded integer value.
End Rem
Type TUIRangeWidget Extends TUIWidget
	Public
	Rem
	bbdoc: Inclusive minimum represented value.
	End Rem
	Field minimumValue:Int
	Rem
	bbdoc: Inclusive maximum represented value.
	End Rem
	Field maximumValue:Int = 100
	Rem
	bbdoc: Current value, clamped to the inclusive range.
	End Rem
	Field currentValue:Int

	Public
	Rem
	bbdoc: Sets the inclusive value range and clamps the current value.
	param: Minimum value.
	param: Maximum value; values below the minimum collapse the range.
	End Rem
	Method SetRange(minimum:Int, maximum:Int)
		If maximum < minimum Then maximum = minimum
		If minimumValue = minimum And maximumValue = maximum Then Return
		minimumValue = minimum
		maximumValue = maximum
		If currentValue < minimumValue Then currentValue = minimumValue
		If currentValue > maximumValue Then currentValue = maximumValue
		_Invalidate()
	End Method

	Rem
	bbdoc: Returns the inclusive minimum value.
	returns: Current range minimum.
	End Rem
	Method Minimum:Int()
		Return minimumValue
	End Method

	Rem
	bbdoc: Returns the inclusive maximum value.
	returns: Current range maximum.
	End Rem
	Method Maximum:Int()
		Return maximumValue
	End Method

	Rem
	bbdoc: Sets and clamps the value without notifying observers.
	param: Desired value.
	End Rem
	Method SetValue(value:Int)
		If value < minimumValue Then value = minimumValue
		If value > maximumValue Then value = maximumValue
		If currentValue = value Then Return
		currentValue = value
		_Invalidate()
	End Method

	Rem
	bbdoc: Returns the current value.
	returns: Value within the inclusive range.
	End Rem
	Method Value:Int()
		Return currentValue
	End Method

	Rem
	bbdoc: Maps the current value proportionally onto an integer scale.
	param: Output value representing the maximum end of the range.
	returns: Scaled position, or zero for a collapsed range.
	End Rem
	Method Fraction:Int(scale:Int)
		If maximumValue <= minimumValue Then Return 0
		Return Int(Long(currentValue - minimumValue) * scale / Long(maximumValue - minimumValue))
	End Method
End Type

Rem
bbdoc: Three-part numeric control for decrementing or incrementing a bounded value.
about: Integer values are native. Decimal mode stores fixed-point scaled integers
and formats them with a configured number of decimal places. Programmatic setters
are silent; user changes invoke OnChange and emit EVENT_UIVALUECHANGED.
End Rem
Type TUIStepper Extends TUIRangeWidget Final
	Private
	Field stepValue:Int = 1
	Field decimalPlaces:Int
	Field decimalScale:Int = 1
	Field changeHandler(stepper:TUIStepper)

	Public
	Rem
	bbdoc: Initializes a clickable and focusable integer stepper.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Sets the positive integer increment.
	param: Increment, clamped to at least one.
	End Rem
	Method SetStep(value:Int)
		If value < 1 Then value = 1
		stepValue = value
	End Method

	Rem
	bbdoc: Returns the stored integer or fixed-point increment.
	returns: Positive increment in the stepper's internal units.
	End Rem
	Method Step:Int()
		Return stepValue
	End Method

	Rem
	bbdoc: Configures the range, value, increment, and precision for decimal mode.
	param: Minimum decimal value.
	param: Maximum decimal value.
	param: Initial decimal value.
	param: Decimal increment; its absolute value is used.
	param: Decimal places, clamped from one through six.
	End Rem
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

	Rem
	bbdoc: Sets the decimal range using the configured precision.
	param: Minimum decimal value.
	param: Maximum decimal value.
	End Rem
	Method SetDecimalRange(minimum:Double, maximum:Double)
		SetRange(_DecimalUnits(minimum), _DecimalUnits(maximum))
	End Method

	Rem
	bbdoc: Sets the decimal value without notifying observers.
	param: Desired decimal value, rounded and clamped at configured precision.
	End Rem
	Method SetDecimalValue(value:Double)
		SetValue(_DecimalUnits(value))
	End Method

	Rem
	bbdoc: Returns the current value converted from fixed-point storage.
	returns: Current decimal value.
	End Rem
	Method DecimalValue:Double()
		Return Double(currentValue) / Double(decimalScale)
	End Method

	Rem
	bbdoc: Sets the decimal increment using the configured precision.
	param: Increment; its absolute value is rounded to fixed-point units.
	End Rem
	Method SetDecimalStep(value:Double)
		stepValue = Max(Abs(_DecimalUnits(value)), 1)
	End Method

	Rem
	bbdoc: Returns the configured decimal precision.
	returns: Decimal places, or zero in integer mode.
	End Rem
	Method DecimalPlaces:Int()
		Return decimalPlaces
	End Method

	Rem
	bbdoc: Formats the current integer or fixed-point value for display.
	returns: Value text using the configured number of decimal places.
	End Rem
	Method ValueText:String()
		Return _ValueText()
	End Method

	Rem
	bbdoc: Registers the user-generated value-change callback.
	param: Callback receiving this stepper, or Null to remove it.
	End Rem
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
	Method _ActivateFocused:Int() Override
		_Activate()
		Return True
	End Method

	Method _ActivatePointer:Int(x:Int, y:Int) Override
		_ActivateAt(x)
		Return True
	End Method

	Method _AdjustFocused:Int(delta:Int) Override
		_Adjust(delta)
		Return True
	End Method

	Rem
	bbdoc: Increments the stepper by one configured step and notifies observers.
	End Rem
	Method _Activate()
		_SetUserValue(currentValue + stepValue)
	End Method

	Rem
	bbdoc: Decrements or increments according to the pressed horizontal third.
	param: Display x coordinate in pixels.
	End Rem
	Method _ActivateAt(x:Int)
		Local partWidth:Int = Max(Width() / 3, 1)
		If x < X() + partWidth Then
			_SetUserValue(currentValue - stepValue)
		Else If x >= X() + partWidth * 2 Then
			_SetUserValue(currentValue + stepValue)
		End If
	End Method

	Rem
	bbdoc: Applies a signed number of configured steps and notifies observers.
	param: Signed step count.
	End Rem
	Method _Adjust(delta:Int)
		_SetUserValue(currentValue + delta * stepValue)
	End Method

	Rem
	bbdoc: Clamps a user-generated value and notifies observers when it changes.
	param: Desired value in integer or fixed-point units.
	End Rem
	Method _SetUserValue(value:Int)
		If value < minimumValue Then value = minimumValue
		If value > maximumValue Then value = maximumValue
		If value = currentValue Then Return
		SetValue(value)
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIVALUECHANGED, Self, currentValue))
	End Method
End Type

Rem
bbdoc: Horizontal single-selection control divided into equal labeled segments.
about: SetSelectedIndex changes selection silently. Pointer and focused changes
invoke the callback and emit EVENT_UISELECTIONCHANGED.
End Rem
Type TUISegmentedControl Extends TUIWidget Final
	Private
	Field itemNames:String[] = New String[0]
	Field selectedIndex:Int = -1
	Field selectionHandler(control:TUISegmentedControl)

	Public
	Rem
	bbdoc: Initializes an empty clickable and focusable segmented control.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Appends one labeled segment.
	param: Segment text.
	returns: Zero-based index of the appended segment.
	End Rem
	Method AddItem:Int(text:String)
		If Not text Then text = ""
		itemNames = itemNames[..itemNames.Length + 1]
		itemNames[itemNames.Length - 1] = text
		If selectedIndex < 0 Then selectedIndex = 0
		_RequestLayout()
		Return itemNames.Length - 1
	End Method

	Rem
	bbdoc: Returns the number of segments.
	returns: Segment count.
	End Rem
	Method ItemCount:Int()
		Return itemNames.Length
	End Method

	Rem
	bbdoc: Returns the text of one segment.
	param: Zero-based segment index.
	returns: Segment text, or an empty string for an invalid index.
	End Rem
	Method ItemText:String(index:Int)
		If index < 0 Or index >= itemNames.Length Then Return ""
		Return itemNames[index]
	End Method

	Rem
	bbdoc: Returns the selected segment index.
	returns: Zero-based index, or -1 while empty.
	End Rem
	Method SelectedIndex:Int()
		Return selectedIndex
	End Method

	Rem
	bbdoc: Changes selection without invoking the callback or emitting an event.
	param: Desired index, clamped to the available segments.
	End Rem
	Method SetSelectedIndex(value:Int)
		_SetSelectedIndex(value, False)
	End Method

	Rem
	bbdoc: Registers the user-generated selection-change callback.
	param: Callback receiving this control, or Null to remove it.
	End Rem
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
	Method _ActivateFocused:Int() Override
		_Activate()
		Return True
	End Method

	Method _ActivatePointer:Int(x:Int, y:Int) Override
		_ActivateAt(x)
		Return True
	End Method

	Method _AdjustFocused:Int(delta:Int) Override
		_Adjust(delta)
		Return True
	End Method

	Rem
	bbdoc: Selects the next segment cyclically and notifies observers.
	End Rem
	Method _Activate()
		If itemNames.Length = 0 Then Return
		_SetSelectedIndex((selectedIndex + 1) Mod itemNames.Length, True)
	End Method

	Rem
	bbdoc: Selects the segment at a horizontal pointer coordinate.
	param: Display x coordinate in pixels.
	End Rem
	Method _ActivateAt(x:Int)
		If itemNames.Length = 0 Or Width() <= 0 Then Return
		Local index:Int = Int(Long(x - X()) * itemNames.Length / Width())
		_SetSelectedIndex(index, True)
	End Method

	Rem
	bbdoc: Moves segment selection by a signed delta and notifies observers.
	param: Signed segment-index delta.
	End Rem
	Method _Adjust(delta:Int)
		_SetSelectedIndex(selectedIndex + delta, True)
	End Method

	Rem
	bbdoc: Updates segment selection with optional observer notification.
	param: Desired segment index.
	param: True to invoke the callback and emit EVENT_UISELECTIONCHANGED.
	End Rem
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

Rem
bbdoc: Focusable horizontal range control with direct pointer tracking.
about: SetValue is silent. Dragging, tapping, or focused adjustment invokes
OnChange and emits EVENT_UIVALUECHANGED for every effective value change.
End Rem
Type TUISlider Extends TUIRangeWidget Final
	Public
	Rem
	bbdoc: Optional callback invoked after user interaction changes the value.
	End Rem
	Field changeHandler(slider:TUISlider)

	Public
	Rem
	bbdoc: Initializes a clickable and focusable slider.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Registers the user-generated value-change callback.
	param: Callback receiving this slider, or Null to remove it.
	End Rem
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
	Method _BeginPointer:Int(x:Int, y:Int) Override
		_TrackPointer(x, y)
		Return True
	End Method

	Method _TrackPointer:Int(x:Int, y:Int) Override
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
		Return True
	End Method

	Method _AdjustFocused:Int(delta:Int) Override
		_SetUserValue(Value() + delta)
		Return True
	End Method

	Rem
	bbdoc: Clamps a user-generated slider value and notifies observers on change.
	param: Desired value.
	End Rem
	Method _SetUserValue(value:Int)
		If value < minimumValue Then value = minimumValue
		If value > maximumValue Then value = maximumValue
		If value = currentValue Then Return
		SetValue(value)
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIVALUECHANGED, Self, currentValue))
	End Method
End Type

Rem
bbdoc: Display-only horizontal indicator for a bounded value.
End Rem
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
	Rem
	bbdoc: Sets the label displayed beside the status lamp.
	param: Label text; Null is treated as an empty string.
	End Rem
	Method SetText(text:String)
		If Not text Then text = ""
		If indicatorText = text Then Return
		indicatorText = text
		_RequestLayout()
	End Method

	Rem
	bbdoc: Returns the status label.
	returns: Displayed text.
	End Rem
	Method Text:String()
		Return indicatorText
	End Method

	Rem
	bbdoc: Sets the displayed status state.
	param: True to use the active style or artwork.
	End Rem
	Method SetActive(value:Int)
		value = value <> 0
		If active = value Then Return
		active = value
		_Invalidate()
	End Method

	Rem
	bbdoc: Returns the displayed status state.
	returns: True when active.
	End Rem
	Method Active:Int()
		Return active
	End Method

	Rem
	bbdoc: Sets optional artwork for inactive and active states.
	param: Inactive-state image, or Null to draw the standard lamp.
	param: Active-state image, or Null to reuse the inactive image.
	End Rem
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
	Rem
	bbdoc: Sets the caption drawn below the gauge.
	param: Caption text; Null is treated as an empty string.
	End Rem
	Method SetLabel(text:String)
		If Not text Then text = ""
		If labelText = text Then Return
		labelText = text
		_Invalidate()
	End Method

	Rem
	bbdoc: Sets the suffix appended to the numeric value.
	param: Unit text such as `%` or `C`.
	End Rem
	Method SetUnit(text:String)
		If Not text Then text = ""
		If unitText = text Then Return
		unitText = text
		_Invalidate()
	End Method

	Rem
	bbdoc: Shows or hides the numeric value in the gauge center.
	param: True to draw the current value and unit.
	End Rem
	Method SetShowValue(value:Int)
		showValue = value <> 0
		_Invalidate()
	End Method

	Rem
	bbdoc: Sets the gauge-track thickness.
	param: Width in pixels, clamped to at least one.
	End Rem
	Method SetArcWidth(value:Int)
		arcWidth = Max(value, 1)
		_Invalidate()
	End Method

	Rem
	bbdoc: Sets the number of equal divisions drawn around the gauge.
	param: Non-negative division count; zero disables ticks.
	End Rem
	Method SetTickCount(value:Int)
		tickCount = Max(value, 0)
		_Invalidate()
	End Method

	Rem
	bbdoc: Sets optional artwork drawn beneath the gauge arc and text.
	param: Face image, or Null to remove it.
	End Rem
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
	Rem
	bbdoc: Sets the rolling sample capacity and clears existing history.
	param: Capacity, clamped to at least two samples.
	End Rem
	Method SetCapacity(value:Int)
		value = Max(value, 2)
		If samples.Length = value Then Return
		samples = New Int[value]
		sampleStart = 0
		sampleCount = 0
		_Invalidate()
	End Method

	Rem
	bbdoc: Returns the maximum number of retained samples.
	returns: Circular-buffer capacity.
	End Rem
	Method Capacity:Int()
		Return samples.Length
	End Method

	Rem
	bbdoc: Returns the number of currently retained samples.
	returns: Sample count from zero through Capacity.
	End Rem
	Method Count:Int()
		Return sampleCount
	End Method

	Rem
	bbdoc: Removes all retained samples without reallocating the buffer.
	End Rem
	Method Clear()
		sampleStart = 0
		sampleCount = 0
		_Invalidate()
	End Method

	Rem
	bbdoc: Appends one sample, discarding the oldest when full.
	param: Sample value.
	End Rem
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

	Rem
	bbdoc: Returns one retained sample in oldest-to-newest order.
	param: Zero-based sample index.
	returns: Sample value, or zero when the index is invalid.
	End Rem
	Method ValueAt:Int(index:Int)
		If index < 0 Or index >= sampleCount Then Return 0
		Return samples[(sampleStart + index) Mod samples.Length]
	End Method

	Rem
	bbdoc: Sets a fixed vertical range and disables automatic ranging.
	param: Lower graph value.
	param: Upper graph value; adjusted above the minimum when necessary.
	End Rem
	Method SetRange(minimum:Int, maximum:Int)
		If maximum <= minimum Then maximum = minimum + 1
		minimumValue = minimum
		maximumValue = maximum
		autoRange = False
		_Invalidate()
	End Method

	Rem
	bbdoc: Enables or disables range calculation from retained samples.
	param: True to derive minimum and maximum for each draw.
	End Rem
	Method SetAutoRange(value:Int)
		autoRange = value <> 0
		_Invalidate()
	End Method

	Rem
	bbdoc: Reports whether the graph derives its range from current samples.
	returns: True when automatic ranging is enabled.
	End Rem
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
	Rem
	bbdoc: Initializes a clickable and focusable rotary dial.
	End Rem
	Method New()
		clickable = True
		focusable = True
	End Method

	Rem
	bbdoc: Sets optional artwork drawn beneath the dial arc and needle.
	param: Face image, or Null to remove it.
	End Rem
	Method SetFaceImage(image:TEmbeddedImage)
		faceImage = image
		_Invalidate()
	End Method

	Rem
	bbdoc: Sets the increment used by focused adjustment.
	param: Positive integer increment, clamped to at least one.
	End Rem
	Method SetStep(value:Int)
		stepValue = Max(value, 1)
	End Method

	Rem
	bbdoc: Returns the focused-adjustment increment.
	returns: Positive integer step.
	End Rem
	Method Step:Int()
		Return stepValue
	End Method

	Rem
	bbdoc: Selects horizontal or vertical linear drag interaction.
	param: UIDialDragHorizontal or UIDialDragVertical.
	End Rem
	Method SetDragDirection(direction:Int)
		If direction <> UIDialDragVertical Then direction = UIDialDragHorizontal
		dragDirection = direction
	End Method

	Rem
	bbdoc: Returns the configured linear drag direction.
	returns: One of the UIDialDrag constants.
	End Rem
	Method DragDirection:Int()
		Return dragDirection
	End Method

	Rem
	bbdoc: Registers the user-generated value-change callback.
	param: Callback receiving this dial, or Null to remove it.
	End Rem
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
	Method _BeginPointer:Int(x:Int, y:Int) Override
		dragStartX = x
		dragStartY = y
		dragStartValue = Value()
		dragging = True
		Return True
	End Method

	Method _TrackPointer:Int(x:Int, y:Int) Override
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
		Return True
	End Method

	Method _EndPointer() Override
		dragging = False
	End Method

	Method _AdjustFocused:Int(delta:Int) Override
		_Adjust(delta)
		Return True
	End Method

	Rem
	bbdoc: Applies a signed number of configured dial steps.
	param: Signed step count.
	End Rem
	Method _Adjust(delta:Int)
		_SetUserValue(Value() + delta * stepValue)
	End Method

	Rem
	bbdoc: Clamps a user-generated dial value and notifies observers on change.
	param: Desired value.
	End Rem
	Method _SetUserValue(value:Int)
		If value < Minimum() Then value = Minimum()
		If value > Maximum() Then value = Maximum()
		If value = Value() Then Return
		SetValue(value)
		If changeHandler Then changeHandler(Self)
		EmitEvent(CreateEvent(EVENT_UIVALUECHANGED, Self, Value()))
	End Method
End Type

Rem
bbdoc: Dialog-owned button that closes its dialog with an application result value.
End Rem
Type TUIDialogAction Extends TUIButton Final
	Private
	Field dialogOwner:TUIDialog
	Field actionResult:Int

	Public
	Rem
	bbdoc: Associates this action with a dialog and result value.
	param: Owning dialog.
	param: Integer result returned when the action is activated.
	about: Intended for TUIDialog.Action.
	End Rem
	Method _Configure(owner:TUIDialog, result:Int)
		dialogOwner = owner
		actionResult = result
	End Method

	Rem
	bbdoc: Returns the result produced by this action.
	returns: Configured integer result.
	End Rem
	Method Result:Int()
		Return actionResult
	End Method

	Public
	Method _ActivateFocused:Int() Override
		_Activate()
		Return True
	End Method

	Method _ActivatePointer:Int(x:Int, y:Int) Override
		_Activate()
		Return True
	End Method

	Method _Activate() Override
		Super._Activate()
		If dialogOwner Then dialogOwner.Close(actionResult)
	End Method
End Type

Rem
bbdoc: Centered modal overlay with a title, wrapped message, and result actions.
about: Show gives the dialog focus and blocks hit testing of the underlying UI.
Close dismisses it, invokes OnResult, and emits EVENT_UIACTION with the result
in `data`.
End Rem
Type TUIDialog Extends TUIContainer Final
	Private
	Field titleLabel:TUILabel
	Field messageLabel:TUILabel
	Field actionRow:TUIRow
	Field dialogResult:Int
	Field resultHandler(dialog:TUIDialog, result:Int)

	Public
	Rem
	bbdoc: Initializes the padded dialog structure and action row.
	End Rem
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

	Rem
	bbdoc: Sets the dialog title.
	param: Title text.
	End Rem
	Method SetTitle(text:String)
		titleLabel.SetText(text)
	End Method

	Rem
	bbdoc: Returns the dialog title.
	returns: Title text.
	End Rem
	Method Title:String()
		Return titleLabel.Text()
	End Method

	Rem
	bbdoc: Sets the wrapped dialog message.
	param: Message text.
	End Rem
	Method SetMessage(text:String)
		messageLabel.SetText(text)
	End Method

	Rem
	bbdoc: Returns the dialog message.
	returns: Message text.
	End Rem
	Method Message:String()
		Return messageLabel.Text()
	End Method

	Rem
	bbdoc: Returns the retained title label for further styling.
	returns: Title label.
	End Rem
	Method TitleLabel:TUILabel()
		Return titleLabel
	End Method

	Rem
	bbdoc: Returns the retained wrapped message label for further styling.
	returns: Message label.
	End Rem
	Method MessageLabel:TUILabel()
		Return messageLabel
	End Method

	Rem
	bbdoc: Appends an equal-width action button to the dialog.
	param: Button label.
	param: Integer result returned by that action.
	returns: The attached dialog action.
	End Rem
	Method Action:TUIDialogAction(text:String, result:Int = 0)
		Local action:TUIDialogAction = New TUIDialogAction
		action._Configure(Self, result)
		action.SetText(text)
		action.SetGrow(1)
		actionRow.Add(action)
		Return action
	End Method

	Rem
	bbdoc: Registers the callback invoked after the dialog closes with a result.
	param: Callback receiving this dialog and its result, or Null to remove it.
	End Rem
	Method OnResult(handler(dialog:TUIDialog, result:Int))
		resultHandler = handler
	End Method

	Rem
	bbdoc: Returns the most recent close result.
	returns: Integer supplied to Close or the activated action.
	End Rem
	Method Result:Int()
		Return dialogResult
	End Method

	Rem
	bbdoc: Shows the dialog centered as a non-dismissable-outside modal overlay.
	param: Requested width in pixels, or UILayoutAuto.
	param: Requested height in pixels, or UILayoutAuto.
	returns: True when the dialog was shown.
	End Rem
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

	Rem
	bbdoc: Dismisses the active dialog and publishes its result.
	param: Application-defined result value.
	returns: True when this dialog was the active overlay and was closed.
	End Rem
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
	Rem
	bbdoc: Initializes the padded wrapped-message toast content.
	End Rem
	Method New()
		layoutDirection = 2
		SetPaddingEdges(14, 10, 14, 10)
		drawBackground = True
		messageLabel = Label()
		messageLabel.SetWordWrap(True)
	End Method

	Rem
	bbdoc: Returns the notification message.
	returns: Message text.
	End Rem
	Method Message:String()
		Return messageLabel.Text()
	End Method

	Rem
	bbdoc: Returns the semantic notification kind.
	returns: One of the UIToast kind constants.
	End Rem
	Method Kind:Int()
		Return toastKind
	End Method

	Rem
	bbdoc: Returns the visible lifetime.
	returns: Duration in milliseconds, or zero for persistent.
	End Rem
	Method Duration:Int()
		Return toastDuration
	End Method

	Rem
	bbdoc: Reports whether the toast remains until explicitly dismissed.
	returns: True when Duration is zero.
	End Rem
	Method Persistent:Int()
		Return toastDuration = 0
	End Method

	Rem
	bbdoc: Returns the toast's display placement.
	returns: One of the UIToast placement constants.
	End Rem
	Method Placement:Int()
		Return toastPlacement
	End Method

	Rem
	bbdoc: Moves the toast to another placement stack.
	param: One of the UIToast placement constants; invalid values use bottom-center.
	End Rem
	Method SetPlacement(value:Int)
		If value < UIToastTopLeft Or value > UIToastBottomRight Then value = UIToastBottomCenter
		If toastPlacement = value Then Return
		toastPlacement = value
		If Context() Then Context().RequestLayout()
	End Method

	Rem
	bbdoc: Removes this toast from its visible stack or pending queue.
	returns: True when the context contained and dismissed it.
	End Rem
	Method Close:Int()
		If Not Context() Then Return False
		Return Context().DismissToast(Self)
	End Method

	Public
	Rem
	bbdoc: Configures message, duration, kind, placement, and default styling.
	param: Notification message.
	param: Lifetime in milliseconds; zero creates a persistent toast.
	param: One of the UIToast kind constants.
	param: One of the UIToast placement constants.
	about: Intended for TUIContext.Toast.
	End Rem
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

	Rem
	bbdoc: Records when this toast became visible.
	param: Current monotonic time in milliseconds.
	End Rem
	Method _Show(now:UInt)
		toastShownAt = now
	End Method

	Rem
	bbdoc: Returns the monotonic time at which the toast became visible.
	returns: Timestamp in milliseconds.
	End Rem
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

Rem
bbdoc: Optional input binding owned by a UI context.
about: Input adapters live in separate modules. A context closes its binding
automatically, allowing Embedded.UI itself to remain display-only.
End Rem
Type TUIInputBinding
	Rem
	bbdoc: Releases adapter resources and detaches from its context.
	End Rem
	Method Close()
	End Method

	Rem
	bbdoc: Reports whether the binding expects context presentation to advance scrolling.
	returns: True when TUIContext.Present should update scroll momentum.
	End Rem
	Method UpdatesScrollMomentum:Int()
		Return False
	End Method
End Type

Rem
bbdoc: Owns one retained UI tree and coordinates layout, rendering, focus, overlays, and presentation.
about: A context draws into one TDisplayBuffer through Embedded.Graphics2D.
Input is optional and supplied by a separate binding, allowing display-only
firmware to omit interactive adapters and their event-processing code.
End Rem
Type TUIContext
	Public
	Rem
	bbdoc: Display used to present rendered dirty regions, or Null for buffer-only rendering.
	End Rem
	Field display:TDisplay
	Rem
	bbdoc: Framebuffer containing the retained UI output.
	End Rem
	Field frame:TDisplayBuffer
	Rem
	bbdoc: Graphics2D context drawing into the framebuffer.
	End Rem
	Field graphics:TEmbedded2DContext
	Rem
	bbdoc: Optional input adapter owned by this context.
	End Rem
	Field inputBinding:TUIInputBinding
	Rem
	bbdoc: Root vertical container filling the framebuffer.
	End Rem
	Field rootWidget:TUIColumn
	Rem
	bbdoc: Active modal or popup overlay, or Null.
	End Rem
	Field overlayWidget:TUIContainer
	Rem
	bbdoc: Widget focused before the active overlay was shown.
	End Rem
	Field overlayPreviousFocus:TUIWidget
	Rem
	bbdoc: True when a pointer press outside the overlay dismisses it.
	End Rem
	Field overlayDismissOutside:Int = True
	Rem
	bbdoc: Theme currently inherited by the widget tree.
	End Rem
	Field themeValue:TUITheme
	Rem
	bbdoc: True when widget bounds require recalculation.
	End Rem
	Field layoutPending:Int = True
	Rem
	bbdoc: Widget currently holding focus, or Null.
	End Rem
	Field focusedWidget:TUIWidget
	Rem
	bbdoc: Widget scheduled to receive focus after pending layout.
	End Rem
	Field deferredFocus:TUIWidget
	Rem
	bbdoc: True when a deferred focus operation is pending.
	End Rem
	Field deferredFocusPending:Int
	Rem
	bbdoc: Number of retained dirty rectangles.
	End Rem
	Field invalidCount:Int
	Rem
	bbdoc: Left edges of retained dirty rectangles.
	End Rem
	Field invalidX0:Int[UIInvalidRegionMaximum]
	Rem
	bbdoc: Top edges of retained dirty rectangles.
	End Rem
	Field invalidY0:Int[UIInvalidRegionMaximum]
	Rem
	bbdoc: Exclusive right edges of retained dirty rectangles.
	End Rem
	Field invalidX1:Int[UIInvalidRegionMaximum]
	Rem
	bbdoc: Exclusive bottom edges of retained dirty rectangles.
	End Rem
	Field invalidY1:Int[UIInvalidRegionMaximum]
	Rem
	bbdoc: Toasts currently displayed above normal and modal content.
	End Rem
	Field visibleToasts:TUIToast[] = New TUIToast[0]
	Rem
	bbdoc: Toasts waiting for a visible slot.
	End Rem
	Field toastQueue:TUIToast[] = New TUIToast[0]
	Rem
	bbdoc: Default placement assigned to new toasts.
	End Rem
	Field toastPlacement:Int = UIToastBottomCenter
	Rem
	bbdoc: Maximum number of toasts displayed simultaneously.
	End Rem
	Field toastVisibleLimit:Int = 3
	Rem
	bbdoc: Spacing between stacked toasts in pixels.
	End Rem
	Field toastGap:Int = 8
	Rem
	bbdoc: Minimum toast distance from display edges in pixels.
	End Rem
	Field toastMargin:Int = 12

	Public
	Rem
	bbdoc: Creates a context with a new framebuffer supplied by a display.
	param: Display used to allocate and present the framebuffer.
	param: Optional theme; the standard dark theme is used when Null.
	returns: New context, or Null when the display or buffer creation fails.
	End Rem
	Function Create:TUIContext(display:TDisplay, theme:TUITheme = Null)
		If Not display Then Return Null
		Local frame:TDisplayBuffer = display.CreateBuffer()
		If Not frame Then Return Null
		Return CreateWithBuffer(frame, display, theme)
	End Function

	Rem
	bbdoc: Creates a display-only UI context without touch input processing.
	param: Display used to allocate and present the framebuffer.
	param: Optional theme; the standard dark theme is used when Null.
	returns: New context, or Null when creation fails.
	about: Read-only widgets, programmatic page changes, and value updates remain
	available. The context does not occupy a touch-event slot or perform
	touch-scroll momentum work during presentation.
	End Rem
	Function CreateDisplayOnly:TUIContext(display:TDisplay, theme:TUITheme = Null)
		Return Create(display, theme)
	End Function

	Rem
	bbdoc: Creates a context that draws into an existing framebuffer.
	param: Framebuffer owned by the caller.
	param: Optional display used for presentation.
	param: Optional theme; the standard dark theme is used when Null.
	returns: New context, or Null when the framebuffer is invalid.
	End Rem
	Function CreateWithBuffer:TUIContext(frame:TDisplayBuffer, display:TDisplay = Null, ..
			theme:TUITheme = Null)
		If Not frame Then Return Null
		Local result:TUIContext = New TUIContext
		result.display = display
		result.frame = frame
		result.graphics = TEmbedded2DContext.Create(frame, display)
		result.graphics.SetDirtyTracking(True)
		If theme Then result.themeValue = theme Else result.themeValue = TUITheme.Dark()
		result.rootWidget = New TUIColumn
		result.rootWidget._Attach(result, Null)
		result.rootWidget.uiStyle = result.themeValue.screen
		result.rootWidget.drawBackground = True
		result.InvalidateAll()
		Return result
	End Function

	Rem
	bbdoc: Creates a display-only UI context over an existing framebuffer.
	param: Framebuffer owned by the caller.
	param: Optional display used for presentation.
	param: Optional theme; the standard dark theme is used when Null.
	returns: New context, or Null when creation fails.
	End Rem
	Function CreateDisplayOnlyWithBuffer:TUIContext(frame:TDisplayBuffer, ..
			display:TDisplay = Null, theme:TUITheme = Null)
		Return CreateWithBuffer(frame, display, theme)
	End Function

	Rem
	bbdoc: Closes the input binding and releases retained focus, overlays, and toasts.
	about: The caller retains ownership of the display and any supplied framebuffer.
	End Rem
	Method Close()
		Local binding:TUIInputBinding = inputBinding
		inputBinding = Null
		If binding Then binding.Close()
		focusedWidget = Null
		deferredFocus = Null
		deferredFocusPending = False
		overlayWidget = Null
		overlayPreviousFocus = Null
		visibleToasts = New TUIToast[0]
		toastQueue = New TUIToast[0]
	End Method

	Rem
	bbdoc: Installs the context's single input binding.
	param: Input adapter to own until UnbindInput or Close.
	returns: True when installed, or False when invalid or already bound.
	End Rem
	Method BindInput:Int(binding:TUIInputBinding)
		If Not binding Or inputBinding Then Return False
		inputBinding = binding
		Return True
	End Method

	Rem
	bbdoc: Removes the input binding when it matches the current adapter.
	param: Binding requesting detachment.
	End Rem
	Method UnbindInput(binding:TUIInputBinding)
		If inputBinding = binding Then inputBinding = Null
	End Method

	Rem
	bbdoc: Returns the root vertical container.
	returns: Container filling the complete framebuffer.
	End Rem
	Method Root:TUIColumn()
		Return rootWidget
	End Method

	Rem
	bbdoc: Returns the active inherited theme.
	returns: Current theme.
	End Rem
	Method Theme:TUITheme()
		Return themeValue
	End Method

	Rem
	bbdoc: Returns the active popup or modal overlay.
	returns: Overlay container, or Null when none is visible.
	End Rem
	Method ActiveOverlay:TUIContainer()
		Return overlayWidget
	End Method

	Rem
	bbdoc: Reports whether a popup or modal overlay is visible.
	returns: True when ActiveOverlay is not Null.
	End Rem
	Method OverlayVisible:Int()
		Return overlayWidget <> Null
	End Method

	Rem
	bbdoc: Creates a detached popup menu attached to this context.
	returns: New popup menu ready for items and ShowOverlay.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method PopupMenu:TUIPopupMenu()
		Local menu:TUIPopupMenu = _UIRequireControls().CreatePopupMenu()
		menu._Attach(Self, Null)
		Return menu
	End Method

	Rem
	bbdoc: Creates a detached dialog attached to this context.
	param: Initial title.
	param: Initial wrapped message.
	returns: New dialog ready for actions and Show.
	about: Requires Embedded.UI.Controls or Embedded.UI.Interactive.
	End Rem
	Method Dialog:TUIDialog(title:String = "", message:String = "")
		Local dialog:TUIDialog = _UIRequireControls().CreateDialog()
		dialog.SetTitle(title)
		dialog.SetMessage(message)
		dialog._Attach(Self, Null)
		Return dialog
	End Method

	Rem
	bbdoc: Creates and schedules a non-modal notification.
	param: Notification message.
	param: Visible lifetime in milliseconds, or zero for persistent.
	param: One of the UIToast kind constants.
	param: Placement constant, or -1 to use the context default.
	returns: The visible or queued toast, or Null when the queue is full.
	End Rem
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

	Rem
	bbdoc: Returns the most recently activated visible toast.
	returns: Toast, or Null when none are visible.
	End Rem
	Method ActiveToast:TUIToast()
		If visibleToasts.Length = 0 Then Return Null
		Return visibleToasts[visibleToasts.Length - 1]
	End Method

	Rem
	bbdoc: Returns the number of currently visible toasts.
	returns: Visible count up to ToastVisibleLimit.
	End Rem
	Method VisibleToastCount:Int()
		Return visibleToasts.Length
	End Method

	Rem
	bbdoc: Returns the number of toasts waiting for a visible slot.
	returns: Pending queue length.
	End Rem
	Method PendingToastCount:Int()
		Return toastQueue.Length
	End Method

	Rem
	bbdoc: Sets the default placement for subsequently created toasts.
	param: One of the UIToast placement constants.
	End Rem
	Method SetToastPlacement(value:Int)
		If value < UIToastTopLeft Or value > UIToastBottomRight Then value = UIToastBottomCenter
		toastPlacement = value
	End Method

	Rem
	bbdoc: Returns the default toast placement.
	returns: One of the UIToast placement constants.
	End Rem
	Method ToastPlacement:Int()
		Return toastPlacement
	End Method

	Rem
	bbdoc: Sets how many toasts may be displayed simultaneously.
	param: Limit clamped from one through UIToastQueueMaximum.
	about: Excess visible toasts return to the front of the pending queue; newly
available slots are filled immediately.
	End Rem
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

	Rem
	bbdoc: Returns the simultaneous visible-toast limit.
	returns: Limit from one through UIToastQueueMaximum.
	End Rem
	Method ToastVisibleLimit:Int()
		Return toastVisibleLimit
	End Method

	Rem
	bbdoc: Sets spacing between notifications in the same placement stack.
	param: Non-negative gap in pixels.
	End Rem
	Method SetToastGap(value:Int)
		If value < 0 Then value = 0
		toastGap = value
		RequestLayout()
	End Method

	Rem
	bbdoc: Returns spacing between stacked notifications.
	returns: Gap in pixels.
	End Rem
	Method ToastGap:Int()
		Return toastGap
	End Method

	Rem
	bbdoc: Sets the minimum distance between notifications and display edges.
	param: Non-negative margin in pixels.
	End Rem
	Method SetToastMargin(value:Int)
		If value < 0 Then value = 0
		toastMargin = value
		RequestLayout()
	End Method

	Rem
	bbdoc: Returns the toast edge margin.
	returns: Margin in pixels.
	End Rem
	Method ToastMargin:Int()
		Return toastMargin
	End Method

	Rem
	bbdoc: Removes one visible or pending toast.
	param: Specific toast, or Null to dismiss the newest visible toast.
	returns: True when a toast was removed.
	End Rem
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

	Rem
	bbdoc: Removes every visible and pending toast.
	End Rem
	Method ClearToasts()
		For Local toast:TUIToast = EachIn visibleToasts
			InvalidateRect(toast.X(), toast.Y(), toast.Width(), toast.Height())
		Next
		visibleToasts = New TUIToast[0]
		toastQueue = New TUIToast[0]
	End Method

	Rem
	bbdoc: Shows a detached container above the root UI as the active overlay.
	param: Detached overlay container belonging to no parent.
	param: Requested left coordinate in pixels.
	param: Requested top coordinate in pixels.
	param: Width in pixels, or UILayoutAuto.
	param: Height in pixels, or UILayoutAuto.
	param: True to permit outside pointer presses to dismiss the overlay.
	returns: True when shown or already active.
	about: Size and position are clamped to the framebuffer. Focus moves into the
overlay and the previous focused widget is retained for dismissal.
	End Rem
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
			Local current:TUIWidget = widget
			While current
				If current.Focusable() Then
					first = current
					Exit
				End If
				current = _NextTreeWidget(current, widget, True)
			Wend
		End If
		If first Then SetFocus(first) Else ClearFocus()
		Return True
	End Method

	Rem
	bbdoc: Dismisses the active overlay and restores its previous focus.
	returns: True when an overlay was dismissed.
	End Rem
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

	Rem
	bbdoc: Returns the widget currently holding context focus.
	returns: Focused widget, or Null when focus is clear.
	End Rem
	Method FocusedWidget:TUIWidget()
		Return focusedWidget
	End Method

	Rem
	bbdoc: Assigns focus to an eligible widget or clears it.
	param: Widget owned by this context, or Null to clear focus.
	returns: True when the request is valid and focus was assigned.
	about: The focused widget is revealed inside ancestor scroll views and
EVENT_UIFOCUSCHANGED is emitted with the previous widget in `extra`.
	End Rem
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
	param: Widget to focus when presentation next processes deferred work.
	about: Navigation uses this to keep layout and framebuffer submission out of
	the input callback which changed the visible page.
	End Rem
	Method DeferFocus(widget:TUIWidget)
		deferredFocus = widget
		deferredFocusPending = True
	End Method

	Rem
	bbdoc: Clears context focus and emits EVENT_UIFOCUSCHANGED when necessary.
	End Rem
	Method ClearFocus()
		SetFocus(Null)
	End Method

	Rem
	bbdoc: Moves focus to the next eligible widget in retained-tree order.
	returns: True when focus was assigned; traversal wraps to the first widget.
	End Rem
	Method FocusNext:Int()
		Local focusRoot:TUIWidget = rootWidget
		If overlayWidget Then focusRoot = overlayWidget
		Local first:TUIWidget
		Local selectNext:Int = focusedWidget = Null
		Local current:TUIWidget = focusRoot
		While current
			If current.Focusable() Then
				If Not first Then first = current
				If selectNext And current <> focusedWidget Then Return SetFocus(current)
				If current = focusedWidget Then selectNext = True
			End If
			current = _NextTreeWidget(current, focusRoot, True)
		Wend
		Return SetFocus(first)
	End Method

	Rem
	bbdoc: Moves focus to the previous eligible widget in retained-tree order.
	returns: True when focus was assigned; traversal wraps to the last widget.
	End Rem
	Method FocusPrevious:Int()
		Local focusRoot:TUIWidget = rootWidget
		If overlayWidget Then focusRoot = overlayWidget
		Local previous:TUIWidget
		Local current:TUIWidget = focusRoot
		While current
			If current.Focusable() Then
				If current = focusedWidget And previous Then Return SetFocus(previous)
				previous = current
			End If
			current = _NextTreeWidget(current, focusRoot, True)
		Wend
		Return SetFocus(previous)
	End Method

	Rem
	bbdoc: Activates the currently focused widget.
	returns: True when the widget handled focused activation.
	End Rem
	Method ActivateFocused:Int()
		Local target:TUIWidget = focusedWidget
		If Not _CanFocus(target) Then Return False
		Return target._ActivateFocused()
	End Method

	Rem
	bbdoc: Adjusts the currently focused value or selection control.
	param: Signed adjustment amount interpreted by the focused widget.
	returns: True when the widget handled the adjustment.
	End Rem
	Method AdjustFocused:Int(delta:Int)
		If delta = 0 Or Not _CanFocus(focusedWidget) Then Return False
		Return focusedWidget._AdjustFocused(delta)
	End Method

	Rem
	bbdoc: Handles one application-level back action.
	returns: True when an overlay was dismissed or a page stack was popped.
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

	Rem
	bbdoc: Replaces the inherited context theme and schedules complete relayout.
	param: Fully initialized theme; Null is ignored.
	End Rem
	Method SetTheme(theme:TUITheme)
		If Not theme Then Return
		themeValue = theme
		rootWidget.uiStyle = theme.screen
		InvalidateAll()
		RequestLayout()
	End Method

	Rem
	bbdoc: Returns the Graphics2D context used for UI rendering.
	returns: Context drawing into Frame.
	End Rem
	Method Graphics:TEmbedded2DContext()
		Return graphics
	End Method

	Rem
	bbdoc: Returns the framebuffer containing retained UI output.
	returns: Context framebuffer.
	End Rem
	Method Frame:TDisplayBuffer()
		Return frame
	End Method

	Rem
	bbdoc: Schedules measurement and layout before the next render or hit test.
	End Rem
	Method RequestLayout()
		layoutPending = True
	End Method

	Rem
	bbdoc: Marks the complete framebuffer for redrawing.
	End Rem
	Method InvalidateAll()
		invalidCount = 1
		invalidX0[0] = 0
		invalidY0[0] = 0
		invalidX1[0] = frame.Width()
		invalidY1[0] = frame.Height()
	End Method

	Rem
	bbdoc: Adds a clipped dirty rectangle, merging overlapping regions.
	param: Left coordinate in framebuffer pixels.
	param: Top coordinate in framebuffer pixels.
	param: Width in pixels.
	param: Height in pixels.
	about: When the bounded region list is exhausted, the context falls back to a
single full-frame invalidation.
	End Rem
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

	Rem
	bbdoc: Immediately measures and assigns bounds to root, overlay, and toast trees.
	about: Applications normally use RequestLayout and allow Render or HitTest to
perform this work when required.
	End Rem
	Method Layout()
		rootWidget._SetBounds(0, 0, graphics.Width(), graphics.Height())
		rootWidget._LayoutChildren()
		If overlayWidget Then overlayWidget._LayoutChildren()
		If visibleToasts.Length Then _LayoutToasts()
		layoutPending = False
	End Method

	Rem
	bbdoc: Redraws all invalid regions into the context framebuffer.
	returns: True when at least one dirty region was rendered.
	about: Render updates pixels but does not submit them to the display. Use
Present for the normal render-and-submit path.
	End Rem
	Method Render:Int()
		If layoutPending Then Layout()
		If invalidCount = 0 Then Return False
		' The retained UI already owns a bounded, merged invalid-region list.
		' Avoid repeating the same dirty-region bookkeeping for every primitive
		' drawn within those clips; publish the final UI regions once instead.
		graphics.SetDirtyTracking(False)
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
		graphics.SetDirtyTracking(True)
		For Local index:Int = 0 Until invalidCount
			graphics.InvalidateRect(invalidX0[index], invalidY0[index], ..
				invalidX1[index] - invalidX0[index], invalidY1[index] - invalidY0[index])
		Next
		invalidCount = 0
		Return True
	End Method

	Rem
	bbdoc: Advances deferred UI work, renders dirty regions, and presents them.
	returns: Display presentation result, or True for a buffer-only context.
	about: Present advances touch-scroll momentum when requested by the input
binding, expires timed toasts, restores deferred focus after layout, and uses
Graphics2D dirty-region presentation when a display is attached.
	End Rem
	Method Present:Int()
		Local now:UInt = UInt(MilliSecs())
		If inputBinding And inputBinding.UpdatesScrollMomentum() Then
			_UpdateScrollMomentum(rootWidget, now)
			If overlayWidget Then _UpdateScrollMomentum(overlayWidget, now)
		End If
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

	Rem
	bbdoc: Finds the topmost clickable widget at a framebuffer coordinate.
	param: Display x coordinate in pixels.
	param: Display y coordinate in pixels.
	returns: Clickable widget, or Null when none is hit.
	about: An active overlay confines hit testing to its own bounds and tree.
	End Rem
	Method HitTest:TUIWidget(x:Int, y:Int)
		If layoutPending Then Layout()
		If overlayWidget Then
			If Not overlayWidget.Contains(x, y) Then Return Null
			Return _HitTest(overlayWidget, x, y)
		End If
		Return _HitTest(rootWidget, x, y)
	End Method

	Public
	Rem
	bbdoc: Expires visible timed toasts at the supplied monotonic time.
	param: Current time in milliseconds.
	about: Called by Present and exposed for specialized presentation loops.
	End Rem
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

	Rem
	bbdoc: Moves a prepared toast into the visible stack.
	param: Toast attached to this context.
	param: Current monotonic time in milliseconds.
	about: Intended for the context's bounded toast scheduler.
	End Rem
	Method _ActivateToast(toast:TUIToast, now:UInt)
		visibleToasts = visibleToasts[..visibleToasts.Length + 1]
		visibleToasts[visibleToasts.Length - 1] = toast
		toast._Show(now)
		RequestLayout()
		_LayoutToasts()
	End Method

	Rem
	bbdoc: Measures and positions all visible toast placement stacks.
	about: Toast width is bounded by the display margin and an upper width of 420
pixels. Stacks grow inward from their configured edge or around the center.
	End Rem
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

	Rem
	bbdoc: Draws one visible widget subtree intersecting a dirty clip rectangle.
	param: Root of the subtree to draw.
	param: Clip left coordinate in pixels.
	param: Clip top coordinate in pixels.
	param: Clip width in pixels.
	param: Clip height in pixels.
	about: Children are drawn in insertion order, followed by the widget overlay
and focus indicator. Clipping containers narrow the Graphics2D viewport.
	End Rem
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

	Rem
	bbdoc: Reveals a widget within every ancestor scroll view.
	param: Widget owned by this context.
	End Rem
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

	Rem
	bbdoc: Finds the nearest scroll view containing a widget.
	param: Widget from which to begin ancestor traversal.
	returns: Nearest scroll view, or Null.
	about: Intended for input adapters.
	End Rem
	Method _ContainingScroll:TUIScrollView(widget:TUIWidget)
		Local current:TUIWidget = widget
		While current
			Local scroll:TUIScrollView = TUIScrollView(current)
			If scroll Then Return scroll
			current = current.Parent()
		Wend
		Return Null
	End Method

	Rem
	bbdoc: Finds the deepest visible scroll view containing a coordinate.
	param: Root widget of the subtree to search.
	param: Display x coordinate in pixels.
	param: Display y coordinate in pixels.
	returns: Scroll view, or Null.
	about: Intended for input adapters beginning a drag on non-clickable content.
	End Rem
	Method _ScrollAt:TUIScrollView(widget:TUIWidget, x:Int, y:Int)
		If Not widget Or Not widget.Visible() Or Not widget.Contains(x, y) Then Return Null
		For Local index:Int = widget.uiChildren.Length - 1 To 0 Step -1
			Local found:TUIScrollView = _ScrollAt(widget.uiChildren[index], x, y)
			If found Then Return found
		Next
		Return TUIScrollView(widget)
	End Method

	Rem
	bbdoc: Advances momentum in every visible scroll view in a subtree.
	param: Root widget of the subtree to update.
	param: Current monotonic time in milliseconds.
	End Rem
	Method _UpdateScrollMomentum(widget:TUIWidget, now:UInt)
		If Not widget Or Not widget.Visible() Then Return
		Local scroll:TUIScrollView = TUIScrollView(widget)
		If scroll Then scroll._UpdateMomentum(now)
		For Local child:TUIWidget = EachIn widget.uiChildren
			_UpdateScrollMomentum(child, now)
		Next
	End Method

	Rem
	bbdoc: Draws the active theme focus indicator around one widget.
	param: Focused widget.
	End Rem
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

	Rem
	bbdoc: Pops the deepest visible page stack in a widget subtree.
	param: Root widget to search.
	returns: True when a stack was popped.
	about: Traversal is iterative to keep embedded native stack use bounded.
	End Rem
	Method _BackInWidget:Int(widget:TUIWidget)
		If Not widget Or Not widget.Visible() Then Return False
		' Walk the tree in reverse post-order without recursion. Embedded entry
		' points carry precise-GC root frames, so a deeply composed page can
		' otherwise exhaust the small native task stack while handling Back.
		Local current:TUIWidget = widget
		While current
			' Descend through the last visible child until reaching a leaf.
			Local child:TUIWidget
			For Local index:Int = current.uiChildren.Length - 1 To 0 Step -1
				If current.uiChildren[index].Visible() Then
					child = current.uiChildren[index]
					Exit
				End If
			Next
			If child Then
				current = child
				Continue
			End If

			While current
				Local stack:TUIPageStack = TUIPageStack(current)
				If stack And stack.CanPop() Then Return stack.Pop()
				If current = widget Then Return False

				Local parent:TUIContainer = current.Parent()
				If Not parent Then Return False
				Local sibling:TUIWidget
				For Local index:Int = parent.uiChildren.Length - 1 To 0 Step -1
					If parent.uiChildren[index] = current Then
						For Local siblingIndex:Int = index - 1 To 0 Step -1
							If parent.uiChildren[siblingIndex].Visible() Then
								sibling = parent.uiChildren[siblingIndex]
								Exit
							End If
						Next
						Exit
					End If
				Next
				If sibling Then
					current = sibling
					Exit
				End If
				current = parent
			Wend
		Wend
		Return False
	End Method

	Rem
	bbdoc: Tests whether a widget is eligible for focus in the current UI state.
	param: Candidate widget.
	returns: True when it and all ancestors are visible and enabled, and it lies
inside the active overlay when one is present.
	End Rem
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

	Rem
	bbdoc: Tests whether a widget is contained by an ancestor, including itself.
	param: Candidate descendant.
	param: Candidate ancestor.
	returns: True when the ancestor is found in the parent chain.
	End Rem
	Method _IsDescendant:Int(widget:TUIWidget, ancestor:TUIWidget)
		Local current:TUIWidget = widget
		While current
			If current = ancestor Then Return True
			current = current.Parent()
		Wend
		Return False
	End Method

	Rem
	bbdoc: Clears focus when the focused widget lies in a supplied subtree.
	param: Subtree root being hidden, disabled, or detached.
	End Rem
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

	' Returns the next widget in pre-order without recursion. When enabledOnly
	' is true, disabled subtrees are skipped for focus traversal.
	Rem
	bbdoc: Returns the next visible widget in iterative pre-order traversal.
	param: Current widget.
	param: Traversal root which must not be crossed.
	param: True to skip disabled subtrees.
	returns: Next widget, or Null at the end of the subtree.
	End Rem
	Method _NextTreeWidget:TUIWidget(widget:TUIWidget, root:TUIWidget, enabledOnly:Int = False)
		If Not widget Or Not root Then Return Null
		For Local child:TUIWidget = EachIn widget.uiChildren
			If child.Visible() And (Not enabledOnly Or child.Enabled()) Then Return child
		Next
		Local current:TUIWidget = widget
		While current And current <> root
			Local parent:TUIContainer = current.Parent()
			If Not parent Then Return Null
			Local foundCurrent:Int
			For Local sibling:TUIWidget = EachIn parent.uiChildren
				If foundCurrent Then
					If sibling.Visible() And (Not enabledOnly Or sibling.Enabled()) Then Return sibling
				Else If sibling = current Then
					foundCurrent = True
				End If
			Next
			current = parent
		Wend
		Return Null
	End Method

	Rem
	bbdoc: Recursively finds the topmost clickable widget in a subtree.
	param: Root widget to search.
	param: Display x coordinate in pixels.
	param: Display y coordinate in pixels.
	returns: Clickable widget, or Null.
	End Rem
	Method _HitTest:TUIWidget(widget:TUIWidget, x:Int, y:Int)
		If Not widget Or Not widget.Contains(x, y) Then Return Null
		For Local index:Int = widget.uiChildren.Length - 1 To 0 Step -1
			Local found:TUIWidget = _HitTest(widget.uiChildren[index], x, y)
			If found Then Return found
		Next
		If widget.clickable Then Return widget
		Return Null
	End Method

	Rem
	bbdoc: Tests widget bounds against a rectangle.
	param: Widget to test.
	param: Rectangle left coordinate.
	param: Rectangle top coordinate.
	param: Rectangle width.
	param: Rectangle height.
	returns: True when the bounds overlap.
	End Rem
	Method _Intersects:Int(widget:TUIWidget, x:Int, y:Int, width:Int, height:Int)
		Return widget.X() < x + width And widget.X() + widget.Width() > x And ..
			widget.Y() < y + height And widget.Y() + widget.Height() > y
	End Method
End Type

?
