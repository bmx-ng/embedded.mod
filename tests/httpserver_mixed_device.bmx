' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.EventQueue
Import Embedded.Network.WiFi
Import Embedded.Network.HTTPServer
Import Embedded.Network.HTTPSTLS
Import Embedded.Network.WebSocket
Import Embedded.Network.WebSocketDeflate
Import Embedded.Runtime.Memory

' Replace these placeholders in a local ignored copy before building.
Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"
Global CertificatePEM:String = "<certificate-pem>"
Global PrivateKeyPEM:String = "<private-key-pem>"

Global events:THTTPEventStream
Global nextEvent:UInt
Global sequence:Int
Global lastCollect:UInt

Type TStatusHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text("ok")
	End Method
End Type

Type TMetricsHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text("integrity=" + HeapIntegrityValid() + ..
			";failures=" + (ObjectFailureCount() + ArrayFailureCount() + StringFailureCount()) + ..
			";reusable=" + HeapReusableBytes() + ..
			";objects=" + ObjectLiveCount() + ..
			";arrays=" + ArrayLiveCount() + ..
			";strings=" + StringLiveCount())
	End Method
End Type

Type TEchoHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text(request.BodyText())
	End Method
End Type

Type TEventsHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		events = THTTPEventStream.Create(512, 1000)
		If Not events Or Not response.Events(events) Then RuntimeError "SSE setup failed"
		If Not events.Send("connected", "ready", "1") Then RuntimeError "SSE send failed"
		nextEvent = MilliSecs() + 500
	End Method
End Type

Type TWebSocketHandler Implements IHTTPWebSocketHandler
	Method Accept:Int(request:THTTPRequest)
		Return request.Header("Origin") = "https://device.test"
	End Method

	Method Open(socket:THTTPWebSocket, request:THTTPRequest)
		If Not socket.SendText("ready") Then RuntimeError "WebSocket greeting failed"
	End Method

	Method Message(socket:THTTPWebSocket, data:Byte[], isText:Int)
		If isText Then
			Local value:String = ""
			If data.length Then value = String.FromUTF8Bytes(Varptr data[0], data.length)
			If Not socket.SendText("echo:" + value) Then RuntimeError "WebSocket text echo failed"
		Else
			If Not socket.SendBinary(data) Then RuntimeError "WebSocket binary echo failed"
		End If
	End Method

	Method Closed(socket:THTTPWebSocket, code:Int)
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
config.maxConnections = 3
config.keepAlive = True
Local server:THTTPServer = THTTPServer.Create(config, tls)
If Not server Then RuntimeError "HTTP server creation failed"
If Not server.Route("GET", "/status", New TStatusHandler) Then RuntimeError "Status route failed"
If Not server.Route("GET", "/metrics", New TMetricsHandler) Then RuntimeError "Metrics route failed"
If Not server.Route("POST", "/echo", New TEchoHandler) Then RuntimeError "Echo route failed"
If Not server.Route("GET", "/events", New TEventsHandler) Then RuntimeError "SSE route failed"
Local upgrade:THTTPWebSocketUpgrade = THTTPWebSocketUpgrade.Create(New TWebSocketHandler, 256, 1024)
If Not upgrade.SetSubprotocols(["device.v1"]) Then RuntimeError "Subprotocol setup failed"
upgrade.SetCompressionFactory(THTTPWebSocketDeflateFactory.Create())
If Not server.RouteUpgrade("/ws", upgrade) Then RuntimeError "WebSocket route failed"
If Not server.Start() Then RuntimeError server.LastError()
Print "HTTPS MIXED READY " + WiFiIPv4Address()
While True
	PollEvent()
	If events And Not events.IsClosed() And MilliSecs() >= nextEvent Then
		sequence :+ 1
		events.Send("tick " + sequence, "update", String(sequence + 1))
		nextEvent = MilliSecs() + 500
	End If
	server.Service(8)
	If MilliSecs() - lastCollect >= 5000 Then
		CollectObjects()
		lastCollect = MilliSecs()
	End If
	Delay(1)
Wend
