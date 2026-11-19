' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.EventQueue
Import Embedded.Network.WiFi
Import Embedded.Network.HTTPServer
Import Embedded.Network.HTTPSTLS

' Replace these placeholders in a local ignored copy before building.
Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"
Global CertificatePEM:String = "<certificate-pem>"
Global PrivateKeyPEM:String = "<private-key-pem>"

Global currentEvents:THTTPEventStream
Global eventStarted:UInt
Global sentLater:Int
Global finished:Int

Type TEventsHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		currentEvents = THTTPEventStream.Create(256, 150)
		If Not currentEvents Or Not response.Events(currentEvents) Then RuntimeError "SSE setup failed"
		If Not currentEvents.Retry(500) Then RuntimeError "SSE retry failed"
		If Not currentEvents.Send("first~nsecond", "update", "7") Then RuntimeError "SSE first event failed"
		If Not currentEvents.Send("resume=" + request.Header("Last-Event-ID"), "cursor") Then ..
			RuntimeError "SSE cursor event failed"
		eventStarted = MilliSecs()
		sentLater = False
		finished = False
	End Method
End Type

If NetworkName = "<ssid>" Or CertificatePEM = "<certificate-pem>" Then ..
	RuntimeError "Configure a local copy with Wi-Fi and temporary test credentials"
If WiFiInitialize(WiFiCountryUK) <> 0 Then RuntimeError "Wi-Fi initialization failed"
If WiFiConnectWait(NetworkName, NetworkPassword) <> 0 Then RuntimeError "Wi-Fi connection failed"

Local tls:THTTPSTLSListener = THTTPSTLSListener.Create(CertificatePEM, PrivateKeyPEM)
If Not tls Then RuntimeError "TLS listener creation failed"
Local config:THTTPServerConfig = New THTTPServerConfig
config.port = 8443
config.maxConnections = 1
Local server:THTTPServer = THTTPServer.Create(config, tls)
If Not server Then RuntimeError "HTTP server creation failed"
If Not server.Route("GET", "/events", New TEventsHandler) Then RuntimeError "SSE route failed"
If Not server.Start() Then RuntimeError server.LastError()
Print "HTTPS SSE READY " + WiFiIPv4Address()
While True
	PollEvent()
	If currentEvents And Not currentEvents.IsClosed() Then
		Local elapsed:UInt = MilliSecs() - eventStarted
		If Not sentLater And elapsed >= 450 Then
			If Not currentEvents.Send("later") Then RuntimeError "SSE later event failed"
			sentLater = True
		End If
		If sentLater And Not finished And elapsed >= 800 Then
			currentEvents.Finish()
			finished = True
		End If
	End If
	server.Service(4)
	Delay(1)
Wend
