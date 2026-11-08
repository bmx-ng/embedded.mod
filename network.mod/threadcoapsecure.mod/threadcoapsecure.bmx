' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional CoAP over DTLS with a runtime pre-shared key on Thread.
about: Importing this module includes the OpenThread secure CoAP API in the
firmware. The key and identity must be supplied at runtime and remain owned by
the native module until ThreadCoAPSecureStop(). One resource and one client
exchange are supported.
End Rem
Module Embedded.Network.ThreadCoAPSecure
?nrf52 or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System
Import Embedded.Network.ThreadCoAP

Rem
bbdoc: Maximum secure CoAP payload in bytes.
End Rem
Const ThreadCoAPSecureMaxPayload:Int = 1024
Rem
bbdoc: Default secure CoAP UDP port.
End Rem
Const ThreadCoAPSecurePort:Int = 5684
Rem
bbdoc: A DTLS handshake is in progress.
End Rem
Const ThreadCoAPSecureConnecting:Int = 1
Rem
bbdoc: The DTLS connection is ready.
End Rem
Const ThreadCoAPSecureConnected:Int = 2

Private
Extern "C"
	Function _SecureStart:Int(psk:Byte Ptr, pskLength:Int, identity:Byte Ptr, identityLength:Int, port:Int) = "bmx_thread_coap_secure_start"
	Function _SecureResource:Int(path:Byte Ptr) = "bmx_thread_coap_secure_resource"
	Function _SecureReceive:Int(data:Byte Ptr, capacity:Int, requestMethod:Int Var, address:Byte Ptr, addressCapacity:Int) = "bmx_thread_coap_secure_receive"
	Function _SecureRespond:Int(code:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_secure_respond"
	Function _SecureConnect:Int(address:Byte Ptr, port:Int) = "bmx_thread_coap_secure_connect"
	Function _SecureConnection:Int() = "bmx_thread_coap_secure_connection"
	Function _SecureSend:Int(path:Byte Ptr, requestMethod:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_secure_send"
	Function _SecureResponse:Int(data:Byte Ptr, capacity:Int, code:Int Var) = "bmx_thread_coap_secure_response"
	Function _SecureStop:Int() = "bmx_thread_coap_secure_stop"
End Extern

Public

Rem
bbdoc: Start CoAP over DTLS with a pre-shared key.
param: The 16–32 byte pre-shared DTLS key.
param: Nonempty UTF-8 PSK identity.
param: The UDP or TCP port.
returns: Zero on success or a negative error.
about: The key must be 16–32 bytes and the UTF-8 identity nonempty. The module retains copies until ThreadCoAPSecureStop.
End Rem
Function ThreadCoAPSecureStart:Int(psk:Byte[], identity:String, port:Int = ThreadCoAPSecurePort)
	If Not psk Or Not identity Then
		Return -22
	End If

	Local id:Byte Ptr = identity.ToUTF8String()
	Local idLength:Int
	While id[idLength] <> 0
		idLength :+ 1
	Wend

	Local result:Int = _SecureStart(psk, psk.length, id, idLength, port)
	MemFree(id)
	Return result
End Function

Rem
bbdoc: Register one secure CoAP resource path.
param: URI resource path without a leading slash.
returns: Zero on success or a negative error.
End Rem
Function ThreadCoAPSecureResource:Int(path:String)
	If Not path Then
		Return -22
	End If

	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _SecureResource(bytes)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Read a secure CoAP server request.
param: Buffer for the received payload.
param: Receives the CoAP request method.
param: Receives the sender or resolved IPv6 address.
returns: Payload length, -11 when empty, -90 for a short buffer, or another negative error.
End Rem
Function ThreadCoAPSecureReceive:Int(data:Byte[], requestMethod:Int Var, address:String Var)
	If Not data Then
		Return -22
	End If

	Local addressBytes:Byte[48]
	Local result:Int = _SecureReceive(data, data.length, requestMethod, addressBytes, addressBytes.length)
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
bbdoc: Reply to the last secure CoAP request.
param: CoAP response code; on read, receives the response code.
param: Payload bytes to send; Null sends an empty payload where allowed.
returns: Zero on success or a negative error.
End Rem
Function ThreadCoAPSecureRespond:Int(code:Int, data:Byte[] = Null)
	Local length:Int
	If data Then
		length = data.length
	End If

	Return _SecureRespond(code, data, length)
End Function

Rem
bbdoc: Begin a DTLS connection to a peer.
param: The peer IPv6 address; on receive, receives the sender address.
param: The UDP or TCP port.
returns: Zero if started or a negative error.
about: Poll ThreadCoAPSecureConnection for ThreadCoAPSecureConnected.
End Rem
Function ThreadCoAPSecureConnect:Int(address:String, port:Int = ThreadCoAPSecurePort)
	If Not address Then
		Return -22
	End If

	Local bytes:Byte Ptr = address.ToUTF8String()
	Local result:Int = _SecureConnect(bytes, port)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Get the DTLS connection state.
returns: Zero when idle, ThreadCoAPSecureConnecting during handshake, ThreadCoAPSecureConnected when ready, or a negative error.
End Rem
Function ThreadCoAPSecureConnection:Int()
	Return _SecureConnection()
End Function

Rem
bbdoc: Send one request on the secure connection.
param: URI resource path without a leading slash.
param: CoAP request method, such as ThreadCoAPGet or ThreadCoAPPost.
param: Payload bytes to send; Null sends an empty payload where allowed.
returns: Zero if queued or a negative error.
End Rem
Function ThreadCoAPSecureSend:Int(path:String, requestMethod:Int, data:Byte[] = Null)
	If Not path Then
		Return -22
	End If

	Local length:Int
	If data Then
		length = data.length
	End If

	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _SecureSend(bytes, requestMethod, data, length)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Read the secure CoAP response.
param: Buffer for the received payload.
param: Receives the CoAP response code.
returns: Payload length, -11 while pending, -90 for a short buffer, or another negative error.
End Rem
Function ThreadCoAPSecureResponse:Int(data:Byte[], code:Int Var)
	If Not data Then
		Return -22
	End If

	Return _SecureResponse(data, data.length, code)
End Function

Rem
bbdoc: Stop secure CoAP and release key material.
returns: Zero on success or a negative error.
End Rem
Function ThreadCoAPSecureStop:Int()
	Return _SecureStop()
End Function

?
