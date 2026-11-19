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

' Replace these placeholders in a local ignored copy before building.
Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"
Global CertificatePEM:String = "<certificate-pem>"
Global PrivateKeyPEM:String = "<private-key-pem>"

Type TEchoWebSocket Implements IHTTPWebSocketHandler
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
config.maxConnections = 1
Local server:THTTPServer = THTTPServer.Create(config, tls)
If Not server Then RuntimeError "HTTP server creation failed"
Local upgrade:THTTPWebSocketUpgrade = THTTPWebSocketUpgrade.Create(New TEchoWebSocket, 256, 1024)
If Not upgrade.SetSubprotocols(["device.v1"]) Then RuntimeError "WebSocket subprotocol setup failed"
upgrade.SetCompressionFactory(THTTPWebSocketDeflateFactory.Create())
If Not server.RouteUpgrade("/ws", upgrade) Then ..
	RuntimeError "WebSocket route failed"
If Not server.Start() Then RuntimeError server.LastError()
Print "WSS READY " + WiFiIPv4Address()
While True
	PollEvent()
	server.Service(4)
	Delay(1)
Wend
