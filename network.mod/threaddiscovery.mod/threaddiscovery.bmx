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
	Function _ThreadServicePublishEx:Int(host:Byte Ptr, instanceName:Byte Ptr, serviceType:Byte Ptr, port:Int, txt:Byte Ptr, txtLength:Int) = "bmx_thread_service_publish_ex"
	Function _ThreadServiceState:Int(handle:Int) = "bmx_thread_service_state"
	Function _ThreadServiceRemove:Int(handle:Int) = "bmx_thread_service_remove"
	Function _ThreadServiceRelease:Int(handle:Int) = "bmx_thread_service_release"
	Function _ThreadServiceResolvedTXT:Int(txt:Byte Ptr, capacity:Int, truncated:Int Var) = "bmx_thread_service_resolved_txt"
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

' Encode up to 256 bytes of DNS-SD TXT strings. Entries are "key=value" or "key".
Function ThreadTXTEncode:Byte[](entries:String[])
	If Not entries Then Return New Byte[0]
	Local total:Int
	For Local entry:String = EachIn entries
		If Not entry Or Not entry.length Then Return Null
		Local bytes:Byte Ptr = entry.ToUTF8String()
		Local length:Int
		While bytes[length] <> 0
			length :+ 1
		Wend
		MemFree(bytes)
		If length < 1 Or length > 255 Then Return Null
		total :+ length + 1
		If total > 256 Then Return Null
	Next
	Local encoded:Byte[] = New Byte[total]
	Local offset:Int
	For Local entry:String = EachIn entries
		Local bytes:Byte Ptr = entry.ToUTF8String()
		Local length:Int
		While bytes[length] <> 0
			length :+ 1
		Wend
		encoded[offset] = Byte(length)
		offset :+ 1
		For Local i:Int = 0 Until length
			encoded[offset + i] = bytes[i]
		Next
		offset :+ length
		MemFree(bytes)
	Next
	Return encoded
End Function

Function ThreadTXTDecode:String[](encoded:Byte[])
	If Not encoded Then Return Null
	Local offset:Int, count:Int
	While offset < encoded.length
		Local length:Int = encoded[offset] & $ff
		offset :+ 1
		If length > encoded.length - offset Then Return Null
		offset :+ length
		count :+ 1
	Wend
	Local entries:String[] = New String[count]
	offset = 0
	For Local index:Int = 0 Until count
		Local length:Int = encoded[offset] & $ff
		offset :+ 1
		Local bytes:Byte[] = New Byte[length]
		For Local i:Int = 0 Until length
			bytes[i] = encoded[offset + i]
		Next
		entries[index] = String.FromUTF8Bytes(bytes, length)
		offset :+ length
	Next
	Return entries
End Function

' Up to four services can be published from one process. They share one SRP host label.
Type TThreadPublishedService
	Private
	Field handle:Int

	Public
	Function Publish:TThreadPublishedService(host:String, instanceName:String, serviceType:String, port:Int, txtEntries:String[] = Null)
		If Not host Or Not instanceName Or Not serviceType Or port < 1 Or port > 65535 Then Return Null
		Local txt:Byte[] = ThreadTXTEncode(txtEntries)
		If Not txt Then Return Null
		Local h:Byte Ptr = host.ToUTF8String()
		Local n:Byte Ptr = instanceName.ToUTF8String()
		Local t:Byte Ptr = serviceType.ToUTF8String()
		Local id:Int = _ThreadServicePublishEx(h, n, t, port, txt, txt.length)
		MemFree(h)
		MemFree(n)
		MemFree(t)
		If id <= 0 Then Return Null
		Local service:TThreadPublishedService = New TThreadPublishedService
		service.handle = id
		Return service
	End Function

	' 1 while pending, 0 when registered, 2 when removed, negative on error.
	Method State:Int()
		If Not handle Then Return -107
		Return _ThreadServiceState(handle)
	End Method

	Method Unpublish:Int()
		If Not handle Then Return -107
		Return _ThreadServiceRemove(handle)
	End Method

	Method Close:Int()
		If Not handle Then Return 0
		Local result:Int = _ThreadServiceRelease(handle)
		If result = 0 Then handle = 0
		Return result
	End Method

	Method Delete()
		Close()
	End Method
End Type

' Available after ThreadServiceResolveState returns zero.
Function ThreadServiceResolvedTXT:Byte[]()
	Local data:Byte[256]
	Local truncated:Int
	Local length:Int = _ThreadServiceResolvedTXT(data, data.length, truncated)
	If length < 0 Then Return Null
	Local result:Byte[] = New Byte[length]
	For Local i:Int = 0 Until length
		result[i] = data[i]
	Next
	Return result
End Function

Function ThreadServiceResolvedTXTTruncated:Int()
	Local data:Byte[256]
	Local truncated:Int
	If _ThreadServiceResolvedTXT(data, data.length, truncated) < 0 Then Return False
	Return truncated
End Function

Private
Global _threadBrowserActive:Int
Public

' A polling browser that refreshes the one-shot DNS query at a chosen interval.
' Poll returns 2 when the set of instance labels changes, 1 while querying,
' zero when unchanged, or a negative error. Only one browser may be active.
Type TThreadServiceBrowser
	Private
	Field serviceType:String
	Field interval:UInt
	Field lastQuery:UInt
	Field pending:Int
	Field hasSnapshot:Int
	Field labels:String[]

	Public
	Function Start:TThreadServiceBrowser(serviceType:String, intervalMs:UInt = 5000)
		If _threadBrowserActive Or Not serviceType Then Return Null
		Local browser:TThreadServiceBrowser = New TThreadServiceBrowser
		browser.serviceType = serviceType
		browser.labels = New String[0]
		browser.interval = intervalMs
		If browser.interval < 1000 Then browser.interval = 1000
		If browser.Refresh() <> 0 Then Return Null
		_threadBrowserActive = True
		Return browser
	End Function

	Method Refresh:Int()
		If pending Then Return -16
		Local result:Int = ThreadServiceBrowse(serviceType)
		If result = 0 Then
			pending = True
			lastQuery = MilliSecs()
		End If
		Return result
	End Method

	Method Poll:Int()
		If pending Then
			Local state:Int = ThreadServiceBrowseState()
			If state = 1 Then Return 1
			pending = False
			If state < 0 Then Return state
			Local count:Int
			While count < 8 And ThreadServiceBrowseResult(count) <> ""
				count :+ 1
			Wend
			Local nextLabels:String[] = New String[count]
			For Local i:Int = 0 Until count
				nextLabels[i] = ThreadServiceBrowseResult(i)
			Next
			Local changed:Int = Not hasSnapshot Or count <> labels.length
			If Not changed Then
				For Local i:Int = 0 Until count
					Local found:Int
					For Local j:Int = 0 Until count
						If nextLabels[i] = labels[j] Then found = True
					Next
					If Not found Then changed = True
				Next
			End If
			labels = nextLabels
			hasSnapshot = True
			If changed Then Return 2
		End If
		If MilliSecs() - lastQuery >= interval Then
			Local result:Int = Refresh()
			If result <> 0 Then Return result
			Return 1
		End If
		Return 0
	End Method

	Method Results:String[]()
		If Not hasSnapshot Then Return New String[0]
		Local result:String[] = New String[labels.length]
		For Local i:Int = 0 Until labels.length
			result[i] = labels[i]
		Next
		Return result
	End Method

	Method Delete()
		_threadBrowserActive = False
	End Method
End Type
?
