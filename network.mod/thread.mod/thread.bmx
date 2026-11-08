' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable Thread mesh networking and bounded UDP/IPv6 traffic.
about: Import the target's Network.Thread module to enable its radio stack.
See each API for its return values. ThreadJoin uses an active operational
dataset; optional imports add commissioning and service discovery.
End Rem
Module Embedded.Network.Thread
?nrf52 or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System

Rem
bbdoc: Thread is disabled.
End Rem
Const ThreadRoleDisabled:Int = 0
Rem
bbdoc: Thread is enabled but not attached.
End Rem
Const ThreadRoleDetached:Int = 1
Rem
bbdoc: The node is attached as a child.
End Rem
Const ThreadRoleChild:Int = 2
Rem
bbdoc: The node is attached as a router.
End Rem
Const ThreadRoleRouter:Int = 3
Rem
bbdoc: The node is the mesh leader.
End Rem
Const ThreadRoleLeader:Int = 4
Rem
bbdoc: Use OpenThread’s internal mesh UDP interface.
End Rem
Const ThreadUDPNetifThread:Int = 0
Rem
bbdoc: Allow the platform UDP interface as well as the mesh where supported.
End Rem
Const ThreadUDPNetifAny:Int = 1
Rem
bbdoc: Maximum UDP payload accepted by this API, in bytes.
End Rem
Const ThreadUDPMaxDatagram:Int = 1280
Rem
bbdoc: Maximum configured UDP receive queue depth.
End Rem
Const ThreadUDPMaxQueueDepth:Int = 16
Rem
bbdoc: Maximum number of additional UDP socket objects.
End Rem
Const ThreadUDPMaxSockets:Int = 8
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
	Function _ThreadUDPSocketOpen:Int(port:Int, netif:Int) = "bmx_thread_udp_socket_open"
	Function _ThreadUDPSocketOpenEx:Int(port:Int, netif:Int, queueDepth:Int, maxDatagram:Int) = "bmx_thread_udp_socket_open_ex"
	Function _ThreadUDPSocketClose:Int(handle:Int) = "bmx_thread_udp_socket_close"
	Function _ThreadUDPSocketLocalPort:Int(handle:Int) = "bmx_thread_udp_socket_local_port"
	Function _ThreadUDPSocketConnect:Int(handle:Int, address:Byte Ptr, port:Int) = "bmx_thread_udp_socket_connect"
	Function _ThreadUDPSocketDisconnect:Int(handle:Int) = "bmx_thread_udp_socket_disconnect"
	Function _ThreadUDPSocketSendConnected:Int(handle:Int, data:Byte Ptr, length:Int) = "bmx_thread_udp_socket_send_connected"
	Function _ThreadUDPSocketSend:Int(handle:Int, address:Byte Ptr, port:Int, data:Byte Ptr, length:Int) = "bmx_thread_udp_socket_send"
	Function _ThreadUDPSocketReceive:Int(handle:Int, data:Byte Ptr, capacity:Int, address:Byte Ptr, ..
		addressCapacity:Int, port:Int Var) = "bmx_thread_udp_socket_receive"
	Function _ThreadUDPSocketDropped:UInt(handle:Int) = "bmx_thread_udp_socket_dropped"
End Extern

Public

Rem
bbdoc: Initialize the platform Thread stack.
returns: Zero on success or a negative error.
about: Normally called by ThreadStartSaved, ThreadForm, or ThreadJoin.
End Rem
Function ThreadInitialize:Int()
	Return _ThreadInitialize()
End Function

Rem
bbdoc: No stored active operational dataset is available.
End Rem
Const ThreadErrorNoSavedNetwork:Int = -61

Rem
bbdoc: Start Thread using the stored active dataset.
returns: Zero on success, ThreadErrorNoSavedNetwork if none is stored, or another negative error.
about: Use this on boot; form or commission a network only when no saved dataset exists.
End Rem
Function ThreadStartSaved:Int()
	Return _ThreadStartSaved()
End Function

Rem
bbdoc: Create a new Thread network and start it.
param: The network name.
param: The IEEE 802.15.4 channel.
returns: Zero on success or a negative error.
about: Replaces the stored active dataset. The name is 1–16 characters and the channel is 11–26.
End Rem
Function ThreadForm:Int(name:String, channel:Int = 15)
	If Not name Or name.length = 0 Or name.length > 16 Or channel < 11 Or channel > 26 Then
		Return -22
	End If

	Local bytes:Byte Ptr = name.ToUTF8String()
	Local result:Int = _ThreadForm(bytes, channel)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Install an existing active dataset and start Thread.
param: The active operational dataset as hexadecimal text.
returns: Zero on success or a negative error.
about: The dataset is hexadecimal text containing the network key; protect it as a secret. This is manual provisioning, not Joiner commissioning.
End Rem
Function ThreadJoin:Int(activeDatasetHex:String)
	If Not activeDatasetHex Or activeDatasetHex.length = 0 Then
		Return -22
	End If

	Local bytes:Byte Ptr = activeDatasetHex.ToUTF8String()
	Local result:Int = _ThreadJoin(bytes)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Stop the Thread interface.
returns: Zero on success or a negative error.
about: The stored dataset remains available for ThreadStartSaved.
End Rem
Function ThreadLeave:Int()
	Return _ThreadLeave()
End Function

Rem
bbdoc: Erase the stored Thread network.
returns: Zero on success or a negative error.
about: Use only during an explicit reprovisioning flow.
End Rem
Function ThreadForget:Int()
	Return _ThreadForget()
End Function

Rem
bbdoc: Get the current Thread device role.
returns: A ThreadRole* constant or a negative error.
End Rem
Function ThreadRole:Int()
	Return _ThreadRole()
End Function

Rem
bbdoc: Wait until the node attaches to a Thread mesh.
param: Maximum wait time in milliseconds.
returns: A role from ThreadRoleChild through ThreadRoleLeader, a negative error, or -110 on timeout.
End Rem
Function ThreadWaitForAttached:Int(timeout:UInt = 30000)
	Local started:UInt = MilliSecs()
	While MilliSecs() - started < timeout
		Local role:Int = ThreadRole()
		If role >= ThreadRoleChild Then
			Return role
		End If

		If role < 0 Then
			Return role
		End If

		Delay 20
	Wend

	Return -110
End Function

Rem
bbdoc: Read a local Thread IPv6 address by index.
param: Zero-based result index.
returns: An IPv6 address, or an empty string after the last address.
End Rem
Function ThreadIPv6Address:String(index:Int)
	If index < 0 Then
		Return ""
	End If

	Local bytes:Byte[48]
	Local length:Int = _ThreadAddress(index, bytes, bytes.length)
	If length <= 0 Then
		Return ""
	End If

	Return String.FromUTF8Bytes(bytes, length)
End Function

Rem
bbdoc: Read the active operational dataset as hexadecimal text.
returns: The dataset, or an empty string if unavailable.
about: The dataset contains the network key; do not log it in production.
End Rem
Function ThreadActiveDataset:String()
	Local bytes:Byte[509]
	Local length:Int = _ThreadDataset(bytes, bytes.length)
	If length <= 0 Then
		Return ""
	End If

	Return String.FromUTF8Bytes(bytes, length)
End Function

Rem
bbdoc: Bind the simple Thread UDP receive endpoint.
param: The UDP or TCP port.
returns: Zero on success or a negative error.
about: Only one simple endpoint can be open per process. Use TThreadUDPSocket for more endpoints.
End Rem
Function ThreadUDPOpen:Int(port:Int)
	Return _ThreadUDPOpen(port)
End Function

Rem
bbdoc: Close the simple Thread UDP endpoint.
returns: Zero on success or a negative error.
End Rem
Function ThreadUDPClose:Int()
	Return _ThreadUDPClose()
End Function

Rem
bbdoc: Send a UDP datagram to a Thread IPv6 address.
param: The peer IPv6 address; on receive, receives the sender address.
param: The UDP or TCP port.
param: Payload bytes to send; Null sends an empty payload where allowed.
param: Number of bytes to send; -1 uses the whole array.
returns: Bytes queued for delivery or a negative error.
about: Payloads are limited to ThreadUDPMaxDatagram bytes.
End Rem
Function ThreadUDPSend:Int(address:String, port:Int, data:Byte[], length:Int = -1)
	If Not address Or Not data Or port < 1 Or port > 65535 Then
		Return -22
	End If

	If length < 0 Then
		length = data.length
	End If

	If length > data.length Or length > ThreadUDPMaxDatagram Then
		Return -22
	End If

	Local addressBytes:Byte Ptr = address.ToUTF8String()
	Local result:Int = _ThreadUDPSend(addressBytes, port, data, length)
	MemFree(addressBytes)
	Return result
End Function

Rem
bbdoc: Read the next datagram from the simple endpoint.
param: Buffer for the received payload.
param: Receives the sender or resolved IPv6 address.
param: Receives the sender or resolved UDP port.
returns: Payload length, -11 when empty, -90 if the buffer is too small, or another negative error.
about: A datagram remains queued after -90.
End Rem
Function ThreadUDPReceive:Int(data:Byte[], address:String Var, port:Int Var)
	If Not data Then
		Return -22
	End If

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

Rem
bbdoc: Count datagrams discarded by the simple endpoint.
returns: The number of datagrams dropped by queue overflow, size, or allocation failure.
End Rem
Function ThreadUDPDropped:UInt()
	Return _ThreadUDPDropped()
End Function

Rem
bbdoc: An independently bound Thread UDP endpoint.
about: Up to ThreadUDPMaxSockets may be open. Closing or deleting one releases its port.
End Rem
Type TThreadUDPSocket
	Private
	Field handle:Int

	Public
	Rem
	bbdoc: Open a UDP socket with a bounded receive queue.
	param: The UDP or TCP port.
	param: The network interface selection constant.
	param: Maximum queued datagrams, from 1 to 16.
	param: Maximum accepted datagram size, from 1 to 1280 bytes.
	returns: A socket object, or Null if binding fails.
	about: Port 0 selects an available local port. ThreadUDPNetifAny also accepts platform traffic where supported.
	End Rem
	Function Open:TThreadUDPSocket(port:Int, netif:Int = ThreadUDPNetifThread, queueDepth:Int = 8, maxDatagram:Int = ThreadUDPMaxDatagram)
		Local id:Int = _ThreadUDPSocketOpenEx(port, netif, queueDepth, maxDatagram)
		If id <= 0 Then
			Return Null
		End If

		Local socket:TThreadUDPSocket = New TThreadUDPSocket
		socket.handle = id
		Return socket
	End Function

	Rem
	bbdoc: Check whether this UDP socket is open.
	returns: True if open; otherwise False.
	End Rem
	Method IsOpen:Int()
		Return handle > 0
	End Method

	Rem
	bbdoc: Get this socket’s bound UDP port.
	returns: The port number or a negative error.
	End Rem
	Method LocalPort:Int()
		If Not handle Then
			Return -107
		End If

		Return _ThreadUDPSocketLocalPort(handle)
	End Method

	Rem
	bbdoc: Set the default UDP peer and filter incoming datagrams to it.
	param: The peer IPv6 address; on receive, receives the sender address.
	param: The UDP or TCP port.
	returns: Zero on success or a negative error.
	End Rem
	Method Connect:Int(address:String, port:Int)
		If Not handle Then
			Return -107
		End If

		If Not address Or port < 1 Or port > 65535 Then
			Return -22
		End If

		Local bytes:Byte Ptr = address.ToUTF8String()
		Local result:Int = _ThreadUDPSocketConnect(handle, bytes, port)
		MemFree(bytes)
		Return result
	End Method

	Rem
	bbdoc: Clear this UDP socket’s default peer.
	returns: Zero on success or a negative error.
	End Rem
	Method Disconnect:Int()
		If Not handle Then
			Return -107
		End If

		Return _ThreadUDPSocketDisconnect(handle)
	End Method

	Rem
	bbdoc: Send a UDP datagram to the configured peer.
	param: Payload bytes to send; Null sends an empty payload where allowed.
	param: Number of bytes to send; -1 uses the whole array.
	returns: Bytes queued or a negative error.
	End Rem
	Method SendConnected:Int(data:Byte[], length:Int = -1)
		If Not handle Then
			Return -107
		End If

		If Not data Then
			Return -22
		End If

		If length < 0 Then
			length = data.length
		End If

		If length > data.length Or length > ThreadUDPMaxDatagram Then
			Return -22
		End If

		Return _ThreadUDPSocketSendConnected(handle, data, length)
	End Method

	Rem
	bbdoc: Close this socket and release its local port.
	returns: Zero on success or a negative error.
	End Rem
	Method Close:Int()
		If Not handle Then
			Return 0
		End If

		Local result:Int = _ThreadUDPSocketClose(handle)
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

	Rem
	bbdoc: Send a UDP datagram to a specified peer.
	param: The peer IPv6 address; on receive, receives the sender address.
	param: The UDP or TCP port.
	param: Payload bytes to send; Null sends an empty payload where allowed.
	param: Number of bytes to send; -1 uses the whole array.
	returns: Bytes queued or a negative error.
	End Rem
	Method Send:Int(address:String, port:Int, data:Byte[], length:Int = -1)
		If Not handle Then
			Return -107
		End If

		If Not address Or Not data Or port < 1 Or port > 65535 Then
			Return -22
		End If

		If length < 0 Then
			length = data.length
		End If

		If length > data.length Or length > ThreadUDPMaxDatagram Then
			Return -22
		End If

		Local addressBytes:Byte Ptr = address.ToUTF8String()
		Local result:Int = _ThreadUDPSocketSend(handle, addressBytes, port, data, length)
		MemFree(addressBytes)
		Return result
	End Method

	Rem
	bbdoc: Read the next UDP datagram from this socket.
	param: Buffer for the received payload.
	param: Receives the sender or resolved IPv6 address.
	param: Receives the sender or resolved UDP port.
	returns: Payload length, -11 when empty, -90 if the buffer is too small, or another negative error.
	about: A datagram remains queued after -90.
	End Rem
	Method Receive:Int(data:Byte[], address:String Var, port:Int Var)
		If Not handle Then
			Return -107
		End If

		If Not data Then
			Return -22
		End If

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

	Rem
	bbdoc: Count datagrams discarded by this socket.
	returns: The number of dropped datagrams.
	End Rem
	Method Dropped:UInt()
		If Not handle Then
			Return 0
		End If

		Return _ThreadUDPSocketDropped(handle)
	End Method
End Type

?
