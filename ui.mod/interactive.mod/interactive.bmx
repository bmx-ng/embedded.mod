' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional touch interaction adapter for Embedded.UI.
about: Import this module only when a retained UI uses a touch device. Display-
only applications can import Embedded.UI without linking the touch abstraction,
global event hook, contact tracking adapter, or touch-scroll update path.
End Rem
Module Embedded.UI.Interactive
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import Embedded.Drivers.Display
Import Embedded.Drivers.Touch
Import Embedded.UI
Import Embedded.UI.Controls

Rem
bbdoc: Maximum number of touch devices that may be bound simultaneously.
End Rem
Const UITouchContextMaximum:Int = 4

Private

Global _touchInputs:TUITouchInput[UITouchContextMaximum]

Function _UITouchEventHook:Object(hookId:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If Not event Then Return data
	If event.id <> EVENT_TOUCHDOWN And event.id <> EVENT_TOUCHMOVE And ..
			event.id <> EVENT_TOUCHUP Then Return data
	For Local input:TUITouchInput = EachIn _touchInputs
		If input Then input.HandleEvent(event)
	Next
	Return data
End Function

Public

Rem
bbdoc: Connects one touch device to an Embedded.UI context.
about: The binding is retained by the adapter registry and is closed
automatically by TUIContext.Close().
End Rem
Type TUITouchInput Extends TUIInputBinding Final
	Private
	Field ui:TUIContext
	Field device:TTouchDevice
	Field slot:Int = -1
	Field pressedWidget:TUIWidget
	Field pressedContact:Int = -1
	Field pressedArmed:Int
	Field touchScroll:TUIScrollView
	Field touchStartY:Int
	Field touchLastY:Int
	Field touchScrolled:Int
	Field pendingTrackWidget:TUIWidget
	Field pendingTrackX:Int
	Field pendingTrackY:Int
	Field pendingTrack:Int
	Field coalescePointerMoves:Int = True

	Public
	Rem
	bbdoc: Attaches a touch device to an existing UI context.
	param: UI context that will receive normalized pointer interaction.
	param: Touch device that emits BRL.Event touch events.
	returns: A retained binding, or Null when the arguments are invalid, the
	context already has input, or all adapter slots are occupied.
	End Rem
	Function Attach:TUITouchInput(ui:TUIContext, device:TTouchDevice)
		If Not ui Or Not device Then Return Null
		Local freeSlot:Int = -1
		For Local index:Int = 0 Until UITouchContextMaximum
			If Not _touchInputs[index] Then
				freeSlot = index
				Exit
			End If
		Next
		If freeSlot < 0 Then Return Null
		Local result:TUITouchInput = New TUITouchInput
		result.ui = ui
		result.device = device
		result.slot = freeSlot
		If Not ui.BindInput(result) Then Return Null
		_touchInputs[freeSlot] = result
		Return result
	End Function

	Rem
	bbdoc: Creates a UI context and attaches a touch device.
	param: Display presented by the new context.
	param: Touch device used for pointer interaction.
	param: Optional theme; the standard dark theme is used when Null.
	returns: The initialized context, or Null when creation or attachment fails.
	End Rem
	Function CreateContext:TUIContext(display:TDisplay, device:TTouchDevice, ..
			theme:TUITheme = Null)
		Local ui:TUIContext = TUIContext.Create(display, theme)
		If Not ui Then Return Null
		If Not Attach(ui, device) Then
			ui.Close()
			Return Null
		End If
		Return ui
	End Function

	Rem
	bbdoc: Creates a UI context over an existing framebuffer and attaches touch.
	param: Display buffer to draw into.
	param: Display that presents the buffer.
	param: Touch device used for pointer interaction.
	param: Optional theme; the standard dark theme is used when Null.
	returns: The initialized context, or Null when creation or attachment fails.
	about: The caller retains ownership of the supplied display buffer.
	End Rem
	Function CreateContextWithBuffer:TUIContext(frame:TDisplayBuffer, ..
			display:TDisplay, device:TTouchDevice, theme:TUITheme = Null)
		Local ui:TUIContext = TUIContext.CreateWithBuffer(frame, display, theme)
		If Not ui Then Return Null
		If Not Attach(ui, device) Then
			ui.Close()
			Return Null
		End If
		Return ui
	End Function

	Rem
	bbdoc: Returns the context receiving this adapter's pointer interaction.
	returns: The attached context, or Null after Close.
	End Rem
	Method Context:TUIContext()
		Return ui
	End Method

	Rem
	bbdoc: Returns the touch device monitored by this adapter.
	returns: The attached device, or Null after Close.
	End Rem
	Method Device:TTouchDevice()
		Return device
	End Method

	Rem
	bbdoc: Reports that this adapter advances inertial scrolling from touch events.
	returns: True.
	End Rem
	Method UpdatesScrollMomentum:Int() Override
		Return True
	End Method

	Rem
	bbdoc: Enables or disables frame-coalesced pointer movement.
	param: True to retain only the latest move until Present or touch release.
	about: Coalescing is enabled by default. It prevents callbacks, layout, and
	invalidation for intermediate touch samples which cannot be displayed. Turn
	it off only when an application requires every raw pointer movement.
	End Rem
	Method SetPointerMoveCoalescing(value:Int)
		value = value <> 0
		If coalescePointerMoves = value Then Return
		FlushPendingInput()
		coalescePointerMoves = value
	End Method

	Rem
	bbdoc: Reports whether pointer moves are coalesced at the frame boundary.
	returns: True when only the latest pending move is applied by Present.
	End Rem
	Method PointerMoveCoalescing:Int()
		Return coalescePointerMoves
	End Method

	Rem
	bbdoc: Applies the newest pointer movement retained for the next frame.
	about: Called automatically by TUIContext.Present and before touch release.
	End Rem
	Method FlushPendingInput() Override
		If Not pendingTrack Then Return
		Local target:TUIWidget = pendingTrackWidget
		Local x:Int = pendingTrackX
		Local y:Int = pendingTrackY
		pendingTrack = False
		pendingTrackWidget = Null
		If Not target Or target <> pressedWidget Then Return
		If Not target._TrackPointer(x, y) Then
			pressedArmed = target.Contains(x, y)
			target._SetPressed(pressedArmed)
		End If
	End Method

	Rem
	bbdoc: Detaches the device and releases this adapter slot.
	about: Closing is safe to repeat. TUIContext.Close calls this automatically
	for its active input binding.
	End Rem
	Method Close() Override
		If slot >= 0 And slot < UITouchContextMaximum And _touchInputs[slot] = Self Then ..
			_touchInputs[slot] = Null
		slot = -1
		Local oldUI:TUIContext = ui
		ui = Null
		device = Null
		If pressedWidget Then pressedWidget._SetPressed(False)
		pressedWidget = Null
		pendingTrackWidget = Null
		pendingTrack = False
		pressedContact = -1
		pressedArmed = False
		touchScroll = Null
		touchScrolled = False
		If oldUI Then oldUI.UnbindInput(Self)
	End Method

	Rem
	bbdoc: Translates one touch event into focus, scrolling, and widget activation.
	param: Touch event to process; unrelated events and devices are ignored.
	End Rem
	Method HandleEvent(event:TEvent)
		If Not ui Or Not device Or Not event Or event.source <> device Then Return
		Local frame:TDisplayBuffer = ui.Frame()
		Local x:Int
		Local y:Int
		If frame.Width() > 1 Then x = Int((Long(event.x) * (frame.Width() - 1) + 5000) / 10000)
		If frame.Height() > 1 Then y = Int((Long(event.y) * (frame.Height() - 1) + 5000) / 10000)
		Select event.id
			Case EVENT_TOUCHDOWN
				If pressedContact >= 0 Then Return
				If ui.overlayWidget And Not ui.overlayWidget.Contains(x, y) Then
					If ui.overlayDismissOutside Then ui.DismissOverlay()
					pressedContact = event.data
					Return
				End If
				Local target:TUIWidget = ui.HitTest(x, y)
				touchScroll = ui._ContainingScroll(target)
				If Not touchScroll Then
					If ui.overlayWidget Then
						touchScroll = ui._ScrollAt(ui.overlayWidget, x, y)
					Else
						touchScroll = ui._ScrollAt(ui.rootWidget, x, y)
					End If
				End If
				If Not target And Not touchScroll Then Return
				pressedContact = event.data
				touchStartY = y
				touchLastY = y
				touchScrolled = False
				If touchScroll Then touchScroll._BeginDrag(UInt(MilliSecs()))
				If target And target.Enabled() Then
					ui.SetFocus(target)
					pressedWidget = target
					pressedArmed = True
					target._SetPressed(True)
					target._BeginPointer(x, y)
				End If
			Case EVENT_TOUCHMOVE
				If pressedContact = event.data Then
					If touchScroll And (touchScrolled Or Abs(y - touchStartY) >= UIScrollDragThreshold) Then
						If Not touchScrolled Then
							touchScrolled = True
							pressedArmed = False
							pendingTrackWidget = Null
							pendingTrack = False
							If pressedWidget Then pressedWidget._SetPressed(False)
						End If
						Local now:UInt = UInt(MilliSecs())
						touchScroll._DragBy(touchLastY - y, now)
						touchLastY = y
					Else If pressedWidget Then
						If coalescePointerMoves Then
							pendingTrackWidget = pressedWidget
							pendingTrackX = x
							pendingTrackY = y
							pendingTrack = True
						Else If Not pressedWidget._TrackPointer(x, y) Then
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
						If Not touchScrolled Then
							' The release coordinate is newer than any retained movement.
							' Drop the intermediate sample and apply only the final state.
							pendingTrackWidget = Null
							pendingTrack = False
							target._TrackPointer(x, y)
						End If
						target._EndPointer()
						activate = Not touchScrolled And pressedArmed And target.Contains(x, y) And target.Enabled()
						target._SetPressed(False)
					End If
					pressedWidget = Null
					pendingTrackWidget = Null
					pendingTrack = False
					pressedContact = -1
					pressedArmed = False
					touchScroll = Null
					touchScrolled = False
					If activate Then _Activate(target, x, y)
				End If
		End Select
	End Method

	Private
	Method _Activate(target:TUIWidget, x:Int, y:Int)
		If target Then target._ActivatePointer(x, y)
	End Method
End Type

AddHook EmitEventHook, _UITouchEventHook
?
