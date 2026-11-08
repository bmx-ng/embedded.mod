' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Bounded CoAP requests and resources over a Thread mesh.
End Rem
Module Embedded.Network.ThreadCoAP
?nrf52 or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System
Import Embedded.Network.Thread

Const ThreadCoAPGet:Int = 1
Const ThreadCoAPPost:Int = 2
Const ThreadCoAPPut:Int = 3
Const ThreadCoAPDelete:Int = 4
Const ThreadCoAPContent:Int = 69
Const ThreadCoAPChanged:Int = 68
Const ThreadCoAPMethodNotAllowed:Int = 133

Private
Extern "C"
	Function _Start:Int(port:Int) = "bmx_thread_coap_start"
	Function _Resource:Int(path:Byte Ptr) = "bmx_thread_coap_resource"
	Function _Receive:Int(data:Byte Ptr, capacity:Int, code:Int Var, address:Byte Ptr, addressCapacity:Int) = "bmx_thread_coap_receive"
	Function _Respond:Int(code:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_respond"
	Function _Send:Int(address:Byte Ptr, port:Int, path:Byte Ptr, code:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_send"
	Function _Response:Int(data:Byte Ptr, capacity:Int, code:Int Var) = "bmx_thread_coap_response"
	Function _AddResource:Int(path:Byte Ptr) = "bmx_thread_coap_add_resource"
	Function _ReceiveNext:Int(data:Byte Ptr, capacity:Int, code:Int Var, address:Byte Ptr, addressCapacity:Int, path:Byte Ptr, pathCapacity:Int, requestId:Int Var) = "bmx_thread_coap_receive_next"
	Function _RespondTo:Int(requestId:Int, code:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_respond_to"
	Function _SendRequest:Int(address:Byte Ptr, port:Int, path:Byte Ptr, code:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_send_request"
	Function _ReadResponse:Int(exchangeId:Int, data:Byte Ptr, capacity:Int, code:Int Var) = "bmx_thread_coap_read_response"
End Extern
Public

' Starts the CoAP endpoint on this node. Usually port 5683.
Function ThreadCoAPStart:Int(port:Int = 5683)
	Return _Start(port)
End Function

' Register one URI path, without a leading slash.
Function ThreadCoAPResource:Int(path:String)
	If Not path Then Return -22
	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _Resource(bytes)
	MemFree(bytes)
	Return result
End Function

' Returns payload length, -11 when no request is queued, or a negative error.
Function ThreadCoAPReceive:Int(data:Byte[], method:Int Var, address:String Var)
	If Not data Then Return -22
	Local addressBytes:Byte[48]
	Local result:Int = _Receive(data, data.length, method, addressBytes, addressBytes.length)
	If result >= 0 Then
		Local length:Int
		While length < addressBytes.length And addressBytes[length] <> 0
			length :+ 1
		Wend
		address = String.FromUTF8Bytes(addressBytes, length)
	End If
	Return result
End Function

' Respond to the last received request with a CoAP response code and payload.
Function ThreadCoAPRespond:Int(code:Int, data:Byte[] = Null)
	Local length:Int
	If data Then length = data.length
	Return _Respond(code, data, length)
End Function

' Send one confirmable GET or POST. Poll ThreadCoAPResponse for its reply.
Function ThreadCoAPSend:Int(address:String, path:String, method:Int, data:Byte[] = Null, port:Int = 5683)
	If Not address Or Not path Then Return -22
	Local length:Int
	If data Then length = data.length
	Local addressBytes:Byte Ptr = address.ToUTF8String()
	Local pathBytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _Send(addressBytes, port, pathBytes, method, data, length)
	MemFree(addressBytes)
	MemFree(pathBytes)
	Return result
End Function

' Returns payload length on success, -11 while pending, or a negative error.
Function ThreadCoAPResponse:Int(data:Byte[], code:Int Var)
	If Not data Then Return -22
	Return _Response(data, data.length, code)
End Function

' Register one additional URI path. Up to four additional resources can be
' registered alongside the legacy ThreadCoAPResource path.
Function ThreadCoAPAddResource:Int(path:String)
	If Not path Then Return -22
	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _AddResource(bytes)
	MemFree(bytes)
	Return result
End Function

' Poll the additional resources. Returns payload length, -11 when empty, or a
' negative error. The returned request ID selects the matching response.
Function ThreadCoAPReceiveNext:Int(data:Byte[], method:Int Var, address:String Var, path:String Var, requestId:Int Var)
	If Not data Then Return -22
	Local addressBytes:Byte[48]
	Local pathBytes:Byte[64]
	Local result:Int = _ReceiveNext(data, data.length, method, addressBytes, addressBytes.length, pathBytes, pathBytes.length, requestId)
	If result >= 0 Then
		Local addressLength:Int
		While addressLength < addressBytes.length And addressBytes[addressLength] <> 0
			addressLength :+ 1
		Wend
		address = String.FromUTF8Bytes(addressBytes, addressLength)
		Local pathLength:Int
		While pathLength < pathBytes.length And pathBytes[pathLength] <> 0
			pathLength :+ 1
		Wend
		path = String.FromUTF8Bytes(pathBytes, pathLength)
	End If
	Return result
End Function

' Reply to one request returned by ThreadCoAPReceiveNext.
Function ThreadCoAPRespondTo:Int(requestId:Int, code:Int, data:Byte[] = Null)
	Local length:Int
	If data Then length = data.length
	Return _RespondTo(requestId, code, data, length)
End Function

' Send a confirmable GET, POST, PUT, or DELETE and return its exchange ID, or a negative error.
' Up to four exchanges may be pending at once.
Function ThreadCoAPSendRequest:Int(address:String, path:String, method:Int, data:Byte[] = Null, port:Int = 5683)
	If Not address Or Not path Then Return -22
	Local length:Int
	If data Then length = data.length
	Local addressBytes:Byte Ptr = address.ToUTF8String()
	Local pathBytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _SendRequest(addressBytes, port, pathBytes, method, data, length)
	MemFree(addressBytes)
	MemFree(pathBytes)
	Return result
End Function

' Read a response by exchange ID. Returns payload length, -11 while pending,
' -90 if the supplied buffer is too small, or another negative error.
Function ThreadCoAPReadResponse:Int(exchangeId:Int, data:Byte[], code:Int Var)
	If Not data Then Return -22
	Return _ReadResponse(exchangeId, data, data.length, code)
End Function

?
