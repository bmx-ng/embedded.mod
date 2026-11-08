' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional bounded TCP stream over a Thread mesh.
about: Importing this module includes OpenThread TCP support in the firmware.
One stream endpoint is supported per node, either outgoing or accepted by a
single listener. A send of up to 1024 bytes remains queued until acknowledged.
End Rem
Module Embedded.Network.ThreadTCP
?nrf52 or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System
Import Embedded.Network.Thread

Rem
bbdoc: Maximum bytes accepted by one TCP send.
End Rem
Const ThreadTCPMaxSend:Int = 1024
Rem
bbdoc: The TCP endpoint is idle.
End Rem
Const ThreadTCPIdle:Int = 0
Rem
bbdoc: The TCP endpoint is connecting or listening.
End Rem
Const ThreadTCPConnecting:Int = 1
Rem
bbdoc: The TCP endpoint is connected.
End Rem
Const ThreadTCPConnected:Int = 2

Private
Extern "C"
	Function _TCPOpen:Int() = "bmx_thread_tcp_open"
	Function _TCPConnect:Int(address:Byte Ptr, port:Int) = "bmx_thread_tcp_connect"
	Function _TCPListen:Int(port:Int) = "bmx_thread_tcp_listen"
	Function _TCPState:Int() = "bmx_thread_tcp_state"
	Function _TCPSend:Int(data:Byte Ptr, length:Int) = "bmx_thread_tcp_send"
	Function _TCPSendReady:Int() = "bmx_thread_tcp_send_ready"
	Function _TCPReceive:Int(data:Byte Ptr, capacity:Int) = "bmx_thread_tcp_receive"
	Function _TCPEndSend:Int() = "bmx_thread_tcp_end_send"
	Function _TCPClose:Int() = "bmx_thread_tcp_close"
End Extern

Public

Rem
bbdoc: Create the single Thread TCP endpoint.
returns: Zero on success or a negative error.
End Rem
Function ThreadTCPOpen:Int()
	Return _TCPOpen()
End Function

Rem
bbdoc: Connect the TCP endpoint to an IPv6 peer.
param: The peer IPv6 address; on receive, receives the sender address.
param: The UDP or TCP port.
returns: Zero if started or a negative error.
about: Poll ThreadTCPState for ThreadTCPConnected.
End Rem
Function ThreadTCPConnect:Int(address:String, port:Int)
	If Not address Then
		Return -22
	End If

	Local bytes:Byte Ptr = address.ToUTF8String()
	Local result:Int = _TCPConnect(bytes, port)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Listen for one incoming TCP connection.
param: The UDP or TCP port.
returns: Zero on success or a negative error.
End Rem
Function ThreadTCPListen:Int(port:Int)
	Return _TCPListen(port)
End Function

Rem
bbdoc: Get the TCP endpoint state.
returns: ThreadTCPIdle, ThreadTCPConnecting, ThreadTCPConnected, or a negative disconnection error.
End Rem
Function ThreadTCPState:Int()
	Return _TCPState()
End Function

Rem
bbdoc: Queue bytes on the TCP stream.
param: Payload bytes to send; Null sends an empty payload where allowed.
param: Number of bytes to send; -1 uses the whole array.
returns: Bytes queued, -16 while an earlier send awaits acknowledgement, or another negative error.
about: At most ThreadTCPMaxSend bytes may be queued in one send.
End Rem
Function ThreadTCPSend:Int(data:Byte[], length:Int = -1)
	If Not data Then
		Return -22
	End If

	If length < 0 Then
		length = data.length
	End If

	If length > data.length Then
		Return -22
	End If

	Return _TCPSend(data, length)
End Function

Rem
bbdoc: Check whether the previous TCP send has completed.
returns: True when ready to send again; otherwise False.
End Rem
Function ThreadTCPSendReady:Int()
	Return _TCPSendReady()
End Function

Rem
bbdoc: Read bytes from the TCP stream.
param: Buffer for the received payload.
returns: Bytes received, -11 if none are ready, zero at end of stream, or another negative error.
End Rem
Function ThreadTCPReceive:Int(data:Byte[])
	If Not data Then
		Return -22
	End If

	Return _TCPReceive(data, data.length)
End Function

Rem
bbdoc: Send an orderly TCP end of stream.
returns: Zero on success or a negative error.
End Rem
Function ThreadTCPEndSend:Int()
	Return _TCPEndSend()
End Function

Rem
bbdoc: Close the TCP endpoint.
returns: Zero on success or a negative error.
End Rem
Function ThreadTCPClose:Int()
	Return _TCPClose()
End Function

?
