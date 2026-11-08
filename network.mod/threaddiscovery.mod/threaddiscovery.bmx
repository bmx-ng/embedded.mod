' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: On-mesh Thread SRP registration and DNS-SD discovery.
End Rem
Module Embedded.Network.ThreadDiscovery
?nrf52 or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System
Import Embedded.Network.Thread


Private

Extern "C"
	Function _ThreadServiceClientEnable:Int() = "bmx_thread_service_client_enable"
	Function _ThreadServiceClientRunning:Int() = "bmx_thread_service_client_running"
	Function _ThreadServicePublish:Int(host:Byte Ptr, instanceName:Byte Ptr, serviceType:Byte Ptr, port:Int) = "bmx_thread_service_publish"
	Function _ThreadServicePublishState:Int() = "bmx_thread_service_publish_state"
	Function _ThreadServiceUnpublish:Int() = "bmx_thread_service_unpublish"
	Function _ThreadServiceBrowse:Int(serviceType:Byte Ptr) = "bmx_thread_service_browse"
	Function _ThreadServiceBrowseState:Int() = "bmx_thread_service_browse_state"
	Function _ThreadServiceBrowseResult:Int(index:Int, label:Byte Ptr, capacity:Int) = "bmx_thread_service_browse_result"
	Function _ThreadServiceResolve:Int(instanceName:Byte Ptr, serviceType:Byte Ptr) = "bmx_thread_service_resolve"
	Function _ThreadServiceResolveState:Int(address:Byte Ptr, capacity:Int, port:Int Var) = "bmx_thread_service_resolve_state"
End Extern

Public

' Discover an SRP server advertised in Thread network data. Also supplies the
' default DNS-SD server for browse and resolve calls.
Function ThreadServiceClientEnable:Int()
	Return _ThreadServiceClientEnable()
End Function

Function ThreadServiceClientRunning:Int()
	Return _ThreadServiceClientRunning()
End Function

' Publish one named UDP service. State is 1 while registration is pending,
' zero when registered, or a negative OpenThread error.
Function ThreadServicePublish:Int(host:String, instanceName:String, serviceType:String, port:Int)
	If Not host Or Not instanceName Or Not serviceType Then Return -22
	Local h:Byte Ptr = host.ToUTF8String()
	Local n:Byte Ptr = instanceName.ToUTF8String()
	Local t:Byte Ptr = serviceType.ToUTF8String()
	Local result:Int = _ThreadServicePublish(h, n, t, port)
	MemFree(h)
	MemFree(n)
	MemFree(t)
	Return result
End Function

Function ThreadServicePublishState:Int()
	Return _ThreadServicePublishState()
End Function

Function ThreadServiceUnpublish:Int()
	Return _ThreadServiceUnpublish()
End Function

' Browse one service type at a time; result labels are available after state 0.
Function ThreadServiceBrowse:Int(serviceType:String)
	If Not serviceType Then Return -22
	Local t:Byte Ptr = serviceType.ToUTF8String()
	Local result:Int = _ThreadServiceBrowse(t)
	MemFree(t)
	Return result
End Function

Function ThreadServiceBrowseState:Int()
	Return _ThreadServiceBrowseState()
End Function

Function ThreadServiceBrowseResult:String(index:Int)
	If index < 0 Then Return ""
	Local label:Byte[64]
	Local length:Int = _ThreadServiceBrowseResult(index, label, label.length)
	If length <= 0 Then Return ""
	Return String.FromUTF8Bytes(label, length)
End Function

Function ThreadServiceResolve:Int(instanceName:String, serviceType:String)
	If Not instanceName Or Not serviceType Then Return -22
	Local n:Byte Ptr = instanceName.ToUTF8String()
	Local t:Byte Ptr = serviceType.ToUTF8String()
	Local result:Int = _ThreadServiceResolve(n, t)
	MemFree(n)
	MemFree(t)
	Return result
End Function

' Returns 1 while resolving, 0 with IPv6 address and UDP port, or an error.
Function ThreadServiceResolveState:Int(address:String Var, port:Int Var)
	Local bytes:Byte[48]
	Local result:Int = _ThreadServiceResolveState(bytes, bytes.length, port)
	If result = 0 Then
		Local length:Int
		While length < bytes.length And bytes[length] <> 0
			length :+ 1
		Wend
		address = String.FromUTF8Bytes(bytes, length)
	End If
	Return result
End Function
?
