' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable Thread mesh networking and bounded UDP/IPv6 traffic.
about: Import the target's Network.Thread module to enable its radio stack.
All calls return zero on success or a negative error code unless documented
otherwise. ThreadJoin uses an active operational dataset; ThreadJoinerStart
performs on-mesh commissioning with a PSKd.
End Rem
Module Embedded.Network.Thread
?nrf52 or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System

Const ThreadRoleDisabled:Int = 0
Const ThreadRoleDetached:Int = 1
Const ThreadRoleChild:Int = 2
Const ThreadRoleRouter:Int = 3
Const ThreadRoleLeader:Int = 4
Const ThreadCommissionerDisabled:Int = 0
Const ThreadCommissionerPetition:Int = 1
Const ThreadCommissionerActive:Int = 2
Const ThreadJoinerIdle:Int = -61
Const ThreadJoinerPending:Int = 1

Private

Extern "C"
	Function _ThreadInitialize:Int() = "bmx_thread_initialize"
	Function _ThreadStartSaved:Int() = "bmx_thread_start_saved"
	Function _ThreadForm:Int(name:Byte Ptr, channel:Int) = "bmx_thread_form"
	Function _ThreadJoin:Int(dataset:Byte Ptr) = "bmx_thread_join"
	Function _ThreadLeave:Int() = "bmx_thread_leave"
	Function _ThreadForget:Int() = "bmx_thread_forget"
	Function _ThreadFactoryEui64:Int(value:Byte Ptr, capacity:Int) = "bmx_thread_factory_eui64"
	Function _ThreadCommissionerStart:Int() = "bmx_thread_commissioner_start"
	Function _ThreadCommissionerState:Int() = "bmx_thread_commissioner_state"
	Function _ThreadCommissionerAddJoiner:Int(eui64:Byte Ptr, pskd:Byte Ptr, timeout:UInt) = "bmx_thread_commissioner_add_joiner"
	Function _ThreadCommissionerStop:Int() = "bmx_thread_commissioner_stop"
	Function _ThreadJoinerStart:Int(pskd:Byte Ptr) = "bmx_thread_joiner_start"
	Function _ThreadJoinerStatus:Int() = "bmx_thread_joiner_status"
	Function _ThreadJoinerStop:Int() = "bmx_thread_joiner_stop"
	Function _ThreadRole:Int() = "bmx_thread_role"
	Function _ThreadAddress:Int(index:Int, value:Byte Ptr, capacity:Int) = "bmx_thread_address"
	Function _ThreadDataset:Int(value:Byte Ptr, capacity:Int) = "bmx_thread_dataset"
	Function _ThreadUDPOpen:Int(port:Int) = "bmx_thread_udp_open"
	Function _ThreadUDPClose:Int() = "bmx_thread_udp_close"
	Function _ThreadUDPSend:Int(address:Byte Ptr, port:Int, data:Byte Ptr, length:Int) = "bmx_thread_udp_send"
	Function _ThreadUDPReceive:Int(data:Byte Ptr, capacity:Int, address:Byte Ptr, ..
		addressCapacity:Int, port:Int Var) = "bmx_thread_udp_receive"
	Function _ThreadUDPDropped:UInt() = "bmx_thread_udp_dropped"
	Function _ThreadUDPSocketOpen:Int(port:Int) = "bmx_thread_udp_socket_open"
	Function _ThreadUDPSocketClose:Int(handle:Int) = "bmx_thread_udp_socket_close"
	Function _ThreadUDPSocketSend:Int(handle:Int, address:Byte Ptr, port:Int, data:Byte Ptr, length:Int) = "bmx_thread_udp_socket_send"
	Function _ThreadUDPSocketReceive:Int(handle:Int, data:Byte Ptr, capacity:Int, address:Byte Ptr, ..
		addressCapacity:Int, port:Int Var) = "bmx_thread_udp_socket_receive"
	Function _ThreadUDPSocketDropped:UInt(handle:Int) = "bmx_thread_udp_socket_dropped"
	Function _ThreadServiceServerEnable:Int(enabled:Int) = "bmx_thread_service_server_enable"
	Function _ThreadServiceServerState:Int() = "bmx_thread_service_server_state"
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

Function ThreadInitialize:Int()
	Return _ThreadInitialize()
End Function

Const ThreadErrorNoSavedNetwork:Int = -61

' Starts with the stored active dataset. Returns -61 if none has been saved.
Function ThreadStartSaved:Int()
	Return _ThreadStartSaved()
End Function

Function ThreadForm:Int(name:String, channel:Int = 15)
	If Not name Or name.length = 0 Or name.length > 16 Or channel < 11 Or channel > 26 Then Return -22
	Local bytes:Byte Ptr = name.ToUTF8String()
	Local result:Int = _ThreadForm(bytes, channel)
	MemFree(bytes)
	Return result
End Function

Function ThreadJoin:Int(activeDatasetHex:String)
	If Not activeDatasetHex Or activeDatasetHex.length = 0 Then Return -22
	Local bytes:Byte Ptr = activeDatasetHex.ToUTF8String()
	Local result:Int = _ThreadJoin(bytes)
	MemFree(bytes)
	Return result
End Function

Function ThreadLeave:Int()
	Return _ThreadLeave()
End Function

' Erases the stored network after leaving it; the next boot cannot resume it.
Function ThreadForget:Int()
	Return _ThreadForget()
End Function

' Factory EUI-64 used to authorize this device on a Commissioner.
Function ThreadFactoryEui64:String()
	Local bytes:Byte[17]
	If _ThreadFactoryEui64(bytes, bytes.length) <> 16 Then Return ""
	Return String.FromUTF8Bytes(bytes, 16)
End Function

Function ThreadCommissionerStart:Int()
	Return _ThreadCommissionerStart()
End Function

Function ThreadCommissionerState:Int()
	Return _ThreadCommissionerState()
End Function

' Supply the joiner's factory EUI-64 as 16 hex digits; an empty string permits any joiner.
Function ThreadCommissionerAddJoiner:Int(eui64:String, pskd:String, timeoutSecs:UInt = 120)
	If Not eui64 Or Not pskd Or timeoutSecs = 0 Then Return -22
	Local euiBytes:Byte Ptr = eui64.ToUTF8String()
	Local pskdBytes:Byte Ptr = pskd.ToUTF8String()
	Local result:Int = _ThreadCommissionerAddJoiner(euiBytes, pskdBytes, timeoutSecs)
	MemFree(euiBytes)
	MemFree(pskdBytes)
	Return result
End Function

Function ThreadCommissionerStop:Int()
	Return _ThreadCommissionerStop()
End Function

' Starts asynchronous commissioning. Call ThreadJoinerStatus until it returns 0 or an error.
Function ThreadJoinerStart:Int(pskd:String)
	If Not pskd Then Return -22
	Local bytes:Byte Ptr = pskd.ToUTF8String()
	Local result:Int = _ThreadJoinerStart(bytes)
	MemFree(bytes)
	Return result
End Function

' 1 while joining; 0 after the commissioned network has started; negative on error.
Function ThreadJoinerStatus:Int()
	Return _ThreadJoinerStatus()
End Function

Function ThreadJoinerStop:Int()
	Return _ThreadJoinerStop()
End Function

Function ThreadRole:Int()
	Return _ThreadRole()
End Function

Function ThreadWaitForAttached:Int(timeout:UInt = 30000)
	Local started:UInt = MilliSecs()
	While MilliSecs() - started < timeout
		Local role:Int = ThreadRole()
		If role >= ThreadRoleChild Then Return role
		If role < 0 Then Return role
		Delay 20
	Wend
	Return -110
End Function

Function ThreadIPv6Address:String(index:Int)
	If index < 0 Then Return ""
	Local bytes:Byte[48]
	Local length:Int = _ThreadAddress(index, bytes, bytes.length)
	If length <= 0 Then Return ""
	Return String.FromUTF8Bytes(bytes, length)
End Function

Function ThreadActiveDataset:String()
	Local bytes:Byte[509]
	Local length:Int = _ThreadDataset(bytes, bytes.length)
	If length <= 0 Then Return ""
	Return String.FromUTF8Bytes(bytes, length)
End Function

' One receive port per node. Payloads up to 512 bytes are queued in native storage.
Function ThreadUDPOpen:Int(port:Int)
	Return _ThreadUDPOpen(port)
End Function

Function ThreadUDPClose:Int()
	Return _ThreadUDPClose()
End Function

Function ThreadUDPSend:Int(address:String, port:Int, data:Byte[], length:Int = -1)
	If Not address Or Not data Or port < 1 Or port > 65535 Then Return -22
	If length < 0 Then length = data.length
	If length > data.length Or length > 512 Then Return -22
	Local addressBytes:Byte Ptr = address.ToUTF8String()
	Local result:Int = _ThreadUDPSend(addressBytes, port, data, length)
	MemFree(addressBytes)
	Return result
End Function

' Returns bytes received, -11 when the queue is empty, or another negative error.
Function ThreadUDPReceive:Int(data:Byte[], address:String Var, port:Int Var)
	If Not data Then Return -22
	Local addressBytes:Byte[48]
	Local result:Int = _ThreadUDPReceive(data, data.length, addressBytes, addressBytes.length, port)
	If result >= 0 Then
		Local length:Int
		While length < addressBytes.length And addressBytes[length] <> 0
			length :+ 1
		Wend
		address = String.FromUTF8Bytes(addressBytes, length)
	End If
	Return result
End Function

Function ThreadUDPDropped:UInt()
	Return _ThreadUDPDropped()
End Function

' Up to four additional independent UDP endpoints, each with its own receive queue.
Type TThreadUDPSocket
	Private
	Field handle:Int

	Public
	Function Open:TThreadUDPSocket(port:Int)
		Local id:Int = _ThreadUDPSocketOpen(port)
		If id <= 0 Then Return Null
		Local socket:TThreadUDPSocket = New TThreadUDPSocket
		socket.handle = id
		Return socket
	End Function

	Method IsOpen:Int()
		Return handle > 0
	End Method

	Method Close:Int()
		If Not handle Then Return 0
		Local result:Int = _ThreadUDPSocketClose(handle)
		If result = 0 Then handle = 0
		Return result
	End Method

	Method Delete()
		Close()
	End Method

	Method Send:Int(address:String, port:Int, data:Byte[], length:Int = -1)
		If Not handle Then Return -107
		If Not address Or Not data Or port < 1 Or port > 65535 Then Return -22
		If length < 0 Then length = data.length
		If length > data.length Or length > 512 Then Return -22
		Local addressBytes:Byte Ptr = address.ToUTF8String()
		Local result:Int = _ThreadUDPSocketSend(handle, addressBytes, port, data, length)
		MemFree(addressBytes)
		Return result
	End Method

	Method Receive:Int(data:Byte[], address:String Var, port:Int Var)
		If Not handle Then Return -107
		If Not data Then Return -22
		Local addressBytes:Byte[48]
		Local result:Int = _ThreadUDPSocketReceive(handle, data, data.length, addressBytes, addressBytes.length, port)
		If result >= 0 Then
			Local length:Int
			While length < addressBytes.length And addressBytes[length] <> 0
				length :+ 1
			Wend
			address = String.FromUTF8Bytes(addressBytes, length)
		End If
		Return result
	End Method

	Method Dropped:UInt()
		If Not handle Then Return 0
		Return _ThreadUDPSocketDropped(handle)
	End Method
End Type

' SRP server state: 0 disabled, 1 running, 2 stopped (OpenThread values).
Function ThreadServiceServerEnable:Int(enabled:Int = True)
	Return _ThreadServiceServerEnable(enabled)
End Function

Function ThreadServiceServerState:Int()
	Return _ThreadServiceServerState()
End Function

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
