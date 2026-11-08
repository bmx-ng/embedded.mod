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

Const ThreadTCPMaxSend:Int = 1024
Const ThreadTCPIdle:Int = 0
Const ThreadTCPConnecting:Int = 1
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

Function ThreadTCPOpen:Int()
	Return _TCPOpen()
End Function

Function ThreadTCPConnect:Int(address:String, port:Int)
	If Not address Then Return -22
	Local bytes:Byte Ptr = address.ToUTF8String()
	Local result:Int = _TCPConnect(bytes, port)
	MemFree(bytes)
	Return result
End Function

Function ThreadTCPListen:Int(port:Int)
	Return _TCPListen(port)
End Function

' 0 idle, 1 connecting or listening, 2 connected, negative after disconnect.
Function ThreadTCPState:Int()
	Return _TCPState()
End Function

' Returns bytes queued, -16 while a prior send awaits acknowledgement, or an error.
Function ThreadTCPSend:Int(data:Byte[], length:Int = -1)
	If Not data Then Return -22
	If length < 0 Then length = data.length
	If length > data.length Then Return -22
	Return _TCPSend(data, length)
End Function

Function ThreadTCPSendReady:Int()
	Return _TCPSendReady()
End Function

' Returns bytes received, -11 when empty, or 0 at end of stream.
Function ThreadTCPReceive:Int(data:Byte[])
	If Not data Then Return -22
	Return _TCPReceive(data, data.length)
End Function

Function ThreadTCPEndSend:Int()
	Return _TCPEndSend()
End Function

Function ThreadTCPClose:Int()
	Return _TCPClose()
End Function

?
