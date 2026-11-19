' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Framework BRL.StandardIO
Import BRL.System
Import BRL.SystemDefault
Import BRL.FileSystem
Import Embedded.Network.HTTPServer

Global restartRequested:Int
Global uploadAborted:Int
Global producerClosed:Int
Global eventStream:THTTPEventStream
Global lastEventID:String

Type TGeneratedProducer Implements IHTTPResponseProducer
	Field remaining:Int
	Field paused:Int
	Field fail:Int

	Method TryRead:Int(buffer:Byte Ptr, capacity:Int)
		If Not paused Then paused = True; Return HTTPWouldBlock
		If fail Then Return -1
		Local count:Int = Min(capacity, remaining)
		For Local i:Int = 0 Until count
			buffer[i] = 120
		Next
		remaining :- count
		Return count
	End Method

	Method Close()
		producerClosed :+ 1
	End Method
End Type

Type TFailingProducerHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		Local producer:TGeneratedProducer = New TGeneratedProducer
		producer.fail = True
		response.Produce(producer)
	End Method
End Type

Type TGeneratedHandler Implements IHTTPHandler
	Field count:Int

	Method Handle(request:THTTPRequest, response:THTTPResponse)
		Local producer:TGeneratedProducer = New TGeneratedProducer
		producer.remaining = count
		response.Produce(producer, "text/plain")
	End Method
End Type

Type TUnknownFileHandler Implements IHTTPHandler
	Field path:String

	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.StreamUnknown(ReadStream(path), "text/plain")
	End Method
End Type

Type TNoBodyProducerHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.status = 204
		Local producer:TGeneratedProducer = New TGeneratedProducer
		producer.remaining = 100
		response.Produce(producer)
	End Method
End Type

Type TProducerClosedHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text(producerClosed)
	End Method
End Type

Type TEventsHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		lastEventID = request.Header("Last-Event-ID")
		eventStream = THTTPEventStream.Create(128, 200)
		If Not response.Events(eventStream) Then RuntimeError "SSE response setup failed"
		If Not eventStream.Send("first~nsecond", "update", "42") Then RuntimeError "SSE initial event failed"
		If Not eventStream.Retry(750) Then RuntimeError "SSE retry failed"
	End Method
End Type

Type TEventsSendHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		If Not eventStream Or eventStream.IsClosed() Then
			response.status = 409
			response.Text("closed")
			Return
		End If
		Local oversized:String = ""
		For Local i:Int = 0 Until 200
			oversized :+ "x"
		Next
		If eventStream.Send(oversized) Then RuntimeError "SSE queue accepted oversized event"
		If eventStream.Send("bad", "", "line~nbreak") Then RuntimeError "SSE accepted multiline ID"
		If Not eventStream.Send("later") Then RuntimeError "SSE event queue failed"
		If Not eventStream.Comment("note") Then RuntimeError "SSE comment queue failed"
		response.Text("queued")
	End Method
End Type

Type TEventsFinishHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		If eventStream Then eventStream.Finish()
		response.Text("finished")
	End Method
End Type

Type TEventsStateHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		Local closed:Int = True
		If eventStream Then closed = eventStream.IsClosed()
		response.Text(closed + ":" + lastEventID)
	End Method
End Type

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

Type TRestartHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text("restarting")
		restartRequested = True
	End Method
End Type

Type TThrowHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		Throw "deliberate handler failure"
	End Method
End Type

Type TAbortCountHandler Implements IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
		response.Text(uploadAborted)
	End Method
End Type

Type TUploadState
	Field count:Int
	Field chunks:Int
	Field checksum:Int
End Type

Type TUploadHandler Implements IHTTPBodyHandler
	Method Begin(request:THTTPRequest, response:THTTPResponse)
		request.context = New TUploadState
	End Method

	Method Chunk(request:THTTPRequest, response:THTTPResponse, data:Byte[])
		Local state:TUploadState = TUploadState(request.context)
		state.count :+ data.length
		state.chunks :+ 1
		For Local value:Byte = EachIn data
			state.checksum = (state.checksum + (value & 255)) Mod 65521
		Next
	End Method

	Method Complete(request:THTTPRequest, response:THTTPResponse)
		Local state:TUploadState = TUploadState(request.context)
		response.Text(state.count + ":" + state.chunks + ":" + state.checksum)
	End Method

	Method Abort(request:THTTPRequest)
		uploadAborted :+ 1
		request.context = Null
	End Method
End Type

If AppArgs.length < 3 Then RuntimeError "expected port and document root"
Local config:THTTPServerConfig = New THTTPServerConfig
config.port = AppArgs[1].ToInt()
config.maxConnections = 2
config.maxRoutes = 24
config.keepAlive = True
config.keepAliveTimeoutMs = 500
config.maxRequestsPerConnection = 4
config.headerTimeoutMs = 300
config.bodyTimeoutMs = 300
config.maxStreamBodyBytes = 65536
Local server:THTTPServer = THTTPServer.Create(config)
If Not server Then RuntimeError "invalid server config"
If Not server.Route("GET", "/status", New TStatusHandler) Then RuntimeError "route failed"
If Not server.Route("POST", "/echo", New TEchoHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/gpio/:pin", New TParamHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/gpio/fixed", New TFixedHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/query", New TQueryHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/restart", New TRestartHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/throw", New TThrowHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/upload-aborts", New TAbortCountHandler) Then RuntimeError "route failed"
Local generated:TGeneratedHandler = New TGeneratedHandler
generated.count = 4097
If Not server.Route("GET", "/generated", generated) Then RuntimeError "route failed"
Local empty:TGeneratedHandler = New TGeneratedHandler
If Not server.Route("GET", "/empty-generated", empty) Then RuntimeError "route failed"
Local unknownFile:TUnknownFileHandler = New TUnknownFileHandler
unknownFile.path = AppArgs[2] + "/large.txt"
If Not server.Route("GET", "/unknown-file", unknownFile) Then RuntimeError "route failed"
If Not server.Route("GET", "/no-body-generated", New TNoBodyProducerHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/producer-closed", New TProducerClosedHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/producer-error", New TFailingProducerHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/events", New TEventsHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/events-send", New TEventsSendHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/events-finish", New TEventsFinishHandler) Then RuntimeError "route failed"
If Not server.Route("GET", "/events-state", New TEventsStateHandler) Then RuntimeError "route failed"
If Not server.RouteStream("POST", "/upload", New TUploadHandler) Then RuntimeError "stream route failed"
If Not server.RouteStream("PUT", "/upload", New TUploadHandler) Then RuntimeError "PUT stream route failed"
If Not server.Static("/assets/", AppArgs[2]) Then RuntimeError "static route failed"
If Not server.Static("/cached/", AppArgs[2], 60) Then RuntimeError "cached static route failed"
If Not server.Start() Then RuntimeError server.LastError()
server.Stop()
If Not server.Start() Then RuntimeError "restart failed: " + server.LastError()
server.Stop()
If Not server.Start() Then RuntimeError "second restart failed: " + server.LastError()
While True
	PollSystem()
	server.Service(8)
	If restartRequested And server.ActiveConnections() = 0 Then
		server.Stop()
		If Not server.Start() Then RuntimeError "restart after request failed: " + server.LastError()
		restartRequested = False
	End If
	Delay(1)
Wend
