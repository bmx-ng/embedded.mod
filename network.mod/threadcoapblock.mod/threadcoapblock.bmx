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

Const ThreadCoAPBlockMaxPayload:Int = 4096
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

' Register one blockwise resource after ThreadCoAPStart().
Function ThreadCoAPBlockResource:Int(path:String)
	If Not path Then Return -22
	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _BlockResource(bytes)
	MemFree(bytes)
	Return result
End Function

' Read a complete request after all Block1 segments arrive.
Function ThreadCoAPBlockReceive:Int(data:Byte[], method:Int Var, address:String Var)
	If Not data Then Return -22
	Local addressBytes:Byte[48]
	Local result:Int = _BlockReceive(data, data.length, method, addressBytes, addressBytes.length)
	If result >= 0 Then
		Local length:Int
		While length < addressBytes.length And addressBytes[length] <> 0
			length :+ 1
		Wend
		address = String.FromUTF8Bytes(addressBytes, length)
	End If
	Return result
End Function

' Reply to the last received request. Payloads up to 4096 bytes use Block2.
Function ThreadCoAPBlockRespond:Int(code:Int, data:Byte[] = Null)
	Local length:Int
	If data Then length = data.length
	Return _BlockRespond(code, data, length)
End Function

' Send one GET, POST, PUT, or DELETE. Poll ThreadCoAPBlockResponse for its reply.
Function ThreadCoAPBlockSend:Int(address:String, path:String, method:Int, data:Byte[] = Null, port:Int = 5683)
	If Not address Or Not path Then Return -22
	Local length:Int
	If data Then length = data.length
	Local addressBytes:Byte Ptr = address.ToUTF8String()
	Local pathBytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _BlockSend(addressBytes, port, pathBytes, method, data, length)
	MemFree(addressBytes)
	MemFree(pathBytes)
	Return result
End Function

' Returns a complete response length, -11 while pending, or a negative error.
Function ThreadCoAPBlockResponse:Int(data:Byte[], code:Int Var)
	If Not data Then Return -22
	Return _BlockResponse(data, data.length, code)
End Function

?
