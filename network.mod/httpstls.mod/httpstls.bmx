' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional mbedTLS server transport for Embedded.Network.HTTPServer.
about: Supply PEM certificate and private key text or mounted file paths, then
pass this listener to THTTPServer.Create. Call the server's Service method
regularly to advance TLS. Replace credentials while the server is stopped.
End Rem
Module Embedded.Network.HTTPSTLS
?pico or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Network.HTTPServer
Import BRL.Socket
Import BRL.System
Import BRL.FileSystem

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
Rem
bbdoc: Maximum size in bytes of each PEM certificate or private-key file.
End Rem
Const HTTPSTLSMaxPEMBytes:Int = 16384

Rem
bbdoc: TLS connection returned internally by THTTPSTLSListener.
about: Applications normally work with THTTPServer and do not create this type.
End Rem
Type THTTPSTLSConnection Implements IHTTPConnection
	Private
	Field socket:TSocket
	Field context:Byte Ptr

	Public
	Rem
	bbdoc: Wraps an accepted socket and native TLS connection.
	param: Accepted TCP socket owned by this wrapper.
	param: Native TLS connection context owned by this wrapper.
	returns: A connection wrapper for the HTTP listener.
	End Rem
	Function Create:THTTPSTLSConnection(accepted:TSocket, native:Byte Ptr)
		Local connection:THTTPSTLSConnection = New THTTPSTLSConnection
		connection.socket = accepted
		connection.context = native
		Return connection
	End Function

	Rem
	bbdoc: Tries to read decrypted bytes without blocking.
	param: Destination buffer for received bytes.
	param: Maximum number of bytes to receive.
	returns: Byte count, HTTPWouldBlock, zero on close, or a negative error.
	End Rem
	Method TryRecv:Int(buffer:Byte Ptr, count:Size_T)
		If Not context Then Return -1
		Return _TLSRecv(context, buffer, count)
	End Method

	Rem
	bbdoc: Tries to send encrypted bytes without blocking.
	param: Source buffer containing bytes to send.
	param: Maximum number of bytes to send.
	returns: Byte count, HTTPWouldBlock, zero on close, or a negative error.
	End Rem
	Method TrySend:Int(buffer:Byte Ptr, count:Size_T)
		If Not context Then Return -1
		Return _TLSSend(context, buffer, count)
	End Method

	Rem
	bbdoc: Gets the accepted peer's IP address.
	returns: Remote IP address as text.
	End Rem
	Method RemoteIP:String()
		If socket Then Return socket.RemoteIp()
		Return ""
	End Method

	Rem
	bbdoc: Releases this TLS connection and its underlying socket.
	End Rem
	Method Close()
		If context Then _TLSClose(context)
		context = Null
		If socket Then socket.Close()
		socket = Null
	End Method
End Type

Rem
bbdoc: Optional HTTPS listener passed to THTTPServer.Create.
about: Create from PEM text or mounted files. Start validates credentials;
Stop the HTTP server before replacing a certificate and key pair.
End Rem
Type THTTPSTLSListener Implements IHTTPListener
	Private
	Field certificate:String
	Field key:String
	Field listener:TSocket
	Field context:Byte Ptr
	Field errorText:String
	Field certificatePath:String
	Field keyPath:String

	Public
	Rem
	bbdoc: Creates a listener from a PEM certificate and matching private key.
	param: PEM-encoded server certificate text.
	param: PEM-encoded matching private key text.
	returns: A listener, or Null when either credential is empty.
	about: Start validates the pair before binding the socket.
	End Rem
	Function Create:THTTPSTLSListener(certificatePEM:String, privateKeyPEM:String)
		If Not certificatePEM Or Not privateKeyPEM Then Return Null
		Local transport:THTTPSTLSListener = New THTTPSTLSListener
		transport.certificate = certificatePEM
		transport.key = privateKeyPEM
		Return transport
	End Function

	Rem
	bbdoc: Creates a listener that reads PEM files from mounted storage at Start.
	param: Mounted path to the PEM certificate file.
	param: Mounted path to the matching PEM private key file.
	returns: A listener, or Null when either path is empty.
	about: Paths may use littlefs:: on Pico W or ESP32. Each file is limited
	to #HTTPSTLSMaxPEMBytes bytes. Call
	#ReplaceFromFiles between Stop and Start to read changed files.
	End Rem
	Function CreateFromFiles:THTTPSTLSListener(certificateFile:String, privateKeyFile:String)
		If Not certificateFile Or Not privateKeyFile Then Return Null
		Local transport:THTTPSTLSListener = New THTTPSTLSListener
		transport.certificatePath = certificateFile
		transport.keyPath = privateKeyFile
		Return transport
	End Function

	Private
	Method _TLSFailure:String()
		Local stage:String
		Select _TLSLastStage()
			Case 1 stage = "random source"
			Case 2 stage = "certificate"
			Case 3 stage = "private key"
			Case 4 stage = "TLS configuration"
			Case 5 stage = "certificate and key pairing"
			Default stage = "allocation"
		End Select
		Return "TLS initialization failed: " + stage + ..
			" (mbedTLS " + _TLSLastError() + ")"
	End Method

	Method _ReadPEM:String(path:String, label:String)
		Local info:SFileStat
		If Not FileStat(path, info) Or info.fileType <> FILETYPE_FILE Then
			errorText = label + " file is unavailable: " + path
			Return Null
		End If
		If info.size < 1 Or info.size > HTTPSTLSMaxPEMBytes Then
			errorText = label + " file must contain 1 to " + HTTPSTLSMaxPEMBytes + " bytes"
			Return Null
		End If
		Local stream:TStream = ReadStream(path)
		If Not stream Then
			errorText = label + " file could not be opened: " + path
			Return Null
		End If
		Local value:String
		Local bytes:Byte[]
		Try
			bytes = New Byte[Int(info.size)]
			Local count:Int
			While count < bytes.length
				Local received:Long = stream.Read(Varptr bytes[count], bytes.length - count)
				If received <= 0 Then Exit
				count :+ Int(received)
			Wend
			Local extra:Byte
			If count = bytes.length And stream.Read(Varptr extra, 1) = 0 Then
				value = String.FromUTF8Bytes(Varptr bytes[0], count)
			End If
		Catch failure:Object
		Catch failure:String
		End Try
		Try
			stream.Close()
		Catch failure:Object
			value = Null
		Catch failure:String
			value = Null
		End Try
		If bytes Then MemClear(Varptr bytes[0], Size_T(bytes.length))
		If Not value Then errorText = label + " file changed or could not be read: " + path
		Return value
	End Method

	Method _Prepare:Int(certificatePEM:String, privateKeyPEM:String)
		If Not certificatePEM Or Not privateKeyPEM Then
			errorText = "TLS certificate and private key are required"
			Return False
		End If
		Local certLength:Size_T
		Local keyLength:Size_T
		If certificatePEM.Find(Chr(0)) >= 0 Or privateKeyPEM.Find(Chr(0)) >= 0 Then
			errorText = "TLS PEM credentials contain a NUL byte"
			Return False
		End If
		Local certBytes:Byte Ptr = certificatePEM.ToUTF8String(certLength)
		Local keyBytes:Byte Ptr = privateKeyPEM.ToUTF8String(keyLength)
		If certLength > HTTPSTLSMaxPEMBytes Or keyLength > HTTPSTLSMaxPEMBytes Then
			MemFree(certBytes)
			MemClear(keyBytes, keyLength + 1)
			MemFree(keyBytes)
			errorText = "TLS PEM credentials exceed " + HTTPSTLSMaxPEMBytes + " bytes"
			Return False
		End If
		Local candidate:Byte Ptr = _TLSCreate(certBytes, certLength + 1, keyBytes, keyLength + 1)
		MemFree(certBytes)
		MemClear(keyBytes, keyLength + 1)
		MemFree(keyBytes)
		If Not candidate Then
			errorText = _TLSFailure()
			Return False
		End If
		If context Then _TLSFree(context)
		context = candidate
		certificate = certificatePEM
		key = privateKeyPEM
		errorText = ""
		Return True
	End Method

	Public
	Rem
	bbdoc: Validates and replaces the certificate and key while stopped.
	param: PEM-encoded replacement certificate text.
	param: PEM-encoded matching replacement private key text.
	returns: True when validated and installed; False with detail from LastError.
	about: A failed replacement leaves the previous credentials available.
	End Rem
	Method ReplaceCredentials:Int(certificatePEM:String, privateKeyPEM:String)
		If listener Then
			errorText = "Stop the HTTPS server before replacing TLS credentials"
			Return False
		End If
		If Not _Prepare(certificatePEM, privateKeyPEM) Then Return False
		certificatePath = ""
		keyPath = ""
		Return True
	End Method

	Rem
	bbdoc: Reads and validates replacement PEM files for the next Start.
	param: Mounted path to the replacement certificate file.
	param: Mounted path to the matching replacement private key file.
	returns: True when validated and installed; False with detail from LastError.
	about: Call after THTTPServer.Stop. A failed replacement preserves the
	previous credentials. The files need only be available during this call.
	End Rem
	Method ReplaceFromFiles:Int(certificateFile:String, privateKeyFile:String)
		If listener Then
			errorText = "Stop the HTTPS server before replacing TLS credentials"
			Return False
		End If
		If Not certificateFile Or Not privateKeyFile Then
			errorText = "TLS certificate and private key paths are required"
			Return False
		End If
		Local certPEM:String = _ReadPEM(certificateFile, "Certificate")
		If Not certPEM Then Return False
		Local keyPEM:String = _ReadPEM(privateKeyFile, "Private key")
		If Not keyPEM Then Return False
		If Not _Prepare(certPEM, keyPEM) Then Return False
		certificatePath = certificateFile
		keyPath = privateKeyFile
		Return True
	End Method

	Rem
	bbdoc: Starts the TLS listener after validating its credentials.
	param: TCP port to bind.
	param: Maximum pending connection backlog.
	returns: True when listening; False with detail from LastError.
	End Rem
	Method Start:Int(port:Int, backlog:Int)
		If listener Then Return True
		If certificatePath And Not certificate Then
			If Not ReplaceFromFiles(certificatePath, keyPath) Then Return False
		ElseIf Not context
			If Not _Prepare(certificate, key) Then Return False
		End If
		listener = TSocket.CreateTCP()
		If listener Then
			listener.SetSockOpt(SOL_SOCKET, SO_REUSEADDR, True)
			If listener.Bind(port) And listener.Listen(backlog) Then
				errorText = ""
				Return True
			End If
			listener.Close()
		End If
		listener = Null
		_TLSFree(context)
		context = Null
		errorText = "TLS socket bind or listen failed"
		Return False
	End Method

	Rem
	bbdoc: Accepts a pending TLS connection without blocking.
	returns: A connection, or Null when none is ready or allocation fails.
	End Rem
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

	Rem
	bbdoc: Closes the listener and releases its TLS context.
	End Rem
	Method Close()
		If listener Then listener.Close()
		listener = Null
		If context Then _TLSFree(context)
		context = Null
	End Method

	Rem
	bbdoc: Returns the latest listener or credential validation failure.
	returns: Latest failure message, or an empty string when none is recorded.
	End Rem
	Method LastError:String()
		Return errorText
	End Method
End Type
?
