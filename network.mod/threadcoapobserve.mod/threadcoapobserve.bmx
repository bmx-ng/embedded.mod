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

Const ThreadCoAPObserveMaxPayload:Int = 1024
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

' Register an observable path after ThreadCoAPStart().
Function ThreadCoAPObserveResource:Int(path:String)
	If Not path Then Return -22
	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _ObserveResource(bytes)
	MemFree(bytes)
	Return result
End Function

Function ThreadCoAPObserveHasSubscriber:Int()
	Return _ObserveHasSubscriber()
End Function

' Send the initial value or a later notification to the current subscriber.
Function ThreadCoAPObservePublish:Int(data:Byte[], code:Int = ThreadCoAPContent)
	Local length:Int
	If data Then length = data.length
	Return _ObservePublish(code, data, length)
End Function

' Subscribe to one path. Notifications are returned by ThreadCoAPObserveRead.
Function ThreadCoAPObserveSubscribe:Int(address:String, path:String, port:Int = 5683)
	If Not address Or Not path Then Return -22
	Local a:Byte Ptr = address.ToUTF8String()
	Local p:Byte Ptr = path.ToUTF8String()
	Local result:Int = _ObserveSubscribe(a, port, p)
	MemFree(a)
	MemFree(p)
	Return result
End Function

' Returns a payload length, -11 if the queue is empty, or a negative error.
Function ThreadCoAPObserveRead:Int(data:Byte[], code:Int Var, sequence:UInt Var)
	If Not data Then Return -22
	Return _ObserveRead(data, data.length, code, sequence)
End Function

Function ThreadCoAPObserveDropped:UInt()
	Return _ObserveDropped()
End Function

Function ThreadCoAPObserveCancel:Int()
	Return _ObserveCancel()
End Function

?
