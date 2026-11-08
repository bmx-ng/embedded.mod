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

Const ThreadCoAPSecureMaxPayload:Int = 1024
Const ThreadCoAPSecurePort:Int = 5684
Const ThreadCoAPSecureConnecting:Int = 1
Const ThreadCoAPSecureConnected:Int = 2

Private
Extern "C"
	Function _SecureStart:Int(psk:Byte Ptr, pskLength:Int, identity:Byte Ptr, identityLength:Int, port:Int) = "bmx_thread_coap_secure_start"
	Function _SecureResource:Int(path:Byte Ptr) = "bmx_thread_coap_secure_resource"
	Function _SecureReceive:Int(data:Byte Ptr, capacity:Int, method:Int Var, address:Byte Ptr, addressCapacity:Int) = "bmx_thread_coap_secure_receive"
	Function _SecureRespond:Int(code:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_secure_respond"
	Function _SecureConnect:Int(address:Byte Ptr, port:Int) = "bmx_thread_coap_secure_connect"
	Function _SecureConnection:Int() = "bmx_thread_coap_secure_connection"
	Function _SecureSend:Int(path:Byte Ptr, method:Int, data:Byte Ptr, length:Int) = "bmx_thread_coap_secure_send"
	Function _SecureResponse:Int(data:Byte Ptr, capacity:Int, code:Int Var) = "bmx_thread_coap_secure_response"
	Function _SecureStop:Int() = "bmx_thread_coap_secure_stop"
End Extern
Public

' A 16 to 32 byte PSK and a nonempty UTF-8 identity are required.
Function ThreadCoAPSecureStart:Int(psk:Byte[], identity:String, port:Int = ThreadCoAPSecurePort)
	If Not psk Or Not identity Then Return -22
	Local id:Byte Ptr = identity.ToUTF8String()
	Local idLength:Int
	While id[idLength] <> 0
		idLength :+ 1
	Wend
	Local result:Int = _SecureStart(psk, psk.length, id, idLength, port)
	MemFree(id)
	Return result
End Function

Function ThreadCoAPSecureResource:Int(path:String)
	If Not path Then Return -22
	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _SecureResource(bytes)
	MemFree(bytes)
	Return result
End Function

Function ThreadCoAPSecureReceive:Int(data:Byte[], method:Int Var, address:String Var)
	If Not data Then Return -22
	Local addressBytes:Byte[48]
	Local result:Int = _SecureReceive(data, data.length, method, addressBytes, addressBytes.length)
	If result >= 0 Then
		Local length:Int
		While length < addressBytes.length And addressBytes[length] <> 0
			length :+ 1
		Wend
		address = String.FromUTF8Bytes(addressBytes, length)
	End If
	Return result
End Function

Function ThreadCoAPSecureRespond:Int(code:Int, data:Byte[] = Null)
	Local length:Int
	If data Then length = data.length
	Return _SecureRespond(code, data, length)
End Function

Function ThreadCoAPSecureConnect:Int(address:String, port:Int = ThreadCoAPSecurePort)
	If Not address Then Return -22
	Local bytes:Byte Ptr = address.ToUTF8String()
	Local result:Int = _SecureConnect(bytes, port)
	MemFree(bytes)
	Return result
End Function

' Returns 0 when idle, 1 during handshake, 2 when connected, or a negative error.
Function ThreadCoAPSecureConnection:Int()
	Return _SecureConnection()
End Function

Function ThreadCoAPSecureSend:Int(path:String, method:Int, data:Byte[] = Null)
	If Not path Then Return -22
	Local length:Int
	If data Then length = data.length
	Local bytes:Byte Ptr = path.ToUTF8String()
	Local result:Int = _SecureSend(bytes, method, data, length)
	MemFree(bytes)
	Return result
End Function

Function ThreadCoAPSecureResponse:Int(data:Byte[], code:Int Var)
	If Not data Then Return -22
	Return _SecureResponse(data, data.length, code)
End Function

Function ThreadCoAPSecureStop:Int()
	Return _SecureStop()
End Function

?
