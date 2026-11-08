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

Rem
bbdoc: CoAP GET request method.
End Rem
Const ThreadCoAPGet:Int = 1
Rem
bbdoc: CoAP POST request method.
End Rem
Const ThreadCoAPPost:Int = 2
Rem
bbdoc: CoAP PUT request method.
End Rem
Const ThreadCoAPPut:Int = 3
Rem
bbdoc: CoAP DELETE request method.
End Rem
Const ThreadCoAPDelete:Int = 4
Rem
bbdoc: CoAP 2.05 Content response code.
End Rem
Const ThreadCoAPContent:Int = 69
Rem
bbdoc: CoAP 2.04 Changed response code.
End Rem
Const ThreadCoAPChanged:Int = 68
Rem
bbdoc: CoAP 4.05 Method Not Allowed response code.
End Rem
Const ThreadCoAPMethodNotAllowed:Int = 133
Rem
bbdoc: Maximum ordinary CoAP payload in bytes.
End Rem
Const ThreadCoAPMaxPayload:Int = 1024

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

Rem
bbdoc: Start the CoAP endpoint on this node.
param: The UDP or TCP port.
returns: Zero on success or a negative error.
End Rem
Function ThreadCoAPStart:Int(port:Int = 5683)
	Return _Start(port)
End Function

Rem
bbdoc: Register the simple server resource path.
param: URI resource path without a leading slash.
returns: Zero on success or a negative error.
about: Use a path without a leading slash. The simple API handles one resource and request at a time.
End Rem
Function ThreadCoAPResource:Int(path:String)
	If Not path Then
		Return -22
	End If

	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _Resource(bytes)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Read a request for the simple resource.
param: Buffer for the received payload.
param: Receives the CoAP request method.
param: Receives the sender or resolved IPv6 address.
returns: Payload length, -11 when none is queued, -90 for a short buffer, or another negative error.
End Rem
Function ThreadCoAPReceive:Int(data:Byte[], requestMethod:Int Var, address:String Var)
	If Not data Then
		Return -22
	End If

	Local addressBytes:Byte[48]
	Local result:Int = _Receive(data, data.length, requestMethod, addressBytes, addressBytes.length)
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
bbdoc: Reply to the last simple server request.
param: CoAP response code; on read, receives the response code.
param: Payload bytes to send; Null sends an empty payload where allowed.
returns: Zero on success or a negative error.
End Rem
Function ThreadCoAPRespond:Int(code:Int, data:Byte[] = Null)
	Local length:Int
	If data Then
		length = data.length
	End If

	Return _Respond(code, data, length)
End Function

Rem
bbdoc: Send one confirmable CoAP request.
param: The peer IPv6 address; on receive, receives the sender address.
param: URI resource path without a leading slash.
param: CoAP request method, such as ThreadCoAPGet or ThreadCoAPPost.
param: Payload bytes to send; Null sends an empty payload where allowed.
param: The UDP or TCP port.
returns: Zero if queued or a negative error.
about: Poll ThreadCoAPResponse. The simple client has one outstanding exchange.
End Rem
Function ThreadCoAPSend:Int(address:String, path:String, requestMethod:Int, data:Byte[] = Null, port:Int = 5683)
	If Not address Or Not path Then
		Return -22
	End If

	Local length:Int
	If data Then
		length = data.length
	End If

	Local addressBytes:Byte Ptr = address.ToUTF8String()
	Local pathBytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _Send(addressBytes, port, pathBytes, requestMethod, data, length)
	MemFree(addressBytes)
	MemFree(pathBytes)
	Return result
End Function

Rem
bbdoc: Read the simple client response.
param: Buffer for the received payload.
param: Receives the CoAP response code.
returns: Payload length, -11 while pending, -90 for a short buffer, or another negative error.
End Rem
Function ThreadCoAPResponse:Int(data:Byte[], code:Int Var)
	If Not data Then
		Return -22
	End If

	Return _Response(data, data.length, code)
End Function

Rem
bbdoc: Register an additional server resource path.
param: URI resource path without a leading slash.
returns: Zero on success or a negative error.
about: Up to four additional paths are supported.
End Rem
Function ThreadCoAPAddResource:Int(path:String)
	If Not path Then
		Return -22
	End If

	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _AddResource(bytes)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Read the next request from an additional resource.
param: Buffer for the received payload.
param: Receives the CoAP request method.
param: Receives the sender or resolved IPv6 address.
param: Receives the matching resource path.
param: Receives the ID used to answer this request.
returns: Payload length, -11 when empty, -90 for a short buffer, or another negative error.
about: Use the returned request ID with ThreadCoAPRespondTo. A short buffer leaves the request queued.
End Rem
Function ThreadCoAPReceiveNext:Int(data:Byte[], requestMethod:Int Var, address:String Var, path:String Var, requestId:Int Var)
	If Not data Then
		Return -22
	End If

	Local addressBytes:Byte[48]
	Local pathBytes:Byte[64]
	Local result:Int = _ReceiveNext(data, data.length, requestMethod, addressBytes, addressBytes.length, pathBytes, pathBytes.length, requestId)
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

Rem
bbdoc: Reply to a request by its ID.
param: Request ID returned by ThreadCoAPReceiveNext.
param: CoAP response code; on read, receives the response code.
param: Payload bytes to send; Null sends an empty payload where allowed.
returns: Zero on success or a negative error.
End Rem
Function ThreadCoAPRespondTo:Int(requestId:Int, code:Int, data:Byte[] = Null)
	Local length:Int
	If data Then
		length = data.length
	End If

	Return _RespondTo(requestId, code, data, length)
End Function

Rem
bbdoc: Send a confirmable CoAP request with its own exchange.
param: The peer IPv6 address; on receive, receives the sender address.
param: URI resource path without a leading slash.
param: CoAP request method, such as ThreadCoAPGet or ThreadCoAPPost.
param: Payload bytes to send; Null sends an empty payload where allowed.
param: The UDP or TCP port.
returns: A positive exchange ID or a negative error.
about: Up to four exchanges may be pending. Poll ThreadCoAPReadResponse using the returned ID.
End Rem
Function ThreadCoAPSendRequest:Int(address:String, path:String, requestMethod:Int, data:Byte[] = Null, port:Int = 5683)
	If Not address Or Not path Then
		Return -22
	End If

	Local length:Int
	If data Then
		length = data.length
	End If

	Local addressBytes:Byte Ptr = address.ToUTF8String()
	Local pathBytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _SendRequest(addressBytes, port, pathBytes, requestMethod, data, length)
	MemFree(addressBytes)
	MemFree(pathBytes)
	Return result
End Function

Rem
bbdoc: Read a response for one exchange ID.
param: Exchange ID returned by ThreadCoAPSendRequest.
param: Buffer for the received payload.
param: Receives the CoAP response code.
returns: Payload length, -11 while pending, -90 for a short buffer, or another negative error.
about: A short buffer leaves the response available for retry.
End Rem
Function ThreadCoAPReadResponse:Int(exchangeId:Int, data:Byte[], code:Int Var)
	If Not data Then
		Return -22
	End If

	Return _ReadResponse(exchangeId, data, data.length, code)
End Function

?
