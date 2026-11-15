' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable touch input and BRL.Event translation.
about: Touch controllers report contacts in display pixels. Registered devices
emit the standard BRL.Event touch events during PollSystem, using the desktop
convention of a contact id in event.data and coordinates normalized to 0..10000.
End Rem
Module Embedded.Drivers.Touch
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import BRL.System
Import Embedded.Drivers.Display

Const TouchMaximumContacts:Int = 10
Const TouchMaximumDevices:Int = 4
Const TouchReleaseDebouncePolls:Int = 2

Private

Global _touchDevices:TTouchDevice[TouchMaximumDevices]

Function _NormalizedTouchCoordinate:Int(value:Int, extent:Int)
	If extent <= 1 Then Return 0
	If value < 0 Then value = 0
	If value >= extent Then value = extent - 1
	Return Int((Long(value) * 10000 + (extent - 1) / 2) / (extent - 1))
End Function

Function _PollTouchDevices:Object(hookId:Int, data:Object, context:Object)
	For Local device:TTouchDevice = EachIn _touchDevices
		If device Then device._PollEvents()
	Next
	Return data
End Function

Public

Rem
bbdoc: Base contract for a polled touch controller.
about: A driver refreshes its fixed contact snapshot in PollContacts. Contact
coordinates are pixel positions in the associated display orientation.
End Rem
Type TTouchDevice Abstract
	Private
	Field eventSlot:Int = -1
	Field previousCount:Int
	Field previousIds:Int[TouchMaximumContacts]
	Field previousX:Int[TouchMaximumContacts]
	Field previousY:Int[TouchMaximumContacts]
	Field previousMissing:Int[TouchMaximumContacts]
	Field nextIds:Int[TouchMaximumContacts]
	Field nextX:Int[TouchMaximumContacts]
	Field nextY:Int[TouchMaximumContacts]
	Field nextMissing:Int[TouchMaximumContacts]
	Field configuredOrientation:Int

	Method _TransformContact(x:Int Var, y:Int Var)
		Local nativeX:Int = x
		Local nativeY:Int = y
		Select configuredOrientation
			Case DisplayOrientation90
				x = nativeY
				y = Width() - 1 - nativeX
			Case DisplayOrientation180
				x = Width() - 1 - nativeX
				y = Height() - 1 - nativeY
			Case DisplayOrientation270
				x = Height() - 1 - nativeY
				y = nativeX
		End Select
	End Method

	Method _FindPrevious:Int(id:Int)
		For Local index:Int = 0 Until previousCount
			If previousIds[index] = id Then Return index
		Next
		Return -1
	End Method

	Method _FindCurrent:Int(id:Int, count:Int)
		For Local index:Int = 0 Until count
			If ContactId(index) = id Then Return index
		Next
		Return -1
	End Method

	Public
	Method _PollEvents()
		Local count:Int = PollContacts()
		If count < 0 Then Return
		If count > TouchMaximumContacts Then count = TouchMaximumContacts
		Local nextCount:Int

		For Local index:Int = 0 Until count
			Local id:Int = ContactId(index)
			Local x:Int = ContactX(index)
			Local y:Int = ContactY(index)
			_TransformContact(x, y)
			Local previous:Int = _FindPrevious(id)
			Local eventId:Int
			If previous < 0 Then
				eventId = EVENT_TOUCHDOWN
			Else If previousX[previous] <> x Or previousY[previous] <> y Then
				eventId = EVENT_TOUCHMOVE
			End If
			If eventId Then
				EmitEvent(CreateEvent(eventId, Self, id, 0, ..
					_NormalizedTouchCoordinate(x, LogicalWidth()), ..
					_NormalizedTouchCoordinate(y, LogicalHeight())))
			End If
			If nextCount < TouchMaximumContacts Then
				nextIds[nextCount] = id
				nextX[nextCount] = x
				nextY[nextCount] = y
				nextMissing[nextCount] = 0
				nextCount :+ 1
			End If
		Next

		For Local previous:Int = 0 Until previousCount
			If _FindCurrent(previousIds[previous], count) < 0 Then
				Local missing:Int = previousMissing[previous] + 1
				If missing >= TouchReleaseDebouncePolls Then
					EmitEvent(CreateEvent(EVENT_TOUCHUP, Self, previousIds[previous], 0, ..
						_NormalizedTouchCoordinate(previousX[previous], LogicalWidth()), ..
						_NormalizedTouchCoordinate(previousY[previous], LogicalHeight())))
				Else If nextCount < TouchMaximumContacts Then
					nextIds[nextCount] = previousIds[previous]
					nextX[nextCount] = previousX[previous]
					nextY[nextCount] = previousY[previous]
					nextMissing[nextCount] = missing
					nextCount :+ 1
				End If
			End If
		Next

		previousCount = nextCount
		For Local index:Int = 0 Until nextCount
			previousIds[index] = nextIds[index]
			previousX[index] = nextX[index]
			previousY[index] = nextY[index]
			previousMissing[index] = nextMissing[index]
		Next
	End Method

	Method Width:Int() Abstract
	Method Height:Int() Abstract
	Method PollContacts:Int() Abstract
	Method ContactId:Int(index:Int) Abstract
	Method ContactX:Int(index:Int) Abstract
	Method ContactY:Int(index:Int) Abstract

	Rem
	bbdoc: Configures the clockwise orientation applied to emitted touch coordinates.
	End Rem
	Method SetOrientation:Int(degrees:Int)
		Local normalized:Int = NormalizeDisplayOrientation(degrees)
		If normalized < 0 Then Return False
		configuredOrientation = normalized
		previousCount = 0
		Return True
	End Method

	Method Orientation:Int()
		Return configuredOrientation
	End Method

	Method LogicalWidth:Int()
		If configuredOrientation = DisplayOrientation90 Or ..
				configuredOrientation = DisplayOrientation270 Then Return Height()
		Return Width()
	End Method

	Method LogicalHeight:Int()
		If configuredOrientation = DisplayOrientation90 Or ..
				configuredOrientation = DisplayOrientation270 Then Return Width()
		Return Height()
	End Method

	Rem
	bbdoc: Starts standard touch-event generation during PollSystem.
	End Rem
	Method StartEvents:Int()
		If eventSlot >= 0 Then Return True
		For Local slot:Int = 0 Until TouchMaximumDevices
			If Not _touchDevices[slot] Then
				_touchDevices[slot] = Self
				eventSlot = slot
				previousCount = 0
				Return True
			End If
		Next
		Return False
	End Method

	Rem
	bbdoc: Stops touch-event generation for this device.
	End Rem
	Method StopEvents()
		If eventSlot >= 0 And eventSlot < TouchMaximumDevices And ..
			_touchDevices[eventSlot] = Self Then _touchDevices[eventSlot] = Null
		eventSlot = -1
		previousCount = 0
	End Method
End Type

AddHook PollSystemHook, _PollTouchDevices
?
