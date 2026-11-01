' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.EventQueue
Import Embedded.Network.WiFi
Import Embedded.Network.HTTPServer
Import Embedded.Hardware.GPIO
?esp32
Import ESP32.Storage.LittleFS
Import ESP32.Storage.SDCard
?pico
Import Pico.Storage.LittleFS
?

' Set these in a local copy before building. Keep credentials out of source control.
Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"
Const ControlToken:String = "<random-secret>"
Const ControlPin:UInt = 4 ' Select a safe output pin for the actual board.

Type TStatusHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Json("{~qstatus~q:~qok~q,~qpin~q:" + GPIOGetOutput(ControlPin) + "}")
	End Method
End Type

Type TEchoHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text(request.BodyText())
	End Method
End Type

Type TGPIOHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		If request.Header("X-Device-Token") <> ControlToken Then
			response.status = 403
			response.Text("Forbidden")
			Return
		End If
		If request.Parameter("pin") <> String(ControlPin) Or ..
			(request.BodyText() <> "0" And request.BodyText() <> "1") Then
			response.status = 400
			response.Text("Expected the configured pin and body 0 or 1")
			Return
		End If
		If Not GPIOPut(ControlPin, request.BodyText() = "1") Then
			response.status = 500
			response.Text("GPIO write failed")
			Return
		End If
		response.Json("{~qpin~q:" + ControlPin + ",~qvalue~q:" + GPIOGetOutput(ControlPin) + "}")
	End Method
End Type

If NetworkName = "<ssid>" Or ControlToken = "<random-secret>" Then ..
	RuntimeError "Configure the Wi-Fi credentials and control token in a local copy"
If WiFiInitialize(WiFiCountryUK) <> 0 Then RuntimeError "Wi-Fi initialization failed"
If WiFiConnectWait(NetworkName, NetworkPassword) <> 0 Then RuntimeError "Wi-Fi connection failed"
If Not GPIOIsOutputCapable(ControlPin) Or Not GPIOInit(ControlPin) Or ..
	Not GPIOSetOutput(ControlPin) Then RuntimeError "Control pin is unavailable"

?pico
If Not MountLittleFS() Then RuntimeError "LittleFS mount failed"
?esp32
If Not LittleFSIsMounted() Then RuntimeError "LittleFS mount failed"
?

Local server:THTTPServer = THTTPServer.Create()
If Not server Then RuntimeError "HTTP server configuration failed"
server.Route("GET", "/status", New TStatusHandler)
server.Route("POST", "/echo", New TEchoHandler)
server.Route("POST", "/gpio/:pin", New TGPIOHandler)
server.Static("/files/", "littlefs::/www/")
?esp32
If MountSDCard() Then server.Static("/sd/", "sd::/www/")
?
If Not server.Start() Then RuntimeError server.LastError()
Print "HTTP server: http://" + WiFiIPv4Address() + ":8080/status"

While True
	PollEvent()
	server.Service(4)
	Delay(1)
Wend
