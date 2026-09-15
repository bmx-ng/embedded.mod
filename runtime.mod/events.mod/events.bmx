' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Deferred native-event bridge shared by embedded targets.
about: Interrupt handlers and other native producers enqueue numeric records in
fixed native storage. PollSystem and WaitSystem drain those records and create
ordinary BlitzMax events in managed application context.
End Rem
Module Embedded.Runtime.Events
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import BRL.System

Const EmbeddedEventSourceCapacity:UInt = 64

Private

Const EmbeddedEventSourceSlotBits:UInt = 6
Const EmbeddedEventSourceSlotMask:UInt = EmbeddedEventSourceCapacity - 1
Const EmbeddedEventGenerationMask:UInt = $03ffffff

Global _embeddedEventSources:Object[EmbeddedEventSourceCapacity]
Global _embeddedEventIds:Int[EmbeddedEventSourceCapacity]
Global _embeddedEventPersistent:Int[EmbeddedEventSourceCapacity]
Global _embeddedEventGenerations:UInt[EmbeddedEventSourceCapacity]

Extern "C"
	Function _EmbeddedTakeDeferredEvent:Int(token:UInt Var, eventData:UInt Var, eventMods:UInt Var, eventX:UInt Var, eventY:UInt Var) = "bmx_embedded_event_take"
	Function _EmbeddedDeferredEventPending:UInt() = "bmx_embedded_event_pending"
	Function _EmbeddedDeferredEventDropped:UInt() = "bmx_embedded_event_dropped"
End Extern

Function _EmbeddedEventSlotValid:Int(token:UInt, slot:UInt)
	Return slot < EmbeddedEventSourceCapacity And ..
		_embeddedEventGenerations[slot] = (token Shr EmbeddedEventSourceSlotBits)
End Function

Function _EmbeddedPollDeferredEvents:Object(hookId:Int, data:Object, context:Object)
	Local token:UInt
	Local eventData:UInt
	Local eventMods:UInt
	Local eventX:UInt
	Local eventY:UInt
	While _EmbeddedTakeDeferredEvent(token, eventData, eventMods, eventX, eventY)
		Local slot:UInt = token & EmbeddedEventSourceSlotMask
		If _EmbeddedEventSlotValid(token, slot)
			Local source:Object = _embeddedEventSources[slot]
			If source
				EmitEvent(CreateEvent(_embeddedEventIds[slot], source, Int(eventData), ..
					Int(eventMods), Int(eventX), Int(eventY)))
				If Not _embeddedEventPersistent[slot] Then ReleaseEmbeddedEventSource(token)
			End If
		End If
	Wend
	Return data
End Function

Public

Rem
bbdoc: Registers a managed object as a deferred native-event source.
about: The returned token is safe to retain in native peripheral state. A
persistent source remains registered until explicitly released; a one-shot
source is released after its first event is emitted.
End Rem
Function RegisterEmbeddedEventSource:UInt(source:Object, eventId:Int, persistent:Int = False)
	If Not source Or eventId = 0 Then Return 0
	For Local slot:UInt = 0 Until EmbeddedEventSourceCapacity
		If Not _embeddedEventSources[slot]
			Local generation:UInt = (_embeddedEventGenerations[slot] + 1) & EmbeddedEventGenerationMask
			If generation = 0 Then generation = 1
			_embeddedEventGenerations[slot] = generation
			_embeddedEventIds[slot] = eventId
			_embeddedEventPersistent[slot] = persistent
			_embeddedEventSources[slot] = source
			Return (generation Shl EmbeddedEventSourceSlotBits) | slot
		End If
	Next
	Return 0
End Function

Rem
bbdoc: Releases a previously registered deferred native-event source.
End Rem
Function ReleaseEmbeddedEventSource:Int(token:UInt)
	If token = 0 Then Return False
	Local slot:UInt = token & EmbeddedEventSourceSlotMask
	If Not _EmbeddedEventSlotValid(token, slot) Then Return False
	If Not _embeddedEventSources[slot] Then Return False
	_embeddedEventSources[slot] = Null
	_embeddedEventIds[slot] = 0
	_embeddedEventPersistent[slot] = False
	Return True
End Function

Rem
bbdoc: Returns the number of native deferred events waiting to be dispatched.
End Rem
Function EmbeddedDeferredEventPending:UInt()
	Return _EmbeddedDeferredEventPending()
End Function

Rem
bbdoc: Returns the number of native events discarded because the queue was full.
End Rem
Function EmbeddedDeferredEventDropped:UInt()
	Return _EmbeddedDeferredEventDropped()
End Function

AddHook PollSystemHook, _EmbeddedPollDeferredEvents
?
