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
	Function _ThreadServiceBrowseCount:Int() = "bmx_thread_service_browse_count"
	Function _ThreadServiceBrowseTruncated:Int() = "bmx_thread_service_browse_truncated"
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

Rem
bbdoc: Enable SRP registration and DNS-SD discovery.
returns: Zero on success or a negative error.
about: Finds an on-mesh server advertised in Thread network data.
End Rem
Function ThreadServiceClientEnable:Int()
	Return _ThreadServiceClientEnable()
End Function

Rem
bbdoc: Check whether the service client is ready.
returns: True when running; otherwise False.
End Rem
Function ThreadServiceClientRunning:Int()
	Return _ThreadServiceClientRunning()
End Function

Rem
bbdoc: Publish one named service through SRP.
param: SRP host label.
param: Service instance label.
param: DNS-SD service type, such as _bmxecho._udp.
param: The UDP or TCP port.
returns: Zero when registration starts or a negative error.
about: Poll ThreadServicePublishState. For multiple services or TXT records, use TThreadPublishedService.
End Rem
Function ThreadServicePublish:Int(host:String, instanceName:String, serviceType:String, port:Int)
	If Not host Or Not instanceName Or Not serviceType Then
		Return -22
	End If

	Local h:Byte Ptr = host.ToUTF8String()
	Local n:Byte Ptr = instanceName.ToUTF8String()
	Local t:Byte Ptr = serviceType.ToUTF8String()
	Local result:Int = _ThreadServicePublish(h, n, t, port)
	MemFree(h)
	MemFree(n)
	MemFree(t)
	Return result
End Function

Rem
bbdoc: Get the single published service state.
returns: One while pending, zero when registered, or a negative error.
End Rem
Function ThreadServicePublishState:Int()
	Return _ThreadServicePublishState()
End Function

Rem
bbdoc: Remove the single published service.
returns: Zero on success or a negative error.
End Rem
Function ThreadServiceUnpublish:Int()
	Return _ThreadServiceUnpublish()
End Function

Rem
bbdoc: Start a DNS-SD browse for one service type.
param: DNS-SD service type, such as _bmxecho._udp.
returns: Zero if started or a negative error.
about: Poll ThreadServiceBrowseState before reading results.
End Rem
Function ThreadServiceBrowse:Int(serviceType:String)
	If Not serviceType Then
		Return -22
	End If

	Local t:Byte Ptr = serviceType.ToUTF8String()
	Local result:Int = _ThreadServiceBrowse(t)
	MemFree(t)
	Return result
End Function

Rem
bbdoc: Get the one-shot browse state.
returns: One while pending, zero when complete, or a negative error.
End Rem
Function ThreadServiceBrowseState:Int()
	Return _ThreadServiceBrowseState()
End Function

Rem
bbdoc: Count labels in the last completed browse.
returns: A count up to 32 or a negative error.
End Rem
Function ThreadServiceBrowseCount:Int()
	Return _ThreadServiceBrowseCount()
End Function

Rem
bbdoc: Check whether the last browse exceeded 32 labels.
returns: True if results were truncated; otherwise False.
End Rem
Function ThreadServiceBrowseTruncated:Int()
	Return _ThreadServiceBrowseTruncated()
End Function

Rem
bbdoc: Read a label from the last completed browse.
param: Zero-based result index.
returns: The instance label or an empty string for an invalid index.
End Rem
Function ThreadServiceBrowseResult:String(index:Int)
	If index < 0 Then
		Return ""
	End If

	Local label:Byte[64]
	Local length:Int = _ThreadServiceBrowseResult(index, label, label.length)
	If length <= 0 Then
		Return ""
	End If

	Return String.FromUTF8Bytes(label, length)
End Function

Rem
bbdoc: Start resolving a service instance.
param: Service instance label.
param: DNS-SD service type, such as _bmxecho._udp.
returns: Zero if started or a negative error.
about: Poll ThreadServiceResolveState to obtain its IPv6 address and port.
End Rem
Function ThreadServiceResolve:Int(instanceName:String, serviceType:String)
	If Not instanceName Or Not serviceType Then
		Return -22
	End If

	Local n:Byte Ptr = instanceName.ToUTF8String()
	Local t:Byte Ptr = serviceType.ToUTF8String()
	Local result:Int = _ThreadServiceResolve(n, t)
	MemFree(n)
	MemFree(t)
	Return result
End Function

Rem
bbdoc: Get the current resolution result.
param: Receives the sender or resolved IPv6 address.
param: Receives the sender or resolved UDP port.
returns: One while pending, zero with address and port, or a negative error.
End Rem
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

Rem
bbdoc: Encode DNS-SD TXT entries as wire bytes.
param: TXT entries as key=value strings or boolean keys.
returns: Encoded bytes, an empty array for no entries, or Null for invalid input.
about: Each entry is key=value or a boolean key. The total is limited to 1024 bytes.
End Rem
Function ThreadTXTEncode:Byte[](entries:String[])
	If Not entries Then
		Return New Byte[0]
	End If

	Local total:Int
	For Local entry:String = EachIn entries
		If Not entry Or Not entry.length Then
			Return Null
		End If

		Local bytes:Byte Ptr = entry.ToUTF8String()
		Local length:Int
		While bytes[length] <> 0
			length :+ 1
		Wend

		MemFree(bytes)
		If length < 1 Or length > 255 Then
			Return Null
		End If

		total :+ length + 1
		If total > 1024 Then
			Return Null
		End If
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

Rem
bbdoc: Decode DNS-SD TXT wire bytes into strings.
param: DNS-SD TXT wire bytes.
returns: An array of entries or Null if malformed.
End Rem
Function ThreadTXTDecode:String[](encoded:Byte[])
	If Not encoded Then
		Return Null
	End If

	Local offset:Int, count:Int
	While offset < encoded.length
		Local length:Int = encoded[offset] & $ff
		offset :+ 1
		If length > encoded.length - offset Then
			Return Null
		End If

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

Rem
bbdoc: A separately managed SRP service registration.
about: Up to eight services share one SRP host label. Delete or Close to release a registration.
End Rem
Type TThreadPublishedService
	Private
	Field handle:Int

	Public
	Rem
	bbdoc: Create and publish a service with optional TXT entries.
	param: SRP host label.
	param: Service instance label.
	param: DNS-SD service type, such as _bmxecho._udp.
	param: The UDP or TCP port.
	param: Optional DNS-SD TXT entries.
	returns: A service object, or Null on invalid input or registration failure.
	End Rem
	Function Publish:TThreadPublishedService(host:String, instanceName:String, serviceType:String, port:Int, txtEntries:String[] = Null)
		If Not host Or Not instanceName Or Not serviceType Or port < 1 Or port > 65535 Then
			Return Null
		End If

		Local txt:Byte[] = ThreadTXTEncode(txtEntries)
		If Not txt Then
			Return Null
		End If

		Local h:Byte Ptr = host.ToUTF8String()
		Local n:Byte Ptr = instanceName.ToUTF8String()
		Local t:Byte Ptr = serviceType.ToUTF8String()
		Local id:Int = _ThreadServicePublishEx(h, n, t, port, txt, txt.length)
		MemFree(h)
		MemFree(n)
		MemFree(t)
		If id <= 0 Then
			Return Null
		End If

		Local service:TThreadPublishedService = New TThreadPublishedService
		service.handle = id
		Return service
	End Function

	Rem
	bbdoc: Get this service’s registration state.
	returns: One while pending, zero when registered, two when removed, or a negative error.
	End Rem
	Method State:Int()
		If Not handle Then
			Return -107
		End If

		Return _ThreadServiceState(handle)
	End Method

	Rem
	bbdoc: Request removal of this service.
	returns: Zero on success or a negative error.
	End Rem
	Method Unpublish:Int()
		If Not handle Then
			Return -107
		End If

		Return _ThreadServiceRemove(handle)
	End Method

	Rem
	bbdoc: Release this service registration.
	returns: Zero on success or a negative error.
	about: Unregisters the service asynchronously if it is still published.
	End Rem
	Method Close:Int()
		If Not handle Then
			Return 0
		End If

		Local result:Int = _ThreadServiceRelease(handle)
		If result = 0 Then
			handle = 0
		End If

		Return result
	End Method

	Rem
	bbdoc: Release native resources when the object is destroyed.
	End Rem
	Method Delete()
		Close()
	End Method
End Type

Rem
bbdoc: Read TXT bytes from the last successful resolution.
returns: TXT wire bytes, or Null if unavailable.
End Rem
Function ThreadServiceResolvedTXT:Byte[]()
	Local data:Byte[1024]
	Local truncated:Int
	Local length:Int = _ThreadServiceResolvedTXT(data, data.length, truncated)
	If length < 0 Then
		Return Null
	End If

	Local result:Byte[] = New Byte[length]
	For Local i:Int = 0 Until length
		result[i] = data[i]
	Next

	Return result
End Function

Rem
bbdoc: Check whether resolved TXT bytes exceeded 1024 bytes.
returns: True if truncated; otherwise False.
End Rem
Function ThreadServiceResolvedTXTTruncated:Int()
	Local data:Byte[1024]
	Local truncated:Int
	If _ThreadServiceResolvedTXT(data, data.length, truncated) < 0 Then
		Return False
	End If

	Return truncated
End Function

Private
Global _threadBrowserActive:Int
Public

Rem
bbdoc: A polling DNS-SD browser that refreshes its results.
about: Only one browser can be active per process. Results are snapshots, not push notifications.
End Rem
Type TThreadServiceBrowser
	Private
	Field serviceType:String
	Field interval:UInt
	Field lastQuery:UInt
	Field pending:Int
	Field hasSnapshot:Int
	Field labels:String[]

	Public
	Rem
	bbdoc: Start periodically browsing a service type.
	param: DNS-SD service type, such as _bmxecho._udp.
	param: Time between browse refreshes, in milliseconds.
	returns: A browser object, or Null if another browser is active or the query cannot start.
	about: The refresh interval is at least 1000 milliseconds.
	End Rem
	Function Start:TThreadServiceBrowser(serviceType:String, intervalMs:UInt = 5000)
		If _threadBrowserActive Or Not serviceType Then
			Return Null
		End If

		Local browser:TThreadServiceBrowser = New TThreadServiceBrowser
		browser.serviceType = serviceType
		browser.labels = New String[0]
		browser.interval = intervalMs
		If browser.interval < 1000 Then
			browser.interval = 1000
		End If

		If browser.Refresh() <> 0 Then
			Return Null
		End If

		_threadBrowserActive = True
		Return browser
	End Function

	Rem
	bbdoc: Start a new browse immediately.
	returns: Zero if started, -16 if already pending, or another negative error.
	End Rem
	Method Refresh:Int()
		If pending Then
			Return -16
		End If

		Local result:Int = ThreadServiceBrowse(serviceType)
		If result = 0 Then
			pending = True
			lastQuery = MilliSecs()
		End If

		Return result
	End Method

	Rem
	bbdoc: Advance the browse and check for changes.
	returns: Two when labels changed, one while pending, zero when unchanged, or a negative error.
	End Rem
	Method Poll:Int()
		If pending Then
			Local state:Int = ThreadServiceBrowseState()
			If state = 1 Then
				Return 1
			End If

			pending = False
			If state < 0 Then
				Return state
			End If

			Local count:Int = ThreadServiceBrowseCount()
			If count < 0 Then
				Return count
			End If

			Local nextLabels:String[] = New String[count]
			For Local i:Int = 0 Until count
				nextLabels[i] = ThreadServiceBrowseResult(i)
			Next

			Local changed:Int = Not hasSnapshot Or count <> labels.length
			If Not changed Then
				For Local i:Int = 0 Until count
					Local found:Int
					For Local j:Int = 0 Until count
						If nextLabels[i] = labels[j] Then
							found = True
						End If
					Next

					If Not found Then
						changed = True
					End If
				Next
			End If

			labels = nextLabels
			hasSnapshot = True
			If changed Then
				Return 2
			End If
		End If

		If MilliSecs() - lastQuery >= interval Then
			Local result:Int = Refresh()
			If result <> 0 Then
				Return result
			End If

			Return 1
		End If

		Return 0
	End Method

	Rem
	bbdoc: Copy the most recent service instance labels.
	returns: A snapshot array, empty before the first completed browse.
	End Rem
	Method Results:String[]()
		If Not hasSnapshot Then
			Return New String[0]
		End If

		Local result:String[] = New String[labels.length]
		For Local i:Int = 0 Until labels.length
			result[i] = labels[i]
		Next

		Return result
	End Method

	Rem
	bbdoc: Release the active browser slot when the object is destroyed.
	End Rem
	Method Delete()
		_threadBrowserActive = False
	End Method
End Type
?
