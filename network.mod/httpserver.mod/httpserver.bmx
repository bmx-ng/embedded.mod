' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Bounded, explicitly serviced HTTP server for embedded targets.
about: Call Service regularly on the managed application context. One request
is handled per connection; every response closes the connection.
End Rem
Module Embedded.Network.HTTPServer
?not win32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Socket
Import BRL.Stream
Import BRL.FileSystem
Import BRL.System

Const HTTPWouldBlock:Int = -2

Type THTTPServerConfig
	Field port:Int = 8080
	Field maxConnections:Int = 1
	Field maxRoutes:Int = 16
	Field maxRequestLine:Int = 256
	Field maxHeaderBytes:Int = 1024
	Field maxHeaders:Int = 16
	Field maxBodyBytes:Int = 1024
	Field maxResponseBodyBytes:Int = 1024
	Field ioBufferBytes:Int = 512
	Field headerTimeoutMs:UInt = 5000
	Field bodyTimeoutMs:UInt = 10000
	Field writeTimeoutMs:UInt = 10000

	Method Copy:THTTPServerConfig()
		Local result:THTTPServerConfig = New THTTPServerConfig
		result.port = port
		result.maxConnections = maxConnections
		result.maxRoutes = maxRoutes
		result.maxRequestLine = maxRequestLine
		result.maxHeaderBytes = maxHeaderBytes
		result.maxHeaders = maxHeaders
		result.maxBodyBytes = maxBodyBytes
		result.maxResponseBodyBytes = maxResponseBodyBytes
		result.ioBufferBytes = ioBufferBytes
		result.headerTimeoutMs = headerTimeoutMs
		result.bodyTimeoutMs = bodyTimeoutMs
		result.writeTimeoutMs = writeTimeoutMs
		Return result
	End Method
End Type

Type THTTPField
	Field name:String
	Field value:String
End Type

Type THTTPRequest
	Field method:String
	Field path:String
	Field query:String
	Field version:String
	Field remoteIP:String
	Field body:Byte[]
	Field headers:THTTPField[]
	Field parameters:THTTPField[]

	Method Header:String(name:String)
		For Local item:THTTPField = EachIn headers
			If item And item.name = name.ToLower() Then Return item.value
		Next
		Return ""
	End Method

	Method Parameter:String(name:String)
		For Local item:THTTPField = EachIn parameters
			If item And item.name = name Then Return item.value
		Next
		Return ""
	End Method

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

	Method BodyText:String()
		If Not body Or body.length = 0 Then Return ""
		Return String.FromUTF8Bytes(Varptr body[0], body.length)
	End Method
End Type

Type THTTPResponse
	Field status:Int = 200
	Field contentType:String = "text/plain; charset=utf-8"
	Field body:Byte[]
	Field stream:TStream
	Field streamLength:Long = -1
	Field headers:THTTPField[] = New THTTPField[8]
	Field headerCount:Int

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

	Method Text(value:String)
		contentType = "text/plain; charset=utf-8"
		body = _HTTPBytes(value)
	End Method

	Method Html(value:String)
		contentType = "text/html; charset=utf-8"
		body = _HTTPBytes(value)
	End Method

	Method Json(value:String)
		contentType = "application/json; charset=utf-8"
		body = _HTTPBytes(value)
	End Method

	Method Bytes(value:Byte[], mime:String = "application/octet-stream")
		contentType = mime
		body = value
	End Method

	Method Redirect(location:String, code:Int = 302)
		status = code
		SetHeader("Location", location)
		body = New Byte[0]
	End Method

	Method StreamFile(value:TStream, size:Long, mime:String = "application/octet-stream")
		stream = value
		streamLength = size
		contentType = mime
	End Method
End Type

Interface IHTTPHandler
	Method Handle(request:THTTPRequest, response:THTTPResponse)
End Interface

Interface IHTTPErrorHandler
	Method HandleError(status:Int, response:THTTPResponse)
End Interface

Private

Type THTTPRoute
	Field method:String
	Field path:String
	Field handler:IHTTPHandler
	Field staticRoot:String
End Type

Type THTTPConnection
	Field socket:TSocket
	Field input:Byte[]
	Field inputCount:Int
	Field headerEnd:Int = -1
	Field expectedBody:Int
	Field started:UInt
	Field lastActivity:UInt
	Field output:Byte[]
	Field outputOffset:Int
	Field response:THTTPResponse
	Field request:THTTPRequest
	Field streamRemaining:Long
	Field fileBuffer:Byte[]
	Field fileCount:Int
	Field fileOffset:Int
	Field state:Int ' 0 reading, 1 sending headers/body, 2 sending stream
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
		Case 408 Return "Request Timeout"
		Case 411 Return "Length Required"
		Case 413 Return "Content Too Large"
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

Public

Type THTTPServer
	Private
	Field config:THTTPServerConfig
	Field listener:TSocket
	Field routes:THTTPRoute[]
	Field routeCount:Int
	Field connections:THTTPConnection[]
	Field errorHandler:IHTTPErrorHandler
	Field _lastError:String

	Public
	Function Create:THTTPServer(settings:THTTPServerConfig = Null)
		If Not settings Then settings = New THTTPServerConfig
		If settings.maxConnections < 1 Or settings.maxConnections > 4 Or ..
			settings.port < 0 Or settings.port > 65535 Or ..
			settings.maxRoutes < 1 Or settings.maxRoutes > 64 Or ..
			settings.maxHeaderBytes < 128 Or ..
			settings.maxHeaderBytes > 4096 Or settings.maxBodyBytes < 0 Or ..
			settings.maxBodyBytes > 8192 Or settings.maxResponseBodyBytes < 0 Or ..
			settings.maxResponseBodyBytes > 8192 Or ..
			settings.ioBufferBytes < 64 Or settings.ioBufferBytes > 2048 Or ..
			settings.maxHeaders < 1 Or settings.maxHeaders > 32 Or ..
			settings.maxRequestLine < 16 Or ..
			settings.maxRequestLine > settings.maxHeaderBytes Then Return Null
		Local server:THTTPServer
		Try
			server = New THTTPServer
			server.config = settings.Copy()
			server.routes = New THTTPRoute[settings.maxRoutes]
			server.connections = New THTTPConnection[settings.maxConnections]
		Catch error:Object
			Return Null
		Catch error:String
			Return Null
		End Try
		Return server
	End Function

	Method Route:Int(method:String, path:String, handler:IHTTPHandler)
		If listener Or routeCount = routes.length Or Not handler Or ..
			Not _HTTPToken(method) Or Not path.StartsWith("/") Then Return False
		Local route:THTTPRoute = New THTTPRoute
		route.method = method.ToUpper()
		route.path = path
		route.handler = handler
		routes[routeCount] = route
		routeCount :+ 1
		Return True
	End Method

	Method Static:Int(prefix:String, root:String)
		If listener Or routeCount = routes.length Or Not prefix.StartsWith("/") Or ..
			Not prefix.EndsWith("/") Or root.length = 0 Then Return False
		Local route:THTTPRoute = New THTTPRoute
		route.method = "GET"
		route.path = prefix
		route.staticRoot = root
		routes[routeCount] = route
		routeCount :+ 1
		Return True
	End Method

	Method OnError(handler:IHTTPErrorHandler)
		errorHandler = handler
	End Method

	Method LastError:String()
		Return _lastError
	End Method

	Method ActiveConnections:Int()
		Local count:Int
		For Local conn:THTTPConnection = EachIn connections
			If conn Then count :+ 1
		Next
		Return count
	End Method

	Method Start:Int()
		If listener Then Return True
		listener = TSocket.CreateTCP()
		If Not listener Then _lastError = "socket creation failed"; Return False
		listener.SetSockOpt(SOL_SOCKET, SO_REUSEADDR, True)
		If Not listener.Bind(config.port) Or Not listener.Listen(config.maxConnections) Then
			_lastError = "socket bind or listen failed"
			listener.Close()
			listener = Null
			Return False
		End If
		Return True
	End Method

	Method Stop()
		For Local i:Int = 0 Until connections.length
			_Close(i)
		Next
		If listener Then listener.Close()
		listener = Null
	End Method

	Private
	Method _Close(index:Int)
		Local conn:THTTPConnection = connections[index]
		If Not conn Then Return
		If conn.response And conn.response.stream Then
			Try
				conn.response.stream.Close()
			Catch error:Object
			Catch error:String
			End Try
		End If
		If conn.socket Then conn.socket.Close()
		connections[index] = Null
	End Method

	Method _Fail(conn:THTTPConnection, status:Int)
		conn.response = New THTTPResponse
		conn.response.status = status
		conn.response.Text(_HTTPReason(status))
		If errorHandler Then errorHandler.HandleError(status, conn.response)
		_Prepare(conn)
	End Method

	Method _Prepare(conn:THTTPConnection)
		Local response:THTTPResponse = conn.response
		If response.status < 200 Or response.status > 599 Then response.status = 500
		If response.contentType.length > 128 Or ..
			response.contentType.Find(Chr(13)) >= 0 Or ..
			response.contentType.Find(Chr(10)) >= 0 Then
			response.contentType = "application/octet-stream"
		End If
		Local length:Long
		If response.stream
			length = response.streamLength
			If length < 0 Then response.stream.Close(); response.stream = Null; response.status = 500
		Else If response.body
			length = response.body.length
			If length > config.maxResponseBodyBytes Then
				response.status = 500
				response.body = Null
				length = 0
			End If
		End If
		If response.status = 204 Or response.status = 205 Or response.status = 304 Then length = 0
		Local version:String = "HTTP/1.1"
		If conn.request Then version = conn.request.version
		Local wire:String = version + " " + response.status + " " + _HTTPReason(response.status) + "~r~n" + ..
			"Content-Length: " + length + "~r~nConnection: close~r~nContent-Type: " + ..
			response.contentType + "~r~n"
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
		Local stream:TStream = ReadStream(path)
		If Not stream Then response.status = 404; Return
		response.StreamFile(stream, info.size, _HTTPMime(path))
	End Method

	Method _Dispatch(conn:THTTPConnection)
		Local request:THTTPRequest = conn.request
		Local response:THTTPResponse = New THTTPResponse
		conn.response = response
		If request.method <> "GET" And request.method <> "HEAD" And request.method <> "POST" Then
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
				If route.staticRoot <> "" Then
					_StaticFile(request, response, route)
					If response.status >= 400 Then _Fail(conn, response.status); Return
				Else
					route.handler.Handle(request, response)
				End If
				_Prepare(conn)
				Return
			Next
		Next
		If matchedPath
			response.status = 405
			response.Text(_HTTPReason(405))
			response.SetHeader("Allow", allow)
			If errorHandler Then errorHandler.HandleError(405, response)
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
		request.remoteIP = conn.socket.RemoteIp()
		request.headers = New THTTPField[config.maxHeaders]
		Local headerCount:Int
		Local host:Int
		Local lengthSeen:Int
		Local transferEncoding:Int
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
					For Local j:Int = 0 Until value.length
						If value[j] < 48 Or value[j] > 57 Then _Fail(conn, 400); Return
						total = total * 10 + value[j] - 48
						If total > config.maxBodyBytes Then _Fail(conn, 413); Return
					Next
					conn.expectedBody = Int(total)
				Case "transfer-encoding" transferEncoding = True
				Case "expect" _Fail(conn, 417); Return
			End Select
			pos = finish + 2
		Wend
		If transferEncoding Then
			If lengthSeen Then _Fail(conn, 400) Else _Fail(conn, 501)
			Return
		End If
		If request.version = "HTTP/1.1" And host <> 1 Then _Fail(conn, 400); Return
		If request.method = "POST" And Not lengthSeen Then _Fail(conn, 411); Return
		conn.request = request
		If conn.expectedBody = 0 Then _Dispatch(conn)
	End Method

	Public
	Method Service:Int(maxSteps:Int = 4)
		If Not listener Or maxSteps <= 0 Then Return 0
		Local done:Int
		While done < maxSteps
			Local slot:Int = -1
			For Local i:Int = 0 Until connections.length
				If Not connections[i] Then slot = i; Exit
			Next
			If slot < 0 Then Exit
			Local socket:TSocket = listener.Accept(0)
			If Not socket Then Exit
			Try
				Local conn:THTTPConnection = New THTTPConnection
				conn.socket = socket
				conn.input = New Byte[config.maxHeaderBytes + config.maxBodyBytes]
				conn.started = MilliSecs()
				conn.lastActivity = conn.started
				connections[slot] = conn
			Catch error:Object
				socket.Close()
			Catch error:String
				socket.Close()
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
					If conn.headerEnd < 0 And now - conn.started >= config.headerTimeoutMs Then
						_Fail(conn, 408)
					Else If conn.headerEnd >= 0 And now - conn.lastActivity >= config.bodyTimeoutMs Then
						_Fail(conn, 408)
					Else
						_Read(conn)
					End If
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
		Local amount:Int = conn.socket.TryRecv(Varptr conn.input[conn.inputCount], ..
			Size_T(conn.input.length - conn.inputCount))
		If amount = HTTPWouldBlock Then Return
		If amount <= 0 Then conn.state = 3; Return
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
		If conn.inputCount - conn.headerEnd >= conn.expectedBody
			If conn.expectedBody > 0
				conn.request.body = New Byte[conn.expectedBody]
				For Local i:Int = 0 Until conn.expectedBody
					conn.request.body[i] = conn.input[conn.headerEnd + i]
				Next
			End If
			_Dispatch(conn)
		End If
	End Method

	Method _Write(conn:THTTPConnection)
		If conn.outputOffset < conn.output.length
			Local count:Int = conn.socket.TrySend(Varptr conn.output[conn.outputOffset], ..
				Size_T(conn.output.length - conn.outputOffset))
			If count = HTTPWouldBlock Then Return
			If count <= 0 Then conn.state = 3; Return
			conn.outputOffset :+ count
			conn.lastActivity = MilliSecs()
			Return
		End If
		If conn.request And conn.request.method = "HEAD" Then conn.state = 3; Return
		If conn.response.status = 204 Or conn.response.status = 205 Or ..
			conn.response.status = 304 Then conn.state = 3; Return
		If conn.response.stream
			If conn.streamRemaining <= 0 Then conn.state = 3; Return
			If Not conn.fileBuffer Then conn.fileBuffer = New Byte[config.ioBufferBytes]
			If conn.fileOffset = conn.fileCount
				Local amount:Long = Min(Long(conn.fileBuffer.length), conn.streamRemaining)
				conn.fileCount = Int(conn.response.stream.Read(Varptr conn.fileBuffer[0], amount))
				conn.fileOffset = 0
				If conn.fileCount <= 0 Then conn.state = 3; Return
			End If
			Local sent:Int = conn.socket.TrySend(Varptr conn.fileBuffer[conn.fileOffset], ..
				Size_T(conn.fileCount - conn.fileOffset))
			If sent = HTTPWouldBlock Then Return
			If sent <= 0 Then conn.state = 3; Return
			conn.fileOffset :+ sent
			conn.streamRemaining :- sent
			conn.lastActivity = MilliSecs()
			Return
		End If
		If conn.response.body And conn.response.body.length > 0
			If conn.fileOffset = conn.response.body.length Then conn.state = 3; Return
			Local sent:Int = conn.socket.TrySend(Varptr conn.response.body[conn.fileOffset], ..
				Size_T(conn.response.body.length - conn.fileOffset))
			If sent = HTTPWouldBlock Then Return
			If sent <= 0 Then conn.state = 3; Return
			conn.fileOffset :+ sent
			conn.lastActivity = MilliSecs()
		Else
			conn.state = 3
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
