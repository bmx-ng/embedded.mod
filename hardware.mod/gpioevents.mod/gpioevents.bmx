' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Managed GPIO interrupt delivery shared by embedded targets.
End Rem
Module Embedded.Hardware.GPIOEvents
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import Embedded.Hardware.GPIO
Import Embedded.Runtime.Events

Rem
bbdoc: Emitted after a registered GPIO interrupt.
about: EventData contains GPIOIRQ flags and EventMods contains the pin number.
Use GPIOIRQTimeUS for the 64-bit timestamp captured by the native handler.
End Rem
Global EVENT_GPIOIRQ:Int = AllocUserEventId("GPIOIRQ")

Rem
bbdoc: A managed, timestamped GPIO interrupt event source.
about: Close disables the interrupt and unregisters the source. It is required
because an open source is deliberately retained by the event bridge.
End Rem
Type TGPIOIRQSource Implements ICloseable
	Private
	Field pin:Int = -1
	Field eventMask:UInt
	Field eventToken:UInt
	Field tokenInstalled:Int
	Field irqEnabled:Int

	Public
	Function Create:TGPIOIRQSource(pin:UInt, eventMask:UInt)
		If eventMask = 0 Then Return Null
		Local source:TGPIOIRQSource = New TGPIOIRQSource
		source.pin = pin
		source.eventMask = eventMask
		source.eventToken = RegisterEmbeddedEventSource(source, EVENT_GPIOIRQ, True)
		If source.eventToken = 0 Then
			source.Close()
			Return Null
		End If
		If Not _GPIOSetEventToken(pin, source.eventToken) Then
			source.Close()
			Return Null
		End If
		source.tokenInstalled = True
		If Not GPIOSetIRQEnabled(pin, eventMask, True) Then
			source.Close()
			Return Null
		End If
		source.irqEnabled = True
		Return source
	End Function

	Method Pin:Int()
		Return pin
	End Method

	Method EventMask:UInt()
		Return eventMask
	End Method

	Method IsOpen:Int()
		Return pin >= 0
	End Method

	Method Close()
		If pin < 0 Then Return
		If irqEnabled Then GPIOSetIRQEnabled(pin, eventMask, False)
		If tokenInstalled Then _GPIOSetEventToken(pin, 0)
		If eventToken Then ReleaseEmbeddedEventSource(eventToken)
		irqEnabled = False
		tokenInstalled = False
		eventToken = 0
		pin = -1
	End Method

	Method Delete()
		Close()
	End Method
End Type

Rem
bbdoc: Returns the native microsecond timestamp carried by a GPIO IRQ event.
End Rem
Function GPIOIRQTimeUS:ULong(event:TEvent)
	If Not event Or event.id <> EVENT_GPIOIRQ Then Return 0
	Return ULong(UInt(event.x)) | (ULong(UInt(event.y)) Shl 32)
End Function
?
