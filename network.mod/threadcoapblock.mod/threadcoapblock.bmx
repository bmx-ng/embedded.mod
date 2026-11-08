' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional bounded CoAP blockwise transfers over Thread.
about: Import this module to enable OpenThread Block1 and Block2 handling in
the firmware. One blockwise resource and one client exchange are supported.
End Rem
Module Embedded.Network.ThreadCoAPBlock
?nrf52 or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System
Import Embedded.Network.ThreadCoAP

Rem
bbdoc: Maximum assembled blockwise payload in bytes.
End Rem
Const ThreadCoAPBlockMaxPayload:Int = 4096
Rem
bbdoc: Blockwise segment size in bytes.
End Rem
Const ThreadCoAPBlockSize:Int = 256

Private
Extern "C"
	Function _BlockResource:Int(path:Byte Ptr) = "bmx_thread_coap_block_resource"
	Function _BlockReceive:Int(data:Byte Ptr, capacity:Int, code:Int Var, address:Byte Ptr, addressCapacity:Int) = "bmx_thread_coap_block_receive"
	Function _BlockRespond:Int(code:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_block_respond"
	Function _BlockSend:Int(address:Byte Ptr, port:Int, path:Byte Ptr, code:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_block_send"
	Function _BlockResponse:Int(data:Byte Ptr, capacity:Int, code:Int Var) = "bmx_thread_coap_block_response"
End Extern

Public

Rem
bbdoc: Register one blockwise CoAP resource.
param: URI resource path without a leading slash.
returns: Zero on success or a negative error.
about: Call ThreadCoAPStart first.
End Rem
Function ThreadCoAPBlockResource:Int(path:String)
	If Not path Then
		Return -22
	End If

	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _BlockResource(bytes)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Read a request after all Block1 segments arrive.
param: Buffer for the received payload.
param: Receives the CoAP request method.
param: Receives the sender or resolved IPv6 address.
returns: Assembled payload length, -11 when empty, -90 for a short buffer, or another negative error.
End Rem
Function ThreadCoAPBlockReceive:Int(data:Byte[], requestMethod:Int Var, address:String Var)
	If Not data Then
		Return -22
	End If

	Local addressBytes:Byte[48]
	Local result:Int = _BlockReceive(data, data.length, requestMethod, addressBytes, addressBytes.length)
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
bbdoc: Reply to the last blockwise request.
param: CoAP response code; on read, receives the response code.
param: Payload bytes to send; Null sends an empty payload where allowed.
returns: Zero on success or a negative error.
about: Payloads up to 4096 bytes use Block2 segments.
End Rem
Function ThreadCoAPBlockRespond:Int(code:Int, data:Byte[] = Null)
	Local length:Int
	If data Then
		length = data.length
	End If

	Return _BlockRespond(code, data, length)
End Function

Rem
bbdoc: Send one blockwise CoAP request.
param: The peer IPv6 address; on receive, receives the sender address.
param: URI resource path without a leading slash.
param: CoAP request method, such as ThreadCoAPGet or ThreadCoAPPost.
param: Payload bytes to send; Null sends an empty payload where allowed.
param: The UDP or TCP port.
returns: Zero if queued or a negative error.
about: Poll ThreadCoAPBlockResponse. One client exchange is supported.
End Rem
Function ThreadCoAPBlockSend:Int(address:String, path:String, requestMethod:Int, data:Byte[] = Null, port:Int = 5683)
	If Not address Or Not path Then
		Return -22
	End If

	Local length:Int
	If data Then
		length = data.length
	End If

	Local addressBytes:Byte Ptr = address.ToUTF8String()
	Local pathBytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _BlockSend(addressBytes, port, pathBytes, requestMethod, data, length)
	MemFree(addressBytes)
	MemFree(pathBytes)
	Return result
End Function

Rem
bbdoc: Read a complete blockwise response.
param: Buffer for the received payload.
param: Receives the CoAP response code.
returns: Assembled payload length, -11 while pending, -90 for a short buffer, or another negative error.
End Rem
Function ThreadCoAPBlockResponse:Int(data:Byte[], code:Int Var)
	If Not data Then
		Return -22
	End If

	Return _BlockResponse(data, data.length, code)
End Function

?
