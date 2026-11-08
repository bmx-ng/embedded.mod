' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable Thread mesh networking and bounded UDP/IPv6 traffic.
about: Import the target's Network.Thread module to enable its radio stack.
All calls return zero on success or a negative error code unless documented
otherwise. ThreadJoin uses an active operational dataset; optional imports add
commissioning and service discovery.
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
Private

Extern "C"
	Function _ThreadInitialize:Int() = "bmx_thread_initialize"
	Function _ThreadStartSaved:Int() = "bmx_thread_start_saved"
	Function _ThreadForm:Int(name:Byte Ptr, channel:Int) = "bmx_thread_form"
	Function _ThreadJoin:Int(dataset:Byte Ptr) = "bmx_thread_join"
	Function _ThreadLeave:Int() = "bmx_thread_leave"
	Function _ThreadForget:Int() = "bmx_thread_forget"
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

?
