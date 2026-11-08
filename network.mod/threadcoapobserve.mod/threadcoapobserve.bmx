' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional CoAP Observe subscriptions over Thread.
about: Import this module to enable OpenThread Observe support in the firmware.
One resource, one subscriber, and one client subscription are supported.
End Rem
Module Embedded.Network.ThreadCoAPObserve
?nrf52 or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System
Import Embedded.Network.ThreadCoAP

Rem
bbdoc: Maximum Observe value payload in bytes.
End Rem
Const ThreadCoAPObserveMaxPayload:Int = 1024
Rem
bbdoc: Number of queued Observe values.
End Rem
Const ThreadCoAPObserveQueueDepth:Int = 4

Private
Extern "C"
	Function _ObserveResource:Int(path:Byte Ptr) = "bmx_thread_coap_observe_resource"
	Function _ObserveHasSubscriber:Int() = "bmx_thread_coap_observe_has_subscriber"
	Function _ObservePublish:Int(code:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_observe_publish"
	Function _ObserveSubscribe:Int(address:Byte Ptr, port:Int, path:Byte Ptr) = "bmx_thread_coap_observe_subscribe"
	Function _ObserveRead:Int(data:Byte Ptr, capacity:Int, code:Int Var, sequence:UInt Var) = "bmx_thread_coap_observe_read"
	Function _ObserveDropped:UInt() = "bmx_thread_coap_observe_dropped"
	Function _ObserveCancel:Int() = "bmx_thread_coap_observe_cancel"
End Extern

Public

Rem
bbdoc: Register one observable CoAP resource.
param: URI resource path without a leading slash.
returns: Zero on success or a negative error.
about: Call ThreadCoAPStart first.
End Rem
Function ThreadCoAPObserveResource:Int(path:String)
	If Not path Then
		Return -22
	End If

	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _ObserveResource(bytes)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Check whether an Observe subscriber is present.
returns: True if a subscriber is active; otherwise False.
End Rem
Function ThreadCoAPObserveHasSubscriber:Int()
	Return _ObserveHasSubscriber()
End Function

Rem
bbdoc: Send an initial value or later Observe notification.
param: Payload bytes to send; Null sends an empty payload where allowed.
param: CoAP response code; on read, receives the response code.
returns: Zero on success or a negative error.
End Rem
Function ThreadCoAPObservePublish:Int(data:Byte[], code:Int = ThreadCoAPContent)
	Local length:Int
	If data Then
		length = data.length
	End If

	Return _ObservePublish(code, data, length)
End Function

Rem
bbdoc: Subscribe to an observable resource.
param: The peer IPv6 address; on receive, receives the sender address.
param: URI resource path without a leading slash.
param: The UDP or TCP port.
returns: Zero if queued or a negative error.
about: Read values with ThreadCoAPObserveRead and end the subscription with ThreadCoAPObserveCancel.
End Rem
Function ThreadCoAPObserveSubscribe:Int(address:String, path:String, port:Int = 5683)
	If Not address Or Not path Then
		Return -22
	End If

	Local a:Byte Ptr = address.ToUTF8String()
	Local p:Byte Ptr = path.ToUTF8String()
	Local result:Int = _ObserveSubscribe(a, port, p)
	MemFree(a)
	MemFree(p)
	Return result
End Function

Rem
bbdoc: Read the next Observe value.
param: Buffer for the received payload.
param: Receives the CoAP response code.
param: Receives the Observe sequence number.
returns: Payload length, -11 when empty, -90 for a short buffer, or another negative error.
End Rem
Function ThreadCoAPObserveRead:Int(data:Byte[], code:Int Var, sequence:UInt Var)
	If Not data Then
		Return -22
	End If

	Return _ObserveRead(data, data.length, code, sequence)
End Function

Rem
bbdoc: Count Observe notifications discarded by queue overflow.
returns: The number of dropped notifications.
End Rem
Function ThreadCoAPObserveDropped:UInt()
	Return _ObserveDropped()
End Function

Rem
bbdoc: Cancel the client Observe subscription.
returns: Zero on success or a negative error.
End Rem
Function ThreadCoAPObserveCancel:Int()
	Return _ObserveCancel()
End Function

?
