' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional mbedTLS server transport for Embedded.Network.HTTPServer.
about: Supply PEM certificate and private key text, then pass this listener to
THTTPServer.Create. Call the server's Service method regularly to advance TLS.
End Rem
Module Embedded.Network.HTTPSTLS
?pico or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Network.HTTPServer
Import BRL.Socket
Import BRL.System

Private
Extern "C"
	Function _TLSCreate:Byte Ptr(certificate:Byte Ptr, certificateLength:Size_T, ..
		key:Byte Ptr, keyLength:Size_T) = "bmx_httpstls_create"
	Function _TLSFree(server:Byte Ptr) = "bmx_httpstls_free"
	Function _TLSAccept:Byte Ptr(server:Byte Ptr, socket:Int) = "bmx_httpstls_accept"
	Function _TLSRecv:Int(connection:Byte Ptr, buffer:Byte Ptr, count:Size_T) = "bmx_httpstls_recv"
	Function _TLSSend:Int(connection:Byte Ptr, buffer:Byte Ptr, count:Size_T) = "bmx_httpstls_send"
	Function _TLSClose(connection:Byte Ptr) = "bmx_httpstls_close"
	Function _TLSLastStage:Int() = "bmx_httpstls_last_stage"
	Function _TLSLastError:Int() = "bmx_httpstls_last_error"
End Extern

Public
Type THTTPSTLSConnection Implements IHTTPConnection
	Private
	Field socket:TSocket
	Field context:Byte Ptr

	Public
	Function Create:THTTPSTLSConnection(accepted:TSocket, native:Byte Ptr)
		Local connection:THTTPSTLSConnection = New THTTPSTLSConnection
		connection.socket = accepted
		connection.context = native
		Return connection
	End Function

	Method TryRecv:Int(buffer:Byte Ptr, count:Size_T)
		If Not context Then Return -1
		Return _TLSRecv(context, buffer, count)
	End Method

	Method TrySend:Int(buffer:Byte Ptr, count:Size_T)
		If Not context Then Return -1
		Return _TLSSend(context, buffer, count)
	End Method

	Method RemoteIP:String()
		If socket Then Return socket.RemoteIp()
		Return ""
	End Method

	Method Close()
		If context Then _TLSClose(context)
		context = Null
		If socket Then socket.Close()
		socket = Null
	End Method
End Type

Type THTTPSTLSListener Implements IHTTPListener
	Private
	Field certificate:String
	Field key:String
	Field listener:TSocket
	Field context:Byte Ptr
	Field errorText:String

	Public
	Function Create:THTTPSTLSListener(certificatePEM:String, privateKeyPEM:String)
		If Not certificatePEM Or Not privateKeyPEM Then Return Null
		Local transport:THTTPSTLSListener = New THTTPSTLSListener
		transport.certificate = certificatePEM
		transport.key = privateKeyPEM
		Return transport
	End Function

	Method Start:Int(port:Int, backlog:Int)
		If listener Then Return True
		Local certLength:Size_T
		Local keyLength:Size_T
		Local certBytes:Byte Ptr = certificate.ToUTF8String(certLength)
		Local keyBytes:Byte Ptr = key.ToUTF8String(keyLength)
		context = _TLSCreate(certBytes, certLength + 1, keyBytes, keyLength + 1)
		MemFree(certBytes)
		MemFree(keyBytes)
		If Not context Then
			Local stage:String
			Select _TLSLastStage()
				Case 1 stage = "random source"
				Case 2 stage = "certificate"
				Case 3 stage = "private key"
				Case 4 stage = "TLS configuration"
				Case 5 stage = "certificate and key pairing"
				Default stage = "allocation"
			End Select
			errorText = "TLS initialization failed: " + stage + ..
				" (mbedTLS " + _TLSLastError() + ")"
			Return False
		End If
		listener = TSocket.CreateTCP()
		If listener Then
			listener.SetSockOpt(SOL_SOCKET, SO_REUSEADDR, True)
			If listener.Bind(port) And listener.Listen(backlog) Then Return True
			listener.Close()
		End If
		listener = Null
		_TLSFree(context)
		context = Null
		errorText = "TLS socket bind or listen failed"
		Return False
	End Method

	Method Accept:IHTTPConnection()
		If Not listener Then Return Null
		Local socket:TSocket = listener.Accept(0)
		If Not socket Then Return Null
		Local native:Byte Ptr = _TLSAccept(context, socket.Socket())
		If Not native Then
			socket.Close()
			errorText = "TLS connection allocation failed"
			Return Null
		End If
		Return THTTPSTLSConnection.Create(socket, native)
	End Method

	Method Close()
		If listener Then listener.Close()
		listener = Null
		If context Then _TLSFree(context)
		context = Null
	End Method

	Method LastError:String()
		Return errorText
	End Method
End Type
?
