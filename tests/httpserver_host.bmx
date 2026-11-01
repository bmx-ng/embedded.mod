' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.System
Import BRL.SystemDefault
Import Embedded.Network.HTTPServer

Type TStatusHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Json("{~qstatus~q:~qok~q}")
	End Method
End Type

Type TEchoHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text(request.BodyText())
	End Method
End Type

Type TParamHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text(request.Parameter("pin"))
	End Method
End Type

Type TQueryHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text(request.QueryValue("value"))
	End Method
End Type

Type TFixedHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text("fixed")
	End Method
End Type

If AppArgs.length < 3 Then RuntimeError "expected port and document root"
Local config:THTTPServerConfig = New THTTPServerConfig
config.port = AppArgs[1].ToInt()
config.maxConnections = 2
config.headerTimeoutMs = 300
config.bodyTimeoutMs = 300
Local server:THTTPServer = THTTPServer.Create(config)
If Not server Then RuntimeError "invalid server config"
If Not server.Route("GET", "/status", New TStatusHandler) Then RuntimeError "route failed"
If Not server.Route("POST", "/echo", New TEchoHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/gpio/:pin", New TParamHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/gpio/fixed", New TFixedHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/query", New TQueryHandler) Then RuntimeError "route failed"
If Not server.Static("/assets/", AppArgs[2]) Then RuntimeError "static route failed"
If Not server.Start() Then RuntimeError server.LastError()
server.Stop()
If Not server.Start() Then RuntimeError "restart failed: " + server.LastError()
server.Stop()
If Not server.Start() Then RuntimeError "second restart failed: " + server.LastError()
While True
	PollSystem()
	server.Service(8)
	Delay(1)
Wend
