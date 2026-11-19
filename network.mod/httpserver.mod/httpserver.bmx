' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Bounded, explicitly serviced HTTP server for embedded targets.
about: Call Service regularly on the managed application context. Connection
reuse is optional and bounded by the server configuration.
End Rem
Module Embedded.Network.HTTPServer
?not win32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Socket
Import BRL.Stream
Import BRL.FileSystem
Import BRL.System

Rem
bbdoc: Return value from a nonblocking producer when no data is ready yet.
End Rem
Const HTTPWouldBlock:Int = -2
Const HTTPStaticETagMaxBytes:Long = 65536

Rem
bbdoc: Resource and timeout limits copied when an HTTP server is created.
about: Set fields before THTTPServer.Create. The defaults favor small embedded
heaps; Create returns Null if a setting is outside its supported range.
End Rem
Type THTTPServerConfig
	Rem
	bbdoc: TCP port to bind; defaults to 8080.
	End Rem
	Field port:Int = 8080
	Rem
	bbdoc: Maximum simultaneous clients, including SSE and upgraded sessions.
	End Rem
	Field maxConnections:Int = 1
	Rem
	bbdoc: Maximum number of registered routes.
	End Rem
	Field maxRoutes:Int = 16
	Rem
	bbdoc: Maximum bytes accepted in a request line.
	End Rem
	Field maxRequestLine:Int = 256
	Rem
	bbdoc: Maximum bytes accepted in the request header block.
	End Rem
	Field maxHeaderBytes:Int = 1024
	Rem
	bbdoc: Maximum number of request header fields.
	End Rem
	Field maxHeaders:Int = 16
	Rem
	bbdoc: Maximum body bytes buffered for an ordinary Route handler.
	End Rem
	Field maxBodyBytes:Int = 1024
	Rem
	bbdoc: Maximum total upload bytes accepted by a RouteStream handler.
	End Rem
	Field maxStreamBodyBytes:Long = 1048576
	Rem
	bbdoc: Maximum byte-array body supplied by a response helper.
	End Rem
	Field maxResponseBodyBytes:Int = 1024
	Rem
	bbdoc: Transfer buffer size for streamed requests and responses.
	End Rem
	Field ioBufferBytes:Int = 512
	Rem
	bbdoc: Time allowed for request headers or an incomplete TLS handshake.
	End Rem
	Field headerTimeoutMs:UInt = 5000
	Rem
	bbdoc: Time allowed between received request-body data.
	End Rem
	Field bodyTimeoutMs:UInt = 10000
	Rem
	bbdoc: Time allowed without progress while writing a response.
	End Rem
	Field writeTimeoutMs:UInt = 10000
	Rem
	bbdoc: Enables bounded sequential HTTP/1.1 connection reuse.
	End Rem
	Field keepAlive:Int
	Rem
	bbdoc: Maximum idle time before a reusable connection closes.
	End Rem
	Field keepAliveTimeoutMs:UInt = 5000
	Rem
	bbdoc: Maximum requests served on one reusable connection.
	End Rem
	Field maxRequestsPerConnection:Int = 16

	Method Copy:THTTPServerConfig()
		Local result:THTTPServerConfig = New THTTPServerConfig
		result.port = port
		result.maxConnections = maxConnections
		result.maxRoutes = maxRoutes
		result.maxRequestLine = maxRequestLine
		result.maxHeaderBytes = maxHeaderBytes
		result.maxHeaders = maxHeaders
		result.maxBodyBytes = maxBodyBytes
		result.maxStreamBodyBytes = maxStreamBodyBytes
		result.maxResponseBodyBytes = maxResponseBodyBytes
		result.ioBufferBytes = ioBufferBytes
		result.headerTimeoutMs = headerTimeoutMs
		result.bodyTimeoutMs = bodyTimeoutMs
		result.writeTimeoutMs = writeTimeoutMs
		result.keepAlive = keepAlive
		result.keepAliveTimeoutMs = keepAliveTimeoutMs
		result.maxRequestsPerConnection = maxRequestsPerConnection
		Return result
	End Method
End Type

Rem
bbdoc: One name and value pair used for headers and route parameters.
End Rem
Type THTTPField
	Field name:String
	Field value:String
End Type

Rem
bbdoc: Request data passed to a route handler.
about: Headers are stored with lowercase names. The body field is populated
for buffered routes; streaming routes receive body chunks through
IHTTPBodyHandler. A streaming handler may use context for per-request state.
End Rem
Type THTTPRequest
	Field method:String
	Field path:String
	Field query:String
	Field version:String
	Field remoteIP:String
	Field body:Byte[]
	Field headers:THTTPField[]
	Field parameters:THTTPField[]
	Field context:Object

	Rem
	bbdoc: Returns a header value, or an empty string when absent.
	End Rem
	Method Header:String(name:String)
		For Local item:THTTPField = EachIn headers
			If item And item.name = name.ToLower() Then Return item.value
		Next
		Return ""
	End Method

	Rem
	bbdoc: Returns a named path parameter, or an empty string when absent.
	End Rem
	Method Parameter:String(name:String)
		For Local item:THTTPField = EachIn parameters
			If item And item.name = name Then Return item.value
		Next
		Return ""
	End Method

	Rem
	bbdoc: Decodes the first matching query value, or returns an empty string.
	End Rem
	Method QueryValue:String(name:String)
		For Local part:String = EachIn query.Split("&")
			Local equals:Int = part.Find("=")
			If equals < 0 Then equals = part.length
			If _HTTPDecode(part[..equals], True, False) = name Then
				If equals = part.length Then Return ""
				Return _HTTPDecode(part[equals + 1..], True, False)
			End If
		Next
		Return ""
	End Method

	Rem
	bbdoc: Decodes a buffered request body as UTF-8 text.
	End Rem
	Method BodyText:String()
		If Not body Or body.length = 0 Then Return ""
		Return String.FromUTF8Bytes(Varptr body[0], body.length)
	End Method
End Type

Rem
bbdoc: Response assembled by a route handler.
about: Use one body helper or stream source per response. The server owns and
closes a supplied stream or producer after the response or disconnection.
End Rem
Type THTTPResponse
	Field status:Int = 200
	Field contentType:String = "text/plain; charset=utf-8"
	Field body:Byte[]
	Field stream:TStream
	Field streamLength:Long = -1
	Field producer:IHTTPResponseProducer
	Field upgrade:IHTTPUpgradedSession
	Field headers:THTTPField[] = New THTTPField[8]
	Field headerCount:Int

	Rem
	bbdoc: Adds a response header, returning False if invalid or full.
	about: Content-Length, Connection, Transfer-Encoding and Content-Type are
	managed by the server and cannot be set here.
	End Rem
	Method SetHeader:Int(name:String, value:String)
		If headerCount = headers.length Or Not _HTTPToken(name) Or ..
			value.length > 256 Or value.Find(Chr(13)) >= 0 Or ..
			value.Find(Chr(10)) >= 0 Then Return False
		Select name.ToLower()
			Case "content-length", "connection", "transfer-encoding", "content-type"
				Return False
		End Select
		Local field:THTTPField = New THTTPField
		field.name = name
		field.value = value
		headers[headerCount] = field
		headerCount :+ 1
		Return True
	End Method

	Rem
	bbdoc: Sets a UTF-8 plain-text response body.
	End Rem
	Method Text(value:String)
		contentType = "text/plain; charset=utf-8"
		body = _HTTPBytes(value)
	End Method

	Rem
	bbdoc: Sets a UTF-8 HTML response body.
	End Rem
	Method Html(value:String)
		contentType = "text/html; charset=utf-8"
		body = _HTTPBytes(value)
	End Method

	Rem
	bbdoc: Sets a UTF-8 JSON response body.
	End Rem
	Method Json(value:String)
		contentType = "application/json; charset=utf-8"
		body = _HTTPBytes(value)
	End Method

	Rem
	bbdoc: Sets a byte-array response body and its MIME type.
	End Rem
	Method Bytes(value:Byte[], mime:String = "application/octet-stream")
		contentType = mime
		body = value
	End Method

	Rem
	bbdoc: Sets a redirect status and Location header with an empty body.
	End Rem
	Method Redirect(location:String, code:Int = 302)
		status = code
		SetHeader("Location", location)
		body = New Byte[0]
	End Method

	Rem
	bbdoc: Sends a known-length stream without buffering the full response.
	about: The server closes the stream after transfer or disconnection.
	End Rem
	Method StreamFile(value:TStream, size:Long, mime:String = "application/octet-stream")
		stream = value
		streamLength = size
		producer = Null
		body = Null
		contentType = mime
	End Method

	Rem
	bbdoc: Sends an unknown-length stream until Read returns zero.
	End Rem
	Method StreamUnknown(value:TStream, mime:String = "application/octet-stream")
		StreamFile(value, -1, mime)
	End Method

	Rem
	bbdoc: Sends bytes from a nonblocking producer until it reports completion.
	End Rem
	Method Produce(value:IHTTPResponseProducer, mime:String = "application/octet-stream")
		producer = value
		stream = Null
		streamLength = -1
		body = Null
		contentType = mime
	End Method

	Rem
	bbdoc: Sends a server-sent event stream with no cached response body.
	End Rem
	Method Events:Int(value:THTTPEventStream)
		If Not value Or Not SetHeader("Cache-Control", "no-cache") Then Return False
		Produce(value, "text/event-stream; charset=utf-8")
		Return True
	End Method

	Rem
	bbdoc: Transfers this response's connection to an upgraded protocol.
	End Rem
	Method Upgrade:Int(value:IHTTPUpgradedSession)
		If Not value Then Return False
		upgrade = value
		status = 101
		Return True
	End Method
End Type

Rem
bbdoc: Callback for a buffered HTTP route.
about: Handle runs from THTTPServer.Service and should return promptly.
End Rem
Interface IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
End Interface

Rem
bbdoc: Incremental request-body handler for a POST or PUT route.
about: Begin runs after headers. Chunk receives at most ioBufferBytes bytes,
and Complete runs after the declared Content-Length or the final chunk.
Callbacks run from Service.
End Rem
Interface IHTTPBodyHandler
	Rem
	bbdoc: Initializes per-request state after headers are accepted.
	End Rem
	Method Begin(request:THTTPRequest, response:THTTPResponse)
	Rem
	bbdoc: Receives at most ioBufferBytes of the request body per call.
	End Rem
	Method Chunk(request:THTTPRequest, response:THTTPResponse, data:Byte[])
	Rem
	bbdoc: Finishes a complete streamed request body.
	End Rem
	Method Complete(request:THTTPRequest, response:THTTPResponse)
	Rem
	bbdoc: Cleans up a body interrupted before Complete.
	End Rem
	Method Abort(request:THTTPRequest)
End Interface

Rem
bbdoc: Nonblocking source for an unknown-length response.
about: TryRead returns 1..capacity bytes, HTTPWouldBlock when no bytes are
ready yet, zero at EOF, or a negative value on failure. Close is called once
when the response finishes or its connection closes. Both methods run from
Service, so they must return promptly.
End Rem
Interface IHTTPResponseProducer
	Rem
	bbdoc: Provides available bytes without blocking the server loop.
	about: Return 1..capacity bytes, HTTPWouldBlock, zero for EOF, or a
	negative error value. The server calls this during Service.
	End Rem
	Method TryRead:Int(buffer:Byte Ptr, capacity:Int)
	Rem
	bbdoc: Releases resources after completion or disconnection.
	End Rem
	Method Close()
End Interface

Rem
bbdoc: Bounded, nonblocking server-sent event source for one HTTP client.
about: Keep a reference to this stream to queue events from the managed
application context. Send, Comment and Retry return False when the pending
buffer is full or the connection has closed. Finish drains queued bytes and
ends the response. The server calls Close on disconnect or completion.
End Rem
Type THTTPEventStream Implements IHTTPResponseProducer
	Private
	Field queue:Byte[]
	Field readIndex:Int
	Field writeIndex:Int
	Field pending:Int
	Field heartbeatMs:UInt
	Field lastOutput:UInt
	Field finished:Int
	Field closed:Int

	Method _Queue:Int(frame:String)
		If closed Or finished Then Return False
		If frame.length > queue.length Then Return False
		Local bytes:Byte[] = _HTTPBytes(frame)
		If bytes.length > queue.length - pending Then Return False
		For Local i:Int = 0 Until bytes.length
			queue[writeIndex] = bytes[i]
			writeIndex :+ 1
			If writeIndex = queue.length Then writeIndex = 0
		Next
		pending :+ bytes.length
		Return True
	End Method

	Public
	Rem
	bbdoc: Creates an event stream with a bounded queue and idle heartbeat.
	about: Returns Null if the queue size is outside 64..65536 bytes, the
	heartbeat is between 1 and 99 milliseconds, or allocation fails. Zero
	disables the heartbeat.
	End Rem
	Function Create:THTTPEventStream(maxPendingBytes:Int = 4096, heartbeatIntervalMs:UInt = 5000)
		If maxPendingBytes < 64 Or maxPendingBytes > 65536 Or ..
			(heartbeatIntervalMs > 0 And heartbeatIntervalMs < 100) Then Return Null
		Local result:THTTPEventStream
		Try
			result = New THTTPEventStream
			result.queue = New Byte[maxPendingBytes]
		Catch error:Object
			Return Null
		Catch error:String
			Return Null
		End Try
		result.heartbeatMs = heartbeatIntervalMs
		result.lastOutput = MilliSecs()
		Return result
	End Function

	Rem
	bbdoc: Queues one event. Line breaks in data become separate data fields.
	about: eventName and id must be single lines. The id is sent to clients on
	reconnect as Last-Event-ID, which the route can read from the request.
	End Rem
	Method Send:Int(data:String, eventName:String = "", id:String = "")
		If closed Or finished Then Return False
		If eventName.Find(Chr(0)) >= 0 Or eventName.Find(Chr(13)) >= 0 Or ..
			eventName.Find(Chr(10)) >= 0 Or id.Find(Chr(0)) >= 0 Or ..
			id.Find(Chr(13)) >= 0 Or id.Find(Chr(10)) >= 0 Then Return False
		Local frameLength:Int = data.length + 8
		If eventName Then frameLength :+ eventName.length + 8
		If id Then frameLength :+ id.length + 5
		For Local i:Int = 0 Until data.length
			If data[i] = 10 Or data[i] = 13 Then
				frameLength :+ 6
				If data[i] = 13 And i + 1 < data.length And data[i + 1] = 10 Then
					frameLength :- 1
					i :+ 1
				End If
			End If
			If frameLength > queue.length Then Return False
		Next
		If frameLength > queue.length Then Return False
		Local frame:String = ""
		If eventName Then frame :+ "event: " + eventName + "~n"
		If id Then frame :+ "id: " + id + "~n"
		Local start:Int
		For Local i:Int = 0 Until data.length
			If data[i] = 10 Or data[i] = 13 Then
				frame :+ "data: " + data[start..i] + "~n"
				If data[i] = 13 And i + 1 < data.length Then
					If data[i + 1] = 10 Then i :+ 1
				End If
				start = i + 1
			End If
		Next
		frame :+ "data: " + data[start..] + "~n"
		Return _Queue(frame + "~n")
	End Method

	Rem
	bbdoc: Queues a comment, which does not dispatch an event in the client.
	End Rem
	Method Comment:Int(value:String)
		If value.Find(Chr(0)) >= 0 Or value.Find(Chr(13)) >= 0 Or ..
			value.Find(Chr(10)) >= 0 Then Return False
		Return _Queue(": " + value + "~n~n")
	End Method

	Rem
	bbdoc: Advises the browser how long to wait before reconnecting.
	End Rem
	Method Retry:Int(milliseconds:Int)
		If milliseconds < 0 Then Return False
		Return _Queue("retry: " + milliseconds + "~n~n")
	End Method

	Rem
	bbdoc: Drains queued events and then ends the response.
	End Rem
	Method Finish()
		finished = True
	End Method

	Rem
	bbdoc: Reports whether this event stream has completed or disconnected.
	End Rem
	Method IsClosed:Int()
		Return closed
	End Method

	Rem
	bbdoc: Returns the number of event bytes still queued for sending.
	End Rem
	Method PendingBytes:Int()
		Return pending
	End Method

	Method TryRead:Int(buffer:Byte Ptr, capacity:Int)
		If closed Or Not buffer Or capacity <= 0 Then Return -1
		If pending > 0 Then
			Local count:Int = Min(capacity, pending)
			For Local i:Int = 0 Until count
				buffer[i] = queue[readIndex]
				readIndex :+ 1
				If readIndex = queue.length Then readIndex = 0
			Next
			pending :- count
			lastOutput = MilliSecs()
			Return count
		End If
		If finished Then Return 0
		If capacity >= 3 And heartbeatMs And MilliSecs() - lastOutput >= heartbeatMs Then
			buffer[0] = 58
			buffer[1] = 10
			buffer[2] = 10
			lastOutput = MilliSecs()
			Return 3
		End If
		Return HTTPWouldBlock
	End Method

	Method Close()
		closed = True
		finished = True
		pending = 0
		queue = Null
	End Method
End Type

Rem
bbdoc: Optional callback that builds an HTTP error response.
End Rem
Interface IHTTPErrorHandler
	Method HandleError(status:Int, response:THTTPResponse)
End Interface

Rem
bbdoc: Optional nonblocking connection transport for HTTP, including TLS.
End Rem
Interface IHTTPConnection
	Method TryRecv:Int(buffer:Byte Ptr, count:Size_T)
	Method TrySend:Int(buffer:Byte Ptr, count:Size_T)
	Method RemoteIP:String()
	Method Close()
End Interface

Rem
bbdoc: Transport view given to a protocol after an HTTP upgrade.
End Rem
Interface IHTTPUpgradedIO
	Method TryRecv:Int(buffer:Byte Ptr, count:Size_T)
	Method TrySend:Int(buffer:Byte Ptr, count:Size_T)
	Method RemoteIP:String()
End Interface

Rem
bbdoc: Optional protocol handler for an HTTP upgrade route.
End Rem
Interface IHTTPUpgradeHandler
	Rem
	bbdoc: Validates an upgrade request and prepares its response.
	End Rem
	Method HandleUpgrade(request:THTTPRequest, response:THTTPResponse)
End Interface

Rem
bbdoc: Nonblocking upgraded protocol serviced in the HTTP server loop.
about: Service returns False when the connection should close. Close runs once
when the socket closes. Service and Close run in the managed application context.
End Rem
Interface IHTTPUpgradedSession
	Rem
	bbdoc: Advances one upgraded connection; return False to close it.
	End Rem
	Method Service:Int(io:IHTTPUpgradedIO)
	Rem
	bbdoc: Releases the upgraded session after the socket closes.
	End Rem
	Method Close()
End Interface

Rem
bbdoc: Listener interface for an optional connection transport such as TLS.
End Rem
Interface IHTTPListener
	Method Start:Int(port:Int, backlog:Int)
	Method Accept:IHTTPConnection()
	Method Close()
	Method LastError:String()
End Interface

Private

Type THTTPRoute
	Field method:String
	Field path:String
	Field handler:IHTTPHandler
	Field bodyHandler:IHTTPBodyHandler
	Field upgradeHandler:IHTTPUpgradeHandler
	Field staticRoot:String
	Field cacheMaxAgeSeconds:Int
End Type

Type THTTPConnection
	Field socket:TSocket
	Field transport:IHTTPConnection
	Field input:Byte[]
	Field inputCount:Int
	Field headerEnd:Int = -1
	Field expectedBody:Long
	Field receivedBody:Long
	Field bodyHandler:IHTTPBodyHandler
	Field streamComplete:Int
	Field started:UInt
	Field lastActivity:UInt
	Field output:Byte[]
	Field outputOffset:Int
	Field response:THTTPResponse
	Field upgrade:IHTTPUpgradedSession
	Field upgradeIO:THTTPUpgradeIO
	Field request:THTTPRequest
	Field streamRemaining:Long
	Field responseChunked:Int
	Field responseCloseDelimited:Int
	Field chunkFinal:Int
	Field fileBuffer:Byte[]
	Field fileCount:Int
	Field fileOffset:Int
	Field state:Int ' 0 reading, 1 sending headers/body, 2 sending stream
	Field closeAfterResponse:Int = True
	Field requestsServed:Int
	Field chunked:Int
	Field chunkState:Int ' 0 size, 1 data, 2 data CRLF, 3 trailers
	Field chunkRemaining:Long
	Field trailerBytes:Int
	Field trailerCount:Int
End Type

Type THTTPUpgradeIO Implements IHTTPUpgradedIO
	Field socket:TSocket
	Field transport:IHTTPConnection
	Field buffered:Byte[]
	Field offset:Int

	Method TryRecv:Int(buffer:Byte Ptr, count:Size_T)
		If buffered And offset < buffered.length Then
			Local amount:Int = Min(Int(count), buffered.length - offset)
			For Local i:Int = 0 Until amount
				buffer[i] = buffered[offset + i]
			Next
			offset :+ amount
			If offset = buffered.length Then buffered = Null
			Return amount
		End If
		If transport Then Return transport.TryRecv(buffer, count)
		Return socket.TryRecv(buffer, count)
	End Method

	Method TrySend:Int(buffer:Byte Ptr, count:Size_T)
		If transport Then Return transport.TrySend(buffer, count)
		Return socket.TrySend(buffer, count)
	End Method

	Method RemoteIP:String()
		If transport Then Return transport.RemoteIP()
		Return socket.RemoteIp()
	End Method
End Type

Function _HTTPBytes:Byte[](value:String)
	Local count:Size_T
	Local ptr:Byte Ptr = value.ToUTF8String(count)
	Local result:Byte[] = New Byte[Int(count)]
	For Local i:Int = 0 Until result.length
		result[i] = ptr[i]
	Next
	If ptr Then MemFree(ptr)
	Return result
End Function

Function _HTTPToken:Int(value:String)
	If value.length = 0 Then Return False
	For Local i:Int = 0 Until value.length
		Local c:Int = value[i]
		If Not ((c >= 48 And c <= 57) Or (c >= 65 And c <= 90) Or ..
			(c >= 97 And c <= 122) Or c = 45) Then Return False
	Next
	Return True
End Function

Function _HTTPHex:Int(c:Int)
	If c >= 48 And c <= 57 Then Return c - 48
	If c >= 65 And c <= 70 Then Return c - 55
	If c >= 97 And c <= 102 Then Return c - 87
	Return -1
End Function

Function _HTTPChunkSize:String(size:Int)
	Local digits:String = "0123456789abcdef"
	Local result:String = ""
	Repeat
		result = Chr(digits[size & 15]) + result
		size = size Shr 4
	Until size = 0
	Return result
End Function

Function _HTTPDecode:String(value:String, plusAsSpace:Int = False, rejectSeparators:Int = True)
	Local bytes:Byte[] = New Byte[value.length]
	Local count:Int
	For Local i:Int = 0 Until value.length
		Local c:Int = value[i]
		If c = 37
			If i + 2 >= value.length Then Return Null
			Local high:Int = _HTTPHex(value[i + 1])
			Local low:Int = _HTTPHex(value[i + 2])
			If high < 0 Or low < 0 Then Return Null
			c = high * 16 + low
			i :+ 2
			If rejectSeparators And (c = 47 Or c = 92) Then Return Null
		Else If c = 43 And plusAsSpace
			c = 32
		End If
		If c = 0 Or c = 92 Or c < 32 Or c > 127 Then Return Null
		bytes[count] = Byte(c)
		count :+ 1
	Next
	If count = 0 Then Return ""
	Return String.FromUTF8Bytes(Varptr bytes[0], count)
End Function

Function _HTTPReason:String(status:Int)
	Select status
		Case 200 Return "OK"
		Case 201 Return "Created"
		Case 204 Return "No Content"
		Case 205 Return "Reset Content"
		Case 206 Return "Partial Content"
		Case 301 Return "Moved Permanently"
		Case 302 Return "Found"
		Case 304 Return "Not Modified"
		Case 303 Return "See Other"
		Case 307 Return "Temporary Redirect"
		Case 308 Return "Permanent Redirect"
		Case 400 Return "Bad Request"
		Case 403 Return "Forbidden"
		Case 404 Return "Not Found"
		Case 405 Return "Method Not Allowed"
		Case 426 Return "Upgrade Required"
		Case 408 Return "Request Timeout"
		Case 411 Return "Length Required"
		Case 413 Return "Content Too Large"
		Case 416 Return "Range Not Satisfiable"
		Case 414 Return "URI Too Long"
		Case 417 Return "Expectation Failed"
		Case 431 Return "Request Header Fields Too Large"
		Case 500 Return "Internal Server Error"
		Case 501 Return "Not Implemented"
		Case 503 Return "Service Unavailable"
	End Select
	Return "Response"
End Function

Function _HTTPMime:String(path:String)
	Local dot:Int = path.FindLast(".")
	If dot < 0 Then Return "application/octet-stream"
	Select path[dot + 1..].ToLower()
		Case "html", "htm" Return "text/html; charset=utf-8"
		Case "css" Return "text/css; charset=utf-8"
		Case "js" Return "text/javascript; charset=utf-8"
		Case "json" Return "application/json; charset=utf-8"
		Case "txt" Return "text/plain; charset=utf-8"
		Case "svg" Return "image/svg+xml"
		Case "png" Return "image/png"
		Case "jpg", "jpeg" Return "image/jpeg"
		Case "gif" Return "image/gif"
		Case "ico" Return "image/x-icon"
		Case "wasm" Return "application/wasm"
	End Select
	Return "application/octet-stream"
End Function

Function _HTTPUnsignedLong:Int(value:String, number:Long Var)
	If value.length = 0 Then Return False
	number = 0
	For Local i:Int = 0 Until value.length
		Local digit:Int = value[i] - 48
		If digit < 0 Or digit > 9 Then Return False
		If number > ($7fffffffffffffff:Long - digit) / 10 Then Return False
		number = number * 10 + digit
	Next
	Return True
End Function

' Returns 0 for an unsupported/malformed range, 1 for a single range, or 2
' for a syntactically valid but unsatisfiable single range.
Function _HTTPByteRange:Int(value:String, size:Long, start:Long Var, length:Long Var)
	If Not value.ToLower().StartsWith("bytes=") Then Return 0
	Local spec:String = value[6..].Trim()
	If spec.Find(",") >= 0 Then Return 0
	Local dash:Int = spec.Find("-")
	If dash < 0 Or spec.Find("-", dash + 1) >= 0 Then Return 0
	Local first:String = spec[..dash]
	Local last:String = spec[dash + 1..]
	If first.length = 0
		Local suffix:Long
		If Not _HTTPUnsignedLong(last, suffix) Then Return 0
		If suffix = 0 Or size = 0 Then Return 2
		start = Max(0:Long, size - suffix)
		length = size - start
		Return 1
	End If
	If Not _HTTPUnsignedLong(first, start) Then Return 0
	If last.length
		Local finish:Long
		If Not _HTTPUnsignedLong(last, finish) Then Return 0
		If finish < start Then Return 2
		If start >= size Then Return 2
		length = Min(finish, size - 1) - start + 1
	Else
		If start >= size Then Return 2
		length = size - start
	End If
	Return 1
End Function

Function _HTTPFileTag:String(path:String, size:Long)
	If size < 0 Or size > HTTPStaticETagMaxBytes Then Return ""
	Local source:TStream = ReadStream(path)
	If Not source Then Return ""
	Local hash:ULong = $cbf29ce484222325:ULong
	Local buffer:Byte[] = New Byte[512]
	Local remaining:Long = size
	Local valid:Int = True
	Try
		While remaining > 0
			Local count:Int = Int(source.Read(Varptr buffer[0], Min(remaining, Long(buffer.length))))
			If count <= 0 Or count > remaining Then valid = False; Exit
			For Local i:Int = 0 Until count
				hash :~ ULong(buffer[i] & 255)
				hash = hash * 1099511628211:ULong
			Next
			remaining :- count
		Wend
		Local extra:Byte
		If valid And source.Read(Varptr extra, 1) <> 0 Then valid = False
	Catch failure:Object
		valid = False
	Catch failure:String
		valid = False
	End Try
	Try
		source.Close()
	Catch failure:Object
		valid = False
	Catch failure:String
		valid = False
	End Try
	If Not valid Then Return ""
	Return "W/~q" + size + "-" + String.FromULong(hash) + "~q"
End Function

Function _HTTPTagMatches:Int(value:String, tag:String)
	If Not value Then Return False
	For Local candidate:String = EachIn value.Split(",")
		Local trimmed:String = candidate.Trim()
		If trimmed = "*" Then Return True
		If tag And (trimmed = tag Or trimmed = tag[2..]) Then Return True
	Next
	Return False
End Function

Public

Rem
bbdoc: Bounded HTTP server serviced by the managed application loop.
about: Register routes before Start, then call Service frequently. Stop closes
active connections and permits a later Start.
End Rem
Type THTTPServer
	Private
	Field config:THTTPServerConfig
	Field listener:TSocket
	Field secureListener:IHTTPListener
	Field running:Int
	Field routes:THTTPRoute[]
	Field routeCount:Int
	Field connections:THTTPConnection[]
	Field errorHandler:IHTTPErrorHandler
	Field _lastError:String

	Public
	Rem
	bbdoc: Creates a server with copied settings and an optional transport.
	about: Returns Null for invalid limits or allocation failure. Pass an
	HTTPSTLS listener as transport to serve HTTPS.
	End Rem
	Function Create:THTTPServer(settings:THTTPServerConfig = Null, transport:IHTTPListener = Null)
		If Not settings Then settings = New THTTPServerConfig
		If settings.maxConnections < 1 Or settings.maxConnections > 4 Or ..
			settings.port < 0 Or settings.port > 65535 Or ..
			settings.maxRoutes < 1 Or settings.maxRoutes > 64 Or ..
			settings.maxHeaderBytes < 128 Or ..
			settings.maxHeaderBytes > 4096 Or settings.maxBodyBytes < 0 Or ..
				settings.maxBodyBytes > 8192 Or ..
				settings.maxStreamBodyBytes < 0 Or ..
				settings.maxStreamBodyBytes > 67108864 Or ..
				settings.maxResponseBodyBytes < 0 Or ..
			settings.maxResponseBodyBytes > 8192 Or ..
			settings.ioBufferBytes < 64 Or settings.ioBufferBytes > 2048 Or ..
			settings.maxHeaders < 1 Or settings.maxHeaders > 32 Or ..
			settings.maxRequestLine < 16 Or ..
			settings.maxRequestLine > settings.maxHeaderBytes Or ..
			settings.maxRequestsPerConnection < 1 Or ..
			settings.maxRequestsPerConnection > 1000 Or ..
			settings.keepAliveTimeoutMs < 100 Or ..
			settings.keepAliveTimeoutMs > 60000 Then Return Null
		Local server:THTTPServer
		Try
			server = New THTTPServer
			server.config = settings.Copy()
			server.secureListener = transport
			server.routes = New THTTPRoute[settings.maxRoutes]
			server.connections = New THTTPConnection[settings.maxConnections]
		Catch error:Object
			Return Null
		Catch error:String
			Return Null
		End Try
		Return server
	End Function

	Rem
	bbdoc: Registers a buffered route before the server starts.
	about: Paths may contain named :parameters. Returns False for invalid
	arguments, a full route table, or registration after Start.
	End Rem
	Method Route:Int(method:String, path:String, handler:IHTTPHandler)
		If running Or routeCount = routes.length Or Not handler Or ..
			Not _HTTPToken(method) Or Not path.StartsWith("/") Then Return False
		Local route:THTTPRoute = New THTTPRoute
		route.method = method.ToUpper()
		route.path = path
		route.handler = handler
		routes[routeCount] = route
		routeCount :+ 1
		Return True
	End Method

	Rem
	bbdoc: Registers a GET route for an optional HTTP upgrade protocol.
	End Rem
	Method RouteUpgrade:Int(path:String, handler:IHTTPUpgradeHandler)
		If running Or routeCount = routes.length Or Not handler Or ..
			Not path.StartsWith("/") Then Return False
		Local route:THTTPRoute = New THTTPRoute
		route.method = "GET"
		route.path = path
		route.upgradeHandler = handler
		routes[routeCount] = route
		routeCount :+ 1
		Return True
	End Method

	Rem
	bbdoc: Registers a POST or PUT route that receives bounded body chunks.
	End Rem
	Method RouteStream:Int(method:String, path:String, handler:IHTTPBodyHandler)
		If running Or routeCount = routes.length Or Not handler Or ..
			(method <> "POST" And method <> "PUT") Or Not path.StartsWith("/") Then Return False
		Local route:THTTPRoute = New THTTPRoute
		route.method = method
		route.path = path
		route.bodyHandler = handler
		routes[routeCount] = route
		routeCount :+ 1
		Return True
	End Method

	Rem
	bbdoc: Maps a URL prefix ending in / to a mounted file directory.
	about: Optional cacheMaxAgeSeconds sets a public cache lifetime. Register
	static routes before Start and after mounting their storage.
	End Rem
	Method Static:Int(prefix:String, root:String, cacheMaxAgeSeconds:Int = 0)
		If running Or routeCount = routes.length Or Not prefix.StartsWith("/") Or ..
			Not prefix.EndsWith("/") Or root.length = 0 Or ..
			cacheMaxAgeSeconds < 0 Or cacheMaxAgeSeconds > 31536000 Then Return False
		Local route:THTTPRoute = New THTTPRoute
		route.method = "GET"
		route.path = prefix
		route.staticRoot = root
		route.cacheMaxAgeSeconds = cacheMaxAgeSeconds
		routes[routeCount] = route
		routeCount :+ 1
		Return True
	End Method

	Rem
	bbdoc: Sets the callback used to prepare HTTP error responses.
	End Rem
	Method OnError(handler:IHTTPErrorHandler)
		errorHandler = handler
	End Method

	Rem
	bbdoc: Returns the latest server or route failure detail.
	End Rem
	Method LastError:String()
		Return _lastError
	End Method

	Rem
	bbdoc: Returns the number of currently occupied connection slots.
	End Rem
	Method ActiveConnections:Int()
		Local count:Int
		For Local conn:THTTPConnection = EachIn connections
			If conn Then count :+ 1
		Next
		Return count
	End Method

	Rem
	bbdoc: Starts listening, returning False on failure.
	about: Call LastError for the failure detail. Repeated calls while already
	running succeed.
	End Rem
	Method Start:Int()
		If running Then Return True
		If secureListener Then
			If Not secureListener.Start(config.port, config.maxConnections) Then
				_lastError = secureListener.LastError()
				Return False
			End If
			running = True
			Return True
		End If
		listener = TSocket.CreateTCP()
		If Not listener Then _lastError = "socket creation failed"; Return False
		listener.SetSockOpt(SOL_SOCKET, SO_REUSEADDR, True)
		If Not listener.Bind(config.port) Or Not listener.Listen(config.maxConnections) Then
			_lastError = "socket bind or listen failed"
			listener.Close()
			listener = Null
			Return False
		End If
		running = True
		Return True
	End Method

	Rem
	bbdoc: Closes the listener and all active connections.
	End Rem
	Method Stop()
		For Local i:Int = 0 Until connections.length
			_Close(i)
		Next
		If listener Then listener.Close()
		listener = Null
		If secureListener Then secureListener.Close()
		running = False
	End Method

	Private
	Method _TryRecv:Int(conn:THTTPConnection, buffer:Byte Ptr, count:Size_T)
		If conn.transport Then Return conn.transport.TryRecv(buffer, count)
		Return conn.socket.TryRecv(buffer, count)
	End Method

	Method _TrySend:Int(conn:THTTPConnection, buffer:Byte Ptr, count:Size_T)
		If conn.transport Then Return conn.transport.TrySend(buffer, count)
		Return conn.socket.TrySend(buffer, count)
	End Method

	Method _Close(index:Int)
			Local conn:THTTPConnection = connections[index]
			If Not conn Then Return
			If conn.bodyHandler And Not conn.streamComplete Then
				Try
					conn.bodyHandler.Abort(conn.request)
				Catch error:Object
					_lastError = "HTTP stream abort handler failed"
				Catch error:String
					_lastError = "HTTP stream abort handler failed: " + error
				End Try
			End If
		If conn.response And conn.response.stream Then
			Try
				conn.response.stream.Close()
			Catch error:Object
			Catch error:String
			End Try
		End If
		If conn.response And conn.response.producer Then
			Try
				conn.response.producer.Close()
			Catch error:Object
			Catch error:String
			End Try
			conn.response.producer = Null
		End If
		If conn.upgrade Then
			Try
				conn.upgrade.Close()
			Catch error:Object
				_lastError = "HTTP upgraded session close failed"
			Catch error:String
				_lastError = "HTTP upgraded session close failed: " + error
			End Try
			conn.upgrade = Null
		End If
		If conn.transport Then conn.transport.Close()
		If conn.socket Then conn.socket.Close()
		connections[index] = Null
	End Method

		Method _Fail(conn:THTTPConnection, status:Int)
			conn.closeAfterResponse = True
			If conn.response And conn.response.stream Then
				Try
					conn.response.stream.Close()
				Catch error:Object
				Catch error:String
				End Try
			End If
			If conn.response And conn.response.producer Then
				Try
					conn.response.producer.Close()
				Catch error:Object
				Catch error:String
				End Try
				conn.response.producer = Null
			End If
			conn.response = New THTTPResponse
			conn.response.status = status
			conn.response.Text(_HTTPReason(status))
			If errorHandler Then
				Try
					errorHandler.HandleError(status, conn.response)
				Catch error:Object
					_lastError = "error handler failed for HTTP " + status
					conn.response = New THTTPResponse
					conn.response.status = status
					conn.response.Text(_HTTPReason(status))
				Catch error:String
					_lastError = "error handler failed for HTTP " + status + ": " + error
					conn.response = New THTTPResponse
					conn.response.status = status
					conn.response.Text(_HTTPReason(status))
				End Try
			End If
			_Prepare(conn)
		End Method

		Method _HandlerFault(conn:THTTPConnection, detail:String)
			_lastError = "HTTP handler failed on " + conn.request.method + " " + conn.request.path + ": " + detail
			_Fail(conn, 500)
		End Method

	Method _Prepare(conn:THTTPConnection)
		Local response:THTTPResponse = conn.response
		If response.upgrade And response.status = 101 And conn.request.version = "HTTP/1.1" Then
			Local wire:String = "HTTP/1.1 101 Switching Protocols~r~nConnection: Upgrade~r~n"
			For Local i:Int = 0 Until response.headerCount
				Local field:THTTPField = response.headers[i]
				wire :+ field.name + ": " + field.value + "~r~n"
			Next
			wire :+ "~r~n"
			conn.output = _HTTPBytes(wire)
			conn.outputOffset = 0
			conn.upgrade = response.upgrade
			conn.upgradeIO = New THTTPUpgradeIO
			conn.upgradeIO.socket = conn.socket
			conn.upgradeIO.transport = conn.transport
			If conn.inputCount > conn.headerEnd Then
				conn.upgradeIO.buffered = New Byte[conn.inputCount - conn.headerEnd]
				For Local i:Int = 0 Until conn.upgradeIO.buffered.length
					conn.upgradeIO.buffered[i] = conn.input[conn.headerEnd + i]
				Next
			End If
			conn.lastActivity = MilliSecs()
			conn.state = 5
			Return
		End If
		If response.status < 200 Or response.status > 599 Then response.status = 500
		If response.contentType.length > 128 Or ..
			response.contentType.Find(Chr(13)) >= 0 Or ..
			response.contentType.Find(Chr(10)) >= 0 Then
			response.contentType = "application/octet-stream"
		End If
		Local length:Long
		Local unknown:Int
		If response.producer
			unknown = True
		Else If response.stream
			length = response.streamLength
			If length = -1 Then unknown = True
			If length < -1 Then response.stream.Close(); response.stream = Null; response.status = 500
		Else If response.body
			length = response.body.length
			If length > config.maxResponseBodyBytes Then
				response.status = 500
				response.body = Null
				length = 0
			End If
		End If
		If response.status = 204 Or response.status = 205 Or response.status = 304 Then
			length = 0
			unknown = False
		End If
		Local version:String = "HTTP/1.1"
		If conn.request Then version = conn.request.version
		conn.responseChunked = unknown And version = "HTTP/1.1"
		conn.responseCloseDelimited = unknown And version = "HTTP/1.0"
		conn.chunkFinal = False
		If conn.responseCloseDelimited Then conn.closeAfterResponse = True
		Local connectionValue:String = "close"
		If Not conn.closeAfterResponse Then connectionValue = "keep-alive"
		Local wire:String = version + " " + response.status + " " + _HTTPReason(response.status) + "~r~n" + ..
			"Connection: " + connectionValue + "~r~nContent-Type: " + response.contentType + "~r~n"
		If conn.responseChunked Then
			wire :+ "Transfer-Encoding: chunked~r~n"
		Else If Not conn.responseCloseDelimited Then
			wire :+ "Content-Length: " + length + "~r~n"
		End If
		For Local i:Int = 0 Until response.headerCount
			Local field:THTTPField = response.headers[i]
			If field.name.ToLower() <> "content-length" And ..
				field.name.ToLower() <> "connection" Then
				wire :+ field.name + ": " + field.value + "~r~n"
			End If
		Next
		wire :+ "~r~n"
		conn.output = _HTTPBytes(wire)
		conn.outputOffset = 0
		conn.streamRemaining = length
		conn.lastActivity = MilliSecs()
		conn.state = 1
	End Method

	Method _StaticFile(request:THTTPRequest, response:THTTPResponse, route:THTTPRoute)
		Local suffix:String = request.path[route.path.length..]
		For Local part:String = EachIn suffix.Split("/")
			If part = ".." Or part = "." Then response.status = 403; Return
		Next
		If suffix.length = 0 Or suffix.EndsWith("/") Then suffix :+ "index.html"
		Local path:String = route.staticRoot
		If Not path.EndsWith("/") Then path :+ "/"
		path :+ suffix
		Local info:SFileStat
		If Not FileStat(path, info) Or Not info.IsFile() Then response.status = 404; Return
		response.SetHeader("Accept-Ranges", "bytes")
		If route.cacheMaxAgeSeconds > 0 Then
			response.SetHeader("Cache-Control", "public, max-age=" + route.cacheMaxAgeSeconds)
		End If
		Local tag:String = _HTTPFileTag(path, info.size)
		If tag Then response.SetHeader("ETag", tag)
		If _HTTPTagMatches(request.Header("If-None-Match"), tag) Then
			response.status = 304
			Return
		End If
		Local start:Long
		Local length:Long = info.size
		If Not request.Header("If-Range") Then
			Select _HTTPByteRange(request.Header("Range"), info.size, start, length)
				Case 1
					response.status = 206
					response.SetHeader("Content-Range", "bytes " + start + "-" + (start + length - 1) + "/" + info.size)
				Case 2
					response.status = 416
					response.SetHeader("Content-Range", "bytes */" + info.size)
					response.body = New Byte[0]
					Return
			End Select
		End If
		Local stream:TStream = ReadStream(path)
		If Not stream Then response.status = 404; Return
		If start > 0 And stream.Seek(start) <> start Then
			stream.Close()
			response.status = 500
			Return
		End If
		response.StreamFile(stream, length, _HTTPMime(path))
	End Method

	Method _Dispatch(conn:THTTPConnection)
		Local request:THTTPRequest = conn.request
		Local response:THTTPResponse = New THTTPResponse
		conn.response = response
		If request.method <> "GET" And request.method <> "HEAD" And ..
			request.method <> "POST" And request.method <> "PUT" Then
			_Fail(conn, 501)
			Return
		End If
		Local matchedPath:Int
		Local allow:String
		For Local pass:Int = 0 To 2
			For Local i:Int = 0 Until routeCount
				Local route:THTTPRoute = routes[i]
				If pass = 0 And (route.staticRoot <> "" Or route.path.Find(":") >= 0) Then Continue
				If pass = 1 And (route.staticRoot <> "" Or route.path.Find(":") < 0) Then Continue
				If pass = 2 And route.staticRoot = "" Then Continue
				Local params:THTTPField[] = _Match(route.path, request.path, route.staticRoot <> "")
				If params = Null Then Continue
				matchedPath = True
				If allow.Find(route.method) < 0 Then
					If allow.length Then allow :+ ", "
					allow :+ route.method
					If route.method = "GET" Then allow :+ ", HEAD"
				End If
				If route.method <> request.method And ..
					Not (request.method = "HEAD" And route.method = "GET") Then Continue
				request.parameters = params
				If route.upgradeHandler Then
					Try
						route.upgradeHandler.HandleUpgrade(request, response)
					Catch error:Object
						_HandlerFault(conn, "upgrade handler exception")
						Return
					Catch error:String
						_HandlerFault(conn, error)
						Return
					End Try
				Else If route.staticRoot <> "" Then
					Try
						_StaticFile(request, response, route)
					Catch error:Object
						_HandlerFault(conn, "static file exception")
						Return
					Catch error:String
						_HandlerFault(conn, error)
						Return
					End Try
					If response.status >= 400 And response.status <> 416 Then _Fail(conn, response.status); Return
				Else
						Try
							route.handler.Handle(request, response)
						Catch error:Object
							_HandlerFault(conn, "object exception")
							Return
						Catch error:String
							_HandlerFault(conn, error)
							Return
						End Try
				End If
				_Prepare(conn)
				Return
			Next
		Next
		If matchedPath
			response.status = 405
			response.Text(_HTTPReason(405))
			response.SetHeader("Allow", allow)
			If errorHandler Then
				Try
					errorHandler.HandleError(405, response)
				Catch error:Object
					_lastError = "error handler failed for HTTP 405"
					response = New THTTPResponse
					response.status = 405
					response.Text(_HTTPReason(405))
					response.SetHeader("Allow", allow)
					conn.response = response
				Catch error:String
					_lastError = "error handler failed for HTTP 405: " + error
					response = New THTTPResponse
					response.status = 405
					response.Text(_HTTPReason(405))
					response.SetHeader("Allow", allow)
					conn.response = response
				End Try
			End If
			_Prepare(conn)
		Else
			_Fail(conn, 404)
		End If
	End Method

	Method _Parse(conn:THTTPConnection)
		Local lineEnd:Int = -1
		For Local i:Int = 0 Until conn.headerEnd - 1
			If conn.input[i] = 13 And conn.input[i + 1] = 10 Then lineEnd = i; Exit
		Next
		If lineEnd < 0 Or lineEnd > config.maxRequestLine Then _Fail(conn, 414); Return
		For Local i:Int = 0 Until lineEnd
			If conn.input[i] < 32 Or conn.input[i] > 126 Then _Fail(conn, 400); Return
		Next
		Local line:String = String.FromUTF8Bytes(Varptr conn.input[0], lineEnd)
		Local parts:String[] = line.Split(" ")
		If parts.length <> 3 Or Not _HTTPToken(parts[0]) Or ..
			(parts[2] <> "HTTP/1.0" And parts[2] <> "HTTP/1.1") Then _Fail(conn, 400); Return
		If Not parts[1].StartsWith("/") Then _Fail(conn, 400); Return
		Local question:Int = parts[1].Find("?")
		Local rawPath:String = parts[1]
		Local query:String = ""
		If question >= 0 Then rawPath = parts[1][..question]; query = parts[1][question + 1..]
		Local path:String = _HTTPDecode(rawPath)
		If path = Null Then _Fail(conn, 400); Return
		If query.length And _HTTPDecode(query, True, False) = Null Then _Fail(conn, 400); Return
		Local request:THTTPRequest = New THTTPRequest
		request.method = parts[0]
		request.path = path
		request.query = query
		request.version = parts[2]
		If conn.transport Then
			request.remoteIP = conn.transport.RemoteIP()
		Else
			request.remoteIP = conn.socket.RemoteIp()
		End If
		request.headers = New THTTPField[config.maxHeaders]
		Local headerCount:Int
		Local host:Int
		Local lengthSeen:Int
		Local transferEncoding:Int
		Local connectionClose:Int
		Local pos:Int = lineEnd + 2
		While pos < conn.headerEnd - 2
			Local finish:Int = -1
			For Local i:Int = pos Until conn.headerEnd - 1
				If conn.input[i] = 13 And conn.input[i + 1] = 10 Then finish = i; Exit
			Next
			If finish < 0 Or headerCount = config.maxHeaders Then _Fail(conn, 431); Return
			For Local i:Int = pos Until finish
				If (conn.input[i] < 32 And conn.input[i] <> 9) Or ..
					conn.input[i] > 126 Then _Fail(conn, 400); Return
			Next
			Local raw:String = String.FromUTF8Bytes(Varptr conn.input[pos], finish - pos)
			Local colon:Int = raw.Find(":")
			If colon <= 0 Or Not _HTTPToken(raw[..colon]) Then _Fail(conn, 400); Return
			Local name:String = raw[..colon].ToLower()
			Local value:String = raw[colon + 1..].Trim()
			If value.Find(Chr(13)) >= 0 Or value.Find(Chr(10)) >= 0 Then _Fail(conn, 400); Return
			Local field:THTTPField = New THTTPField
			field.name = name
			field.value = value
			request.headers[headerCount] = field
			headerCount :+ 1
			Select name
				Case "host"
					If value.length = 0 Then _Fail(conn, 400); Return
					host :+ 1
				Case "content-length"
					If lengthSeen Or value.length = 0 Then _Fail(conn, 400); Return
					lengthSeen = True
					Local total:Long
					Local maximum:Long = Max(Long(config.maxBodyBytes), config.maxStreamBodyBytes)
					For Local j:Int = 0 Until value.length
						If value[j] < 48 Or value[j] > 57 Then _Fail(conn, 400); Return
						If total > maximum / 10 Then _Fail(conn, 413); Return
						total = total * 10 + value[j] - 48
						If total > maximum Then _Fail(conn, 413); Return
					Next
					conn.expectedBody = total
				Case "transfer-encoding"
					If transferEncoding Or value.ToLower() <> "chunked" Then _Fail(conn, 501); Return
					transferEncoding = True
				Case "connection"
					For Local token:String = EachIn value.ToLower().Split(",")
						If token.Trim() = "close" Then connectionClose = True
					Next
				Case "expect" _Fail(conn, 417); Return
			End Select
			pos = finish + 2
		Wend
		If transferEncoding Then
			If lengthSeen Then _Fail(conn, 400); Return
			If request.version <> "HTTP/1.1" Then _Fail(conn, 400); Return
		End If
		If request.version = "HTTP/1.1" And host <> 1 Then _Fail(conn, 400); Return
		If (request.method = "POST" Or request.method = "PUT") And ..
			Not lengthSeen And Not transferEncoding Then _Fail(conn, 411); Return
		conn.request = request
		conn.chunked = transferEncoding
		conn.closeAfterResponse = Not (config.keepAlive And request.version = "HTTP/1.1" And ..
			Not connectionClose And conn.requestsServed + 1 < config.maxRequestsPerConnection)
		If request.method = "GET" Then
			For Local i:Int = 0 Until routeCount
				Local route:THTTPRoute = routes[i]
				If route.upgradeHandler And _Match(route.path, request.path, False) <> Null Then
					If lengthSeen Or transferEncoding Then _Fail(conn, 400); Return
					Exit
				End If
			Next
		End If
		For Local pass:Int = 0 To 1
			For Local i:Int = 0 Until routeCount
				Local route:THTTPRoute = routes[i]
				If Not route.bodyHandler Or route.method <> request.method Then Continue
				If pass = 0 And route.path.Find(":") >= 0 Then Continue
				If pass = 1 And route.path.Find(":") < 0 Then Continue
				Local params:THTTPField[] = _Match(route.path, request.path, False)
				If params = Null Then Continue
				If Not transferEncoding And conn.expectedBody > config.maxStreamBodyBytes Then _Fail(conn, 413); Return
				request.parameters = params
				conn.bodyHandler = route.bodyHandler
				conn.response = New THTTPResponse
				Try
					conn.bodyHandler.Begin(request, conn.response)
				Catch error:Object
					_HandlerFault(conn, "object exception in stream Begin")
					Return
				Catch error:String
					_HandlerFault(conn, error)
					Return
				End Try
				If conn.expectedBody = 0 And Not transferEncoding
					If conn.inputCount > conn.headerEnd Then conn.closeAfterResponse = True
					_CompleteStream(conn)
				End If
				Return
			Next
		Next
		If Not transferEncoding And conn.expectedBody > config.maxBodyBytes Then _Fail(conn, 413); Return
		If transferEncoding
			request.body = New Byte[config.maxBodyBytes]
		Else If conn.expectedBody = 0
			If conn.inputCount > conn.headerEnd Then conn.closeAfterResponse = True
			_Dispatch(conn)
		End If
	End Method

	Method _CompleteStream(conn:THTTPConnection)
		Try
			conn.bodyHandler.Complete(conn.request, conn.response)
		Catch error:Object
			_HandlerFault(conn, "object exception in stream Complete")
			Return
		Catch error:String
			_HandlerFault(conn, error)
			Return
		End Try
		conn.streamComplete = True
		_Prepare(conn)
	End Method

	Method _ConsumeStream(conn:THTTPConnection)
		Local available:Int = conn.inputCount - conn.headerEnd
		Local offset:Int = conn.headerEnd
		While available > 0 And conn.receivedBody < conn.expectedBody
			Local count:Int = Int(Min(Long(config.ioBufferBytes), ..
				Min(Long(available), conn.expectedBody - conn.receivedBody)))
			Local chunk:Byte[] = New Byte[count]
			For Local i:Int = 0 Until count
				chunk[i] = conn.input[offset + i]
			Next
			Try
				conn.bodyHandler.Chunk(conn.request, conn.response, chunk)
			Catch error:Object
				_HandlerFault(conn, "object exception in stream Chunk")
				Return
			Catch error:String
				_HandlerFault(conn, error)
				Return
			End Try
			conn.receivedBody :+ count
			available :- count
			offset :+ count
		Wend
		If available > 0 Then conn.closeAfterResponse = True
		conn.inputCount = 0
		conn.headerEnd = 0
		If conn.receivedBody = conn.expectedBody Then _CompleteStream(conn)
	End Method

	Method _ConsumeChunked(conn:THTTPConnection)
		Local pos:Int = conn.headerEnd
		While pos < conn.inputCount And conn.state = 0
			Select conn.chunkState
				Case 0 ' chunk size line
					Local finish:Int = -1
					For Local i:Int = pos + 1 Until conn.inputCount
						If conn.input[i - 1] = 13 And conn.input[i] = 10 Then finish = i - 1; Exit
					Next
					If finish < 0
						If conn.inputCount - pos > 128 Then _Fail(conn, 400)
						Exit
					End If
					If finish = pos Or finish - pos > 128 Then _Fail(conn, 400); Return
					Local size:Long
					Local digits:Int
					Local maximum:Long = config.maxBodyBytes
					If conn.bodyHandler Then maximum = config.maxStreamBodyBytes
					For Local i:Int = pos Until finish
						If conn.input[i] = 59 Then Exit ' ignore bounded chunk extensions
						Local digit:Int = _HTTPHex(conn.input[i])
						If digit < 0 Then _Fail(conn, 400); Return
						If size > (maximum - conn.receivedBody) / 16 Then _Fail(conn, 413); Return
						size = size * 16 + digit
						If size > maximum - conn.receivedBody Then _Fail(conn, 413); Return
						digits :+ 1
					Next
					If digits = 0 Then _Fail(conn, 400); Return
					For Local i:Int = pos Until finish
						If conn.input[i] < 32 Or conn.input[i] > 126 Then _Fail(conn, 400); Return
					Next
					conn.chunkRemaining = size
					pos = finish + 2
					If size = 0 Then conn.chunkState = 3 Else conn.chunkState = 1
				Case 1 ' chunk data
					Local count:Int = Int(Min(Long(config.ioBufferBytes), ..
						Min(Long(conn.inputCount - pos), conn.chunkRemaining)))
					If count = 0 Then Exit
					If conn.bodyHandler
						Local chunk:Byte[] = New Byte[count]
						For Local i:Int = 0 Until count
							chunk[i] = conn.input[pos + i]
						Next
						Try
							conn.bodyHandler.Chunk(conn.request, conn.response, chunk)
						Catch error:Object
							_HandlerFault(conn, "object exception in stream Chunk")
							Return
						Catch error:String
							_HandlerFault(conn, error)
							Return
						End Try
					Else
						For Local i:Int = 0 Until count
							conn.request.body[Int(conn.receivedBody) + i] = conn.input[pos + i]
						Next
					End If
					conn.receivedBody :+ count
					conn.chunkRemaining :- count
					pos :+ count
					If conn.chunkRemaining = 0 Then conn.chunkState = 2
				Case 2 ' CRLF after chunk data
					If conn.inputCount - pos < 2 Then Exit
					If conn.input[pos] <> 13 Or conn.input[pos + 1] <> 10 Then _Fail(conn, 400); Return
					pos :+ 2
					conn.chunkState = 0
				Case 3 ' trailers, bounded and discarded
					Local finish:Int = -1
					For Local i:Int = pos + 1 Until conn.inputCount
						If conn.input[i - 1] = 13 And conn.input[i] = 10 Then finish = i - 1; Exit
					Next
					If finish < 0
						If conn.trailerBytes + conn.inputCount - pos > config.maxHeaderBytes Then _Fail(conn, 431)
						Exit
					End If
					conn.trailerBytes :+ finish - pos + 2
					If conn.trailerBytes > config.maxHeaderBytes Then _Fail(conn, 431); Return
					If finish = pos
						If conn.inputCount > finish + 2 Then conn.closeAfterResponse = True
						If conn.bodyHandler
							_CompleteStream(conn)
						Else
							Local body:Byte[] = New Byte[Int(conn.receivedBody)]
							For Local i:Int = 0 Until body.length
								body[i] = conn.request.body[i]
							Next
							conn.request.body = body
							_Dispatch(conn)
						End If
						Return
					End If
					conn.trailerCount :+ 1
					If conn.trailerCount > config.maxHeaders Then _Fail(conn, 431); Return
					Local raw:String = String.FromUTF8Bytes(Varptr conn.input[pos], finish - pos)
					Local colon:Int = raw.Find(":")
					If colon <= 0 Or Not _HTTPToken(raw[..colon]) Then _Fail(conn, 400); Return
					Select raw[..colon].ToLower()
						Case "host", "content-length", "transfer-encoding", "connection", "trailer"
							_Fail(conn, 400)
							Return
					End Select
					For Local i:Int = pos Until finish
						If (conn.input[i] < 32 And conn.input[i] <> 9) Or conn.input[i] > 126 Then _Fail(conn, 400); Return
					Next
					pos = finish + 2
			End Select
		Wend
		If conn.state <> 0 Then Return
		Local remaining:Int = conn.inputCount - pos
		For Local i:Int = 0 Until remaining
			conn.input[i] = conn.input[pos + i]
		Next
		conn.inputCount = remaining
		conn.headerEnd = 0
	End Method

	Public
	Rem
	bbdoc: Advances at most maxSteps accepts and connection operations.
	about: Call frequently from the managed application context. Route callbacks,
	stream producers and upgraded sessions run during this call.
	End Rem
	Method Service:Int(maxSteps:Int = 4)
		If Not running Or maxSteps <= 0 Then Return 0
		Local done:Int
		While done < maxSteps
			Local slot:Int = -1
			For Local i:Int = 0 Until connections.length
				If Not connections[i] Then slot = i; Exit
			Next
			If slot < 0 Then Exit
			Local socket:TSocket
			Local transport:IHTTPConnection
			If secureListener Then
				transport = secureListener.Accept()
				If Not transport Then Exit
			Else
				socket = listener.Accept(0)
				If Not socket Then Exit
			End If
			Try
				Local conn:THTTPConnection = New THTTPConnection
				conn.socket = socket
				conn.transport = transport
				conn.input = New Byte[config.maxHeaderBytes + config.maxBodyBytes]
				conn.started = MilliSecs()
				conn.lastActivity = conn.started
				connections[slot] = conn
			Catch error:Object
				If transport Then transport.Close()
				If socket Then socket.Close()
			Catch error:String
				If transport Then transport.Close()
				If socket Then socket.Close()
			End Try
			done :+ 1
		Wend
		For Local i:Int = 0 Until connections.length
			If done >= maxSteps Then Exit
			Local conn:THTTPConnection = connections[i]
			If Not conn Then Continue
			Try
				Local now:UInt = MilliSecs()
				If conn.state = 0
					If conn.headerEnd < 0 And conn.requestsServed > 0 And conn.inputCount = 0
						If now - conn.started >= config.keepAliveTimeoutMs Then
							conn.state = 3
						Else
							_Read(conn)
						End If
					Else If conn.headerEnd < 0 And now - conn.started >= config.headerTimeoutMs Then
						_Fail(conn, 408)
					Else If conn.headerEnd >= 0 And now - conn.lastActivity >= config.bodyTimeoutMs Then
						_Fail(conn, 408)
					Else
						_Read(conn)
					End If
				Else If conn.state = 4
					If Not conn.upgrade.Service(conn.upgradeIO) Then conn.state = 3
				Else
					If now - conn.lastActivity >= config.writeTimeoutMs Then
						conn.state = 3
					Else
						_Write(conn)
					End If
				End If
			Catch error:Object
				conn.state = 3
			Catch error:String
				conn.state = 3
			End Try
			done :+ 1
			If conn.state = 3 Then _Close(i)
		Next
		Return done
	End Method

	Private
	Method _Read(conn:THTTPConnection)
		If conn.inputCount = conn.input.length Then _Fail(conn, 431); Return
		Local amount:Int = _TryRecv(conn, Varptr conn.input[conn.inputCount], ..
			Size_T(conn.input.length - conn.inputCount))
		If amount = HTTPWouldBlock Then Return
		If amount <= 0 Then conn.state = 3; Return
		If conn.requestsServed > 0 And conn.inputCount = 0 Then conn.started = MilliSecs()
		conn.inputCount :+ amount
		conn.lastActivity = MilliSecs()
		If conn.headerEnd < 0
			Local requestLineEnd:Int = -1
			For Local i:Int = 1 Until conn.inputCount
				If conn.input[i - 1] = 13 And conn.input[i] = 10 Then requestLineEnd = i - 1; Exit
			Next
			If requestLineEnd > config.maxRequestLine Or ..
				(requestLineEnd < 0 And conn.inputCount > config.maxRequestLine + 2) Then
				_Fail(conn, 414)
				Return
			End If
			For Local i:Int = 3 Until conn.inputCount
				If conn.input[i - 3] = 13 And conn.input[i - 2] = 10 And ..
					conn.input[i - 1] = 13 And conn.input[i] = 10 Then
					conn.headerEnd = i + 1
					Exit
				End If
			Next
			If conn.headerEnd < 0
				If conn.inputCount >= config.maxHeaderBytes Then _Fail(conn, 431)
				Return
			End If
			If conn.headerEnd > config.maxHeaderBytes Then _Fail(conn, 431); Return
			_Parse(conn)
		End If
		If conn.state <> 0 Or Not conn.request Then Return
		If conn.chunked Then _ConsumeChunked(conn); Return
		If conn.bodyHandler Then _ConsumeStream(conn); Return
		If conn.inputCount - conn.headerEnd >= conn.expectedBody
			If conn.inputCount - conn.headerEnd > conn.expectedBody Then conn.closeAfterResponse = True
			If conn.expectedBody > 0
				conn.request.body = New Byte[conn.expectedBody]
				For Local i:Int = 0 Until conn.expectedBody
					conn.request.body[i] = conn.input[conn.headerEnd + i]
				Next
			End If
			_Dispatch(conn)
		End If
	End Method

	Method _FinishResponse(conn:THTTPConnection)
		If conn.response And conn.response.stream Then
			conn.response.stream.Close()
			conn.response.stream = Null
		End If
		If conn.response And conn.response.producer Then
			Local producer:IHTTPResponseProducer = conn.response.producer
			conn.response.producer = Null
			Try
				producer.Close()
			Catch error:Object
				_lastError = "HTTP response producer close failed"
			Catch error:String
				_lastError = "HTTP response producer close failed: " + error
			End Try
		End If
		conn.requestsServed :+ 1
		If conn.closeAfterResponse Then conn.state = 3; Return
		conn.inputCount = 0
		conn.headerEnd = -1
		conn.expectedBody = 0
		conn.receivedBody = 0
		conn.bodyHandler = Null
		conn.streamComplete = False
		conn.output = Null
		conn.outputOffset = 0
		conn.response = Null
		conn.request = Null
		conn.streamRemaining = 0
		conn.responseChunked = False
		conn.responseCloseDelimited = False
		conn.chunkFinal = False
		conn.fileCount = 0
		conn.fileOffset = 0
		conn.chunked = False
		conn.chunkState = 0
		conn.chunkRemaining = 0
		conn.trailerBytes = 0
		conn.trailerCount = 0
		conn.started = MilliSecs()
		conn.lastActivity = conn.started
		conn.state = 0
	End Method

	Method _Write(conn:THTTPConnection)
		If conn.outputOffset < conn.output.length
			Local count:Int = _TrySend(conn, Varptr conn.output[conn.outputOffset], ..
				Size_T(conn.output.length - conn.outputOffset))
			If count = HTTPWouldBlock Then Return
			If count <= 0 Then conn.state = 3; Return
			conn.outputOffset :+ count
			conn.lastActivity = MilliSecs()
			Return
		End If
		If conn.state = 5 Then
			conn.output = Null
			conn.state = 4
			Return
		End If
		If conn.request And conn.request.method = "HEAD" Then _FinishResponse(conn); Return
		If conn.response.status = 204 Or conn.response.status = 205 Or ..
			conn.response.status = 304 Then _FinishResponse(conn); Return
		If conn.responseChunked Or conn.responseCloseDelimited
			If conn.chunkFinal Then _FinishResponse(conn); Return
			If Not conn.fileBuffer Then conn.fileBuffer = New Byte[config.ioBufferBytes]
			If conn.responseCloseDelimited And conn.fileOffset < conn.fileCount
				Local sent:Int = _TrySend(conn, Varptr conn.fileBuffer[conn.fileOffset], ..
					Size_T(conn.fileCount - conn.fileOffset))
				If sent = HTTPWouldBlock Then Return
				If sent <= 0 Then conn.state = 3; Return
				conn.fileOffset :+ sent
				conn.lastActivity = MilliSecs()
				Return
			End If
			Local amount:Int
			Try
				If conn.response.producer Then
					amount = conn.response.producer.TryRead(Varptr conn.fileBuffer[0], conn.fileBuffer.length)
				Else
					amount = Int(conn.response.stream.Read(Varptr conn.fileBuffer[0], conn.fileBuffer.length))
				End If
			Catch error:Object
				_lastError = "HTTP response source threw an object exception"
				conn.state = 3
				Return
			Catch error:String
				_lastError = "HTTP response source failed: " + error
				conn.state = 3
				Return
			End Try
			If amount = HTTPWouldBlock Then Return
			If amount < 0 Or amount > conn.fileBuffer.length Then
				_lastError = "HTTP response source returned an invalid count"
				conn.state = 3
				Return
			End If
			If amount = 0 Then
				If conn.responseCloseDelimited Then _FinishResponse(conn); Return
				conn.output = _HTTPBytes("0~r~n~r~n")
				conn.outputOffset = 0
				conn.chunkFinal = True
				Return
			End If
			If conn.responseCloseDelimited
				conn.fileCount = amount
				conn.fileOffset = 0
				Return
			End If
			Local prefix:Byte[] = _HTTPBytes(_HTTPChunkSize(amount) + "~r~n")
			Local frame:Byte[] = New Byte[prefix.length + amount + 2]
			For Local i:Int = 0 Until prefix.length
				frame[i] = prefix[i]
			Next
			For Local i:Int = 0 Until amount
				frame[prefix.length + i] = conn.fileBuffer[i]
			Next
			frame[frame.length - 2] = 13
			frame[frame.length - 1] = 10
			conn.output = frame
			conn.outputOffset = 0
			Return
		End If
		If conn.response.stream
			If conn.streamRemaining <= 0 Then _FinishResponse(conn); Return
			If Not conn.fileBuffer Then conn.fileBuffer = New Byte[config.ioBufferBytes]
			If conn.fileOffset = conn.fileCount
				Local amount:Long = Min(Long(conn.fileBuffer.length), conn.streamRemaining)
				conn.fileCount = Int(conn.response.stream.Read(Varptr conn.fileBuffer[0], amount))
				conn.fileOffset = 0
				If conn.fileCount <= 0 Then conn.state = 3; Return
			End If
			Local sent:Int = _TrySend(conn, Varptr conn.fileBuffer[conn.fileOffset], ..
				Size_T(conn.fileCount - conn.fileOffset))
			If sent = HTTPWouldBlock Then Return
			If sent <= 0 Then conn.state = 3; Return
			conn.fileOffset :+ sent
			conn.streamRemaining :- sent
			conn.lastActivity = MilliSecs()
			Return
		End If
		If conn.response.body And conn.response.body.length > 0
			If conn.fileOffset = conn.response.body.length Then _FinishResponse(conn); Return
			Local sent:Int = _TrySend(conn, Varptr conn.response.body[conn.fileOffset], ..
				Size_T(conn.response.body.length - conn.fileOffset))
			If sent = HTTPWouldBlock Then Return
			If sent <= 0 Then conn.state = 3; Return
			conn.fileOffset :+ sent
			conn.lastActivity = MilliSecs()
		Else
			_FinishResponse(conn)
		End If
	End Method
End Type

Private

Function _Match:THTTPField[](pattern:String, path:String, isStatic:Int)
	If isStatic
		If path.StartsWith(pattern) Then Return New THTTPField[1]
		Return Null
	End If
	Local expected:String[] = pattern.Split("/")
	Local actual:String[] = path.Split("/")
	If expected.length <> actual.length Then Return Null
	Local count:Int
	For Local i:Int = 0 Until expected.length
		If expected[i].StartsWith(":")
			If actual[i].length = 0 Then Return Null
			count :+ 1
		Else If expected[i] <> actual[i]
			Return Null
		End If
	Next
	Local params:THTTPField[] = New THTTPField[Max(1, count)]
	count = 0
	For Local i:Int = 0 Until expected.length
		If expected[i].StartsWith(":")
			Local field:THTTPField = New THTTPField
			field.name = expected[i][1..]
			field.value = actual[i]
			params[count] = field
			count :+ 1
		End If
	Next
	Return params
End Function
?
