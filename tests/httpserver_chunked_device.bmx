' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.EventQueue
Import BRL.FileSystem
Import BRL.TextStream
Import Embedded.Network.WiFi
Import Embedded.Network.HTTPServer
Import Embedded.Network.HTTPSTLS
?esp32
Import ESP32.Storage.LittleFS
?pico
Import Pico.Storage.LittleFS
?

' Replace these placeholders in a local copy before building.
Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"
Global CertificatePEM:String = "<certificate-pem>"
Global PrivateKeyPEM:String = "<private-key-pem>"

Type TGeneratedProducer Implements IHTTPResponseProducer
	Field remaining:Int = 8193
	Field paused:Int

	Method TryRead:Int(buffer:Byte Ptr, capacity:Int)
		If Not paused Then paused = True; Return HTTPWouldBlock
		Local count:Int = Min(capacity, remaining)
		For Local i:Int = 0 Until count
			buffer[i] = 120
		Next
		remaining :- count
		Return count
	End Method

	Method Close()
	End Method
End Type

Type TGeneratedHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Produce(New TGeneratedProducer, "text/plain")
	End Method
End Type

Type TStatusHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Json("{~qstatus~q:~qok~q}")
	End Method
End Type

Type TNoBodyHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.status = 204
		response.Produce(New TGeneratedProducer)
	End Method
End Type

If NetworkName = "<ssid>" Or CertificatePEM = "<certificate-pem>" Then ..
	RuntimeError "Configure a local copy with Wi-Fi and temporary test credentials"
?esp32
If Not LittleFSIsMounted() Then RuntimeError "LittleFS is not mounted"
?pico
If Not MountLittleFS() Then RuntimeError "LittleFS mount failed"
?
Local asset:String = ""
For Local i:Int = 0 Until 256
	asset :+ "abcdef0123456789"
Next
If FileType("littlefs::/www") <> FILETYPE_DIR Then
	If Not CreateDir("littlefs::/www") Then RuntimeError "LittleFS fixture directory failed"
End If
If Not SaveText(asset, "littlefs::/www/range-fixture.txt") Then RuntimeError "LittleFS fixture write failed"
If WiFiInitialize(WiFiCountryUK) <> 0 Then RuntimeError "Wi-Fi initialization failed"
If WiFiConnectWait(NetworkName, NetworkPassword) <> 0 Then RuntimeError "Wi-Fi connection failed"

Local tls:THTTPSTLSListener = THTTPSTLSListener.Create(CertificatePEM, PrivateKeyPEM)
If Not tls Then RuntimeError "TLS listener creation failed"
Local config:THTTPServerConfig = New THTTPServerConfig
config.port = 8443
config.keepAlive = True
config.maxConnections = 1
Local server:THTTPServer = THTTPServer.Create(config, tls)
If Not server Then RuntimeError "HTTP server creation failed"
If Not server.Route("GET", "/generated", New TGeneratedHandler) Then RuntimeError "generated route failed"
If Not server.Route("GET", "/status", New TStatusHandler) Then RuntimeError "status route failed"
If Not server.Route("GET", "/no-body", New TNoBodyHandler) Then RuntimeError "no-body route failed"
If Not server.Static("/assets/", "littlefs::/www/", 60) Then RuntimeError "static route failed"
If Not server.Start() Then RuntimeError server.LastError()
Print "HTTPS CHUNKED READY " + WiFiIPv4Address()
While True
	PollEvent()
	server.Service(4)
	Delay(1)
Wend
