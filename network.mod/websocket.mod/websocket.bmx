' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional bounded WebSocket support for Embedded.Network.HTTPServer.
about: Import this module only in applications with WebSocket routes. Sessions
are serviced in the HTTP server's managed context on plain or TLS connections.
End Rem
Module Embedded.Network.WebSocket
?not win32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Network.HTTPServer

Const WebSocketNormalClosure:Int = 1000
Const WebSocketGoingAway:Int = 1001
Const WebSocketProtocolError:Int = 1002
Const WebSocketInvalidData:Int = 1007
Const WebSocketMessageTooBig:Int = 1009
Const WebSocketInternalError:Int = 1011

Rem
bbdoc: Callbacks for one WebSocket route.
about: Accept runs before the upgrade, so applications can check Origin or
credentials. Open, Message and Closed run from THTTPServer.Service(). Message
receives one complete bounded text or binary message.
End Rem
Interface IHTTPWebSocketHandler
	Rem
	bbdoc: Approves an upgrade after checking credentials and Origin.
	about: Return False to send HTTP 403 before the WebSocket opens.
	End Rem
	Method Accept:Int(request:THTTPRequest)
	Rem
	bbdoc: Runs once after the WebSocket connection opens.
	End Rem
	Method Open(socket:THTTPWebSocket, request:THTTPRequest)
	Rem
	bbdoc: Receives one complete text or binary message within the route limit.
	about: isText is True for UTF-8 text and False for binary data.
	End Rem
	Method Message(socket:THTTPWebSocket, data:Byte[], isText:Int)
	Rem
	bbdoc: Runs once when the WebSocket connection closes.
	End Rem
	Method Closed(socket:THTTPWebSocket, code:Int)
End Interface

Rem
bbdoc: Optional per-connection WebSocket compression codec.
about: Implement in a separate module. Decode must enforce maxOutput after
expansion. The WebSocketDeflate module supplies a ready-made implementation.
End Rem
Interface IHTTPWebSocketCompression
	Method ResponseHeader:String()
	Method Encode:Byte[](data:Byte[])
	Method Decode:Byte[](data:Byte[], maxOutput:Int)
	Method DecodeFailureCode:Int()
End Interface

Rem
bbdoc: Negotiates an optional compression codec for each connection.
about: Negotiate receives the client's extension offers and returns Null to
decline them. Each accepted connection must receive its own codec instance.
End Rem
Interface IHTTPWebSocketCompressionFactory
	Method Negotiate:IHTTPWebSocketCompression(offer:String)
End Interface

Rem
bbdoc: Handler passed to THTTPServer.RouteUpgrade for a WebSocket endpoint.
about: Configure subprotocols and optional compression before registering the
route. Each open client occupies one HTTP server connection slot.
End Rem
Type THTTPWebSocketUpgrade Implements IHTTPUpgradeHandler
	Private
	Field handler:IHTTPWebSocketHandler
	Field maxMessage:Int
	Field maxPending:Int
	Field subprotocols:String[]
	Field compressionFactory:IHTTPWebSocketCompressionFactory

	Public
	Rem
	bbdoc: Creates a bounded WebSocket upgrade handler for one route.
	about: maxMessageBytes defaults to 2048 and accepts 64..65536 bytes;
	maxPendingBytes defaults to 4096 and accepts 256..65536 bytes. Returns
	Null for an invalid handler or limit.
	End Rem
	Function Create:THTTPWebSocketUpgrade(handler:IHTTPWebSocketHandler, ..
		maxMessageBytes:Int = 2048, maxPendingBytes:Int = 4096)
		If Not handler Or maxMessageBytes < 64 Or maxMessageBytes > 65536 Or ..
			maxPendingBytes < 256 Or maxPendingBytes > 65536 Then Return Null
		Local result:THTTPWebSocketUpgrade = New THTTPWebSocketUpgrade
		result.handler = handler
		result.maxMessage = maxMessageBytes
		result.maxPending = maxPendingBytes
		Return result
	End Function

	Rem
	bbdoc: Sets supported subprotocol tokens, returning False if any is invalid.
	about: The first client-offered supported token is selected. Pass Null to
	remove the list. An unmatched offer can still upgrade without a protocol.
	End Rem
	Method SetSubprotocols:Int(supported:String[])
		If Not supported Then
			subprotocols = Null
			Return True
		End If
		For Local candidate:String = EachIn supported
			If Not _WSValidToken(candidate) Then Return False
		Next
		subprotocols = supported[..]
		Return True
	End Method

	Rem
	bbdoc: Enables optional compression negotiation for this route.
	about: Pass Null to disable it. Import WebSocketDeflate for the supplied
	permessage-deflate factory.
	End Rem
	Method SetCompressionFactory(factory:IHTTPWebSocketCompressionFactory)
		compressionFactory = factory
	End Method

	Method HandleUpgrade(request:THTTPRequest, response:THTTPResponse)
		If request.method <> "GET" Or request.version <> "HTTP/1.1" Or ..
			Not _WSTokenContains(request.Header("Connection"), "upgrade") Or ..
			Not _WSTokenContains(request.Header("Upgrade"), "websocket") Then
			response.status = 400
			response.Text("Bad Request")
			Return
		End If
		Local version:String = request.Header("Sec-WebSocket-Version")
		If version <> "13" Then
			response.status = 426
			response.SetHeader("Sec-WebSocket-Version", "13")
			response.Text("Upgrade Required")
			Return
		End If
		Local key:String = request.Header("Sec-WebSocket-Key")
		If Not _WSValidKey(key) Or ..
			_WSHeaderCount(request, "sec-websocket-key") <> 1 Or ..
			_WSHeaderCount(request, "sec-websocket-version") <> 1 Or ..
			_WSHeaderCount(request, "upgrade") <> 1 Then
			response.status = 400
			response.Text("Bad Request")
			Return
		End If
		If Not handler.Accept(request) Then
			response.status = 403
			response.Text("Forbidden")
			Return
		End If
		Local protocol:String = _WSSelectSubprotocol(request, subprotocols)
		If protocol = Chr(0) Then
			response.status = 400
			response.Text("Bad Request")
			Return
		End If
		Local codec:IHTTPWebSocketCompression
		If compressionFactory Then codec = compressionFactory.Negotiate(_WSHeaderValues(request, "sec-websocket-extensions"))
		Local source:THTTPWebSocket = THTTPWebSocket._Create(handler, request, maxMessage, maxPending, protocol, codec)
		If Not source Then
			response.status = 500
			response.Text("Internal Server Error")
			Return
		End If
		Local accept:String = _WSAccept(key)
		If protocol And Not response.SetHeader("Sec-WebSocket-Protocol", protocol) Then
			response.status = 500; response.Text("Internal Server Error"); Return
		End If
		If codec And Not response.SetHeader("Sec-WebSocket-Extensions", codec.ResponseHeader()) Then
			response.status = 500; response.Text("Internal Server Error"); Return
		End If
		If Not response.SetHeader("Upgrade", "websocket") Or ..
			Not response.SetHeader("Sec-WebSocket-Accept", accept) Or ..
			Not response.Upgrade(source) Then
			response.status = 500
			response.Text("Internal Server Error")
		End If
	End Method
End Type

Rem
bbdoc: One bounded WebSocket connection.
about: SendText and SendBinary queue complete messages and return False when
the connection is closing or its output queue is full. Disconnect initiates a
close handshake. Access the socket only in the managed application context.
End Rem
Type THTTPWebSocket Implements IHTTPUpgradedSession
	Private
	Field handler:IHTTPWebSocketHandler
	Field request:THTTPRequest
	Field rx:Byte[]
	Field rxCount:Int
	Field message:Byte[]
	Field messageCount:Int
	Field fragmentOpcode:Int
	Field tx:Byte[]
	Field txRead:Int
	Field txWrite:Int
	Field txCount:Int
	Field maxMessage:Int
	Field subprotocol:String
	Field codec:IHTTPWebSocketCompression
	Field fragmentCompressed:Int
	Field opened:Int
	Field closed:Int
	Field closing:Int
	Field closeReceived:Int
	Field closeCode:Int = 1006
	Field closeStarted:UInt
	Field lastActivity:UInt
	Field pingStarted:UInt
	Field awaitingPong:Int

	Public
	Function _Create:THTTPWebSocket(handler:IHTTPWebSocketHandler, request:THTTPRequest, ..
		maxMessage:Int, maxPending:Int, subprotocol:String, codec:IHTTPWebSocketCompression)
		Local result:THTTPWebSocket
		Try
			result = New THTTPWebSocket
			result.handler = handler
			result.request = request
			result.maxMessage = maxMessage
			result.subprotocol = subprotocol
			result.codec = codec
			result.rx = New Byte[maxMessage + 14]
			result.message = New Byte[maxMessage]
			result.tx = New Byte[maxPending]
		Catch error:Object
			Return Null
		Catch error:String
			Return Null
		End Try
		result.lastActivity = MilliSecs()
		Return result
	End Function

	Method _Queue:Int(opcode:Int, data:Byte[], compressed:Int = False)
		If closed Or (closing And opcode <> 8 And opcode <> 10) Then Return False
		Local length:Int = data.length
		Local header:Int = 2
		If length > 125 And length <= 65535 Then header = 4
		If length > 65535 Then header = 10
		Local available:Int = tx.length - txCount
		If opcode = 1 Or opcode = 2 Then available :- 128
		If length + header > available Then Return False
		Local frame:Byte[] = New Byte[length + header]
		frame[0] = Byte($80 | opcode | (compressed Shl 6))
		If header = 2
			frame[1] = Byte(length)
		Else If header = 4
			frame[1] = 126
			frame[2] = Byte(length Shr 8)
			frame[3] = Byte(length)
		Else
			frame[1] = 127
			frame[6] = Byte(length Shr 24)
			frame[7] = Byte(length Shr 16)
			frame[8] = Byte(length Shr 8)
			frame[9] = Byte(length)
		End If
		For Local i:Int = 0 Until length
			frame[header + i] = data[i]
		Next
		For Local i:Int = 0 Until frame.length
			tx[txWrite] = frame[i]
			txWrite :+ 1
			If txWrite = tx.length Then txWrite = 0
		Next
		txCount :+ frame.length
		Return True
	End Method

	Method _QueueControl:Int(opcode:Int, data:Byte[])
		Return _Queue(opcode, data)
	End Method

	Method _Fail(code:Int)
		Disconnect(code)
		rxCount = 0
	End Method

	Public
	Rem
	bbdoc: Queues a complete UTF-8 text message.
	about: Returns False if the message exceeds the route limit, the output
	queue lacks room, or the connection is closing.
	End Rem
	Method SendText:Int(value:String)
		If closed Or closing Then Return False
		If value.length > maxMessage Then Return False
		Local data:Byte[] = _WSBytes(value)
		If data.length > maxMessage Then Return False
		Return _QueueMessage(1, data)
	End Method

	Rem
	bbdoc: Queues a complete binary message, returning False if it cannot fit.
	End Rem
	Method SendBinary:Int(data:Byte[])
		If closed Or closing Or Not data Or data.length > maxMessage Then Return False
		Return _QueueMessage(2, data)
	End Method

	Rem
	bbdoc: Returns the negotiated subprotocol, or an empty string if none.
	End Rem
	Method Subprotocol:String()
		Return subprotocol
	End Method

	Private
	Method _QueueMessage:Int(opcode:Int, data:Byte[])
		If codec And data.length >= 32 Then
			Local encoded:Byte[] = codec.Encode(data)
			If encoded And encoded.length < data.length Then Return _Queue(opcode, encoded, True)
		End If
		Return _Queue(opcode, data)
	End Method

	Public

	Rem
	bbdoc: Begins a close handshake with an optional code and reason.
	about: The connection closes after the peer replies or the close timeout.
	End Rem
	Method Disconnect(code:Int = WebSocketNormalClosure, reason:String = "")
		If closed Or closing Then Return
		If Not _WSValidCloseCode(code) Then code = WebSocketProtocolError
		If reason.length > 123 Then reason = ""
		Local reasonBytes:Byte[] = _WSBytes(reason)
		If reasonBytes.length > 123 Then reasonBytes = New Byte[0]
		Local payload:Byte[] = New Byte[reasonBytes.length + 2]
		payload[0] = Byte(code Shr 8)
		payload[1] = Byte(code)
		For Local i:Int = 0 Until reasonBytes.length
			payload[i + 2] = reasonBytes[i]
		Next
		closing = True
		closeCode = code
		closeStarted = MilliSecs()
		_QueueControl(8, payload)
	End Method

	Rem
	bbdoc: Reports whether the connection has finished closing.
	End Rem
	Method IsClosed:Int()
		Return closed
	End Method

	Rem
	bbdoc: Returns the number of queued output bytes.
	End Rem
	Method PendingBytes:Int()
		Return txCount
	End Method

	Method Service:Int(io:IHTTPUpgradedIO)
		If closed Then Return False
		If Not opened Then
			opened = True
			handler.Open(Self, request)
		End If
		If txCount > 0 Then
			Local contiguous:Int = Min(txCount, tx.length - txRead)
			Local sent:Int = io.TrySend(Varptr tx[txRead], Size_T(contiguous))
			If sent = 0 Or (sent < 0 And sent <> HTTPWouldBlock) Then Return False
			If sent > 0 Then
				txRead = (txRead + sent) Mod tx.length
				txCount :- sent
				lastActivity = MilliSecs()
			End If
		End If
		If closing And closeReceived And txCount = 0 Then Return False
		If closing And MilliSecs() - closeStarted >= 3000 Then Return False
		If Not closing And awaitingPong And MilliSecs() - pingStarted >= 10000 Then
			Disconnect(WebSocketGoingAway)
		End If
		If Not closing And Not awaitingPong And MilliSecs() - lastActivity >= 30000 Then
			If _Queue(9, New Byte[0]) Then
				awaitingPong = True
				pingStarted = MilliSecs()
			End If
		End If
		If rxCount = rx.length Then _Fail(WebSocketMessageTooBig); Return True
		Local received:Int = io.TryRecv(Varptr rx[rxCount], Size_T(rx.length - rxCount))
		If received = 0 Or (received < 0 And received <> HTTPWouldBlock) Then Return False
		If received > 0 Then
			rxCount :+ received
			lastActivity = MilliSecs()
			_Parse()
		End If
		Return True
	End Method

	Method Close()
		If closed Then Return
		closed = True
		handler.Closed(Self, closeCode)
		rx = Null
		message = Null
		tx = Null
		codec = Null
	End Method

	Private
	Method _Deliver(opcode:Int, payload:Byte[], compressed:Int)
		If compressed Then
			payload = codec.Decode(payload, maxMessage)
			If Not payload Then _Fail(codec.DecodeFailureCode()); Return
		End If
		If opcode = 1 And Not _WSValidUTF8(payload, 0, payload.length) Then
			_Fail(WebSocketInvalidData)
			Return
		End If
		handler.Message(Self, payload, opcode = 1)
	End Method

	Method _Frame(opcode:Int, fin:Int, payload:Byte[], compressed:Int)
		Select opcode
			Case 8
				If payload.length = 1 Then _Fail(WebSocketProtocolError); Return
				If payload.length >= 2 Then
					Local code:Int = ((payload[0] & 255) Shl 8) | (payload[1] & 255)
					If Not _WSValidCloseCode(code) Or ..
						Not _WSValidUTF8(payload, 2, payload.length - 2) Then
						_Fail(WebSocketProtocolError)
						Return
					End If
					closeCode = code
				End If
				closeReceived = True
				If Not closing Then
					closing = True
					closeStarted = MilliSecs()
					If Not _QueueControl(8, payload) Then _Fail(WebSocketProtocolError)
				End If
			Case 9
				If Not closing And Not _QueueControl(10, payload) Then _Fail(WebSocketProtocolError)
			Case 10
				If awaitingPong And payload.length = 0 Then awaitingPong = False
			Case 0
				If Not fragmentOpcode Then _Fail(WebSocketProtocolError); Return
				If payload.length > maxMessage - messageCount Then _Fail(WebSocketMessageTooBig); Return
				For Local i:Int = 0 Until payload.length
					message[messageCount + i] = payload[i]
				Next
				messageCount :+ payload.length
				If fin Then
					Local complete:Byte[] = New Byte[messageCount]
					For Local i:Int = 0 Until messageCount
						complete[i] = message[i]
					Next
					Local kind:Int = fragmentOpcode
					Local wasCompressed:Int = fragmentCompressed
					fragmentOpcode = 0
					fragmentCompressed = False
					messageCount = 0
					_Deliver(kind, complete, wasCompressed)
				End If
			Case 1, 2
				If fragmentOpcode Then _Fail(WebSocketProtocolError); Return
				If fin Then
					_Deliver(opcode, payload, compressed)
				Else
					fragmentOpcode = opcode
					fragmentCompressed = compressed
					messageCount = payload.length
					For Local i:Int = 0 Until payload.length
						message[i] = payload[i]
					Next
				End If
			Default
				_Fail(WebSocketProtocolError)
		End Select
	End Method

	Method _Parse()
		While rxCount >= 2
			Local first:Int = rx[0] & 255
			Local second:Int = rx[1] & 255
			Local fin:Int = (first & $80) <> 0
			Local opcode:Int = first & 15
			Local compressed:Int = (first & $40) <> 0
			If (first & $30) <> 0 Or (compressed And (Not codec Or opcode <> 1 And opcode <> 2)) Or ..
				(second & $80) = 0 Or ..
				(opcode <> 0 And opcode <> 1 And opcode <> 2 And ..
					opcode <> 8 And opcode <> 9 And opcode <> 10) Then
				_Fail(WebSocketProtocolError)
				Return
			End If
			Local length:Long = second & 127
			Local header:Int = 2
			If length = 126 Then
				If rxCount < 4 Then Return
				length = ((rx[2] & 255) Shl 8) | (rx[3] & 255)
				If length < 126 Then _Fail(WebSocketProtocolError); Return
				header = 4
			Else If length = 127 Then
				If rxCount < 10 Then Return
				If rx[2] <> 0 Or rx[3] <> 0 Or rx[4] <> 0 Or rx[5] <> 0 Then
					_Fail(WebSocketMessageTooBig)
					Return
				End If
				length = (Long(rx[6] & 255) Shl 24) | (Long(rx[7] & 255) Shl 16) | ..
					(Long(rx[8] & 255) Shl 8) | Long(rx[9] & 255)
				If length < 65536 Then _Fail(WebSocketProtocolError); Return
				header = 10
			End If
			If opcode >= 8 And (Not fin Or length > 125) Then _Fail(WebSocketProtocolError); Return
			If length > maxMessage Or length + header + 4 > rx.length Then
				_Fail(WebSocketMessageTooBig)
				Return
			End If
			Local total:Int = header + 4 + Int(length)
			If rxCount < total Then Return
			Local payload:Byte[] = New Byte[Int(length)]
			For Local i:Int = 0 Until payload.length
				payload[i] = rx[header + 4 + i] ~ rx[header + (i Mod 4)]
			Next
			For Local i:Int = total Until rxCount
				rx[i - total] = rx[i]
			Next
			rxCount :- total
			_Frame(opcode, fin, payload, compressed)
			If closing Then Return
		End While
	End Method
End Type

Private

Function _WSRotl:UInt(value:UInt, count:Int)
	Return (value Shl count) | (value Shr (32 - count))
End Function

' The WebSocket handshake always hashes a 24-byte key plus the 36-byte GUID.
' That fixed 60-byte input takes exactly two SHA-1 compression blocks.
Function _WSAccept:String(key:String)
	Local source:Byte[] = _WSBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
	Local padded:Byte[] = New Byte[128]
	For Local i:Int = 0 Until source.length
		padded[i] = source[i]
	Next
	padded[60] = $80
	padded[126] = 1
	padded[127] = $e0
	Local h0:UInt = $67452301
	Local h1:UInt = $efcdab89
	Local h2:UInt = $98badcfe
	Local h3:UInt = $10325476
	Local h4:UInt = $c3d2e1f0
	For Local block:Int = 0 To 1
		Local words:UInt[] = New UInt[80]
		For Local i:Int = 0 Until 16
			Local offset:Int = block * 64 + i * 4
			words[i] = (UInt(padded[offset] & 255) Shl 24) | ..
				(UInt(padded[offset + 1] & 255) Shl 16) | ..
				(UInt(padded[offset + 2] & 255) Shl 8) | UInt(padded[offset + 3] & 255)
		Next
		For Local i:Int = 16 Until 80
			words[i] = _WSRotl(words[i - 3] ~ words[i - 8] ~ ..
				words[i - 14] ~ words[i - 16], 1)
		Next
		Local a:UInt = h0
		Local b:UInt = h1
		Local c:UInt = h2
		Local d:UInt = h3
		Local e:UInt = h4
		For Local i:Int = 0 Until 80
			Local f:UInt
			Local k:UInt
			If i < 20
				f = (b & c) | ((b ~ $ffffffff) & d)
				k = $5a827999
			Else If i < 40
				f = b ~ c ~ d
				k = $6ed9eba1
			Else If i < 60
				f = (b & c) | (b & d) | (c & d)
				k = $8f1bbcdc
			Else
				f = b ~ c ~ d
				k = $ca62c1d6
			End If
			Local nextA:UInt = _WSRotl(a, 5) + f + e + k + words[i]
			e = d
			d = c
			c = _WSRotl(b, 30)
			b = a
			a = nextA
		Next
		h0 :+ a
		h1 :+ b
		h2 :+ c
		h3 :+ d
		h4 :+ e
	Next
	Local digest:Byte[] = New Byte[20]
	Local parts:UInt[] = [h0, h1, h2, h3, h4]
	For Local i:Int = 0 Until 5
		digest[i * 4] = Byte(parts[i] Shr 24)
		digest[i * 4 + 1] = Byte(parts[i] Shr 16)
		digest[i * 4 + 2] = Byte(parts[i] Shr 8)
		digest[i * 4 + 3] = Byte(parts[i])
	Next
	Return _WSBase64Encode(digest)
End Function

Function _WSBase64Encode:String(data:Byte[])
	Const alphabet:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	Local result:String = ""
	For Local i:Int = 0 Until data.length Step 3
		Local first:Int = data[i] & 255
		Local second:Int
		Local third:Int
		If i + 1 < data.length Then second = data[i + 1] & 255
		If i + 2 < data.length Then third = data[i + 2] & 255
		result :+ Chr(alphabet[(first Shr 2) & 63])
		result :+ Chr(alphabet[((first & 3) Shl 4) | (second Shr 4)])
		If i + 1 < data.length Then
			result :+ Chr(alphabet[((second & 15) Shl 2) | (third Shr 6)])
		Else
			result :+ "="
		End If
		If i + 2 < data.length Then
			result :+ Chr(alphabet[third & 63])
		Else
			result :+ "="
		End If
	Next
	Return result
End Function

Function _WSBytes:Byte[](value:String)
	Local count:Size_T
	Local ptr:Byte Ptr = value.ToUTF8String(count)
	Local result:Byte[] = New Byte[Int(count)]
	For Local i:Int = 0 Until result.length
		result[i] = ptr[i]
	Next
	If ptr Then MemFree(ptr)
	Return result
End Function

Function _WSTokenContains:Int(value:String, wanted:String)
	For Local token:String = EachIn value.ToLower().Split(",")
		If token.Trim() = wanted Then Return True
	Next
	Return False
End Function

Function _WSHeaderCount:Int(request:THTTPRequest, name:String)
	Local result:Int
	For Local field:THTTPField = EachIn request.headers
		If field And field.name = name Then result :+ 1
	Next
	Return result
End Function

Function _WSHeaderValues:String(request:THTTPRequest, name:String)
	Local values:String = ""
	For Local field:THTTPField = EachIn request.headers
		If field And field.name = name Then
			If values Then values :+ ","
			values :+ field.value
		End If
	Next
	Return values
End Function

Function _WSValidToken:Int(value:String)
	If Not value Then Return False
	For Local i:Int = 0 Until value.length
		Local c:Int = value[i]
		If c >= 48 And c <= 57 Or c >= 65 And c <= 90 Or ..
			c >= 97 And c <= 122 Then Continue
		If c = 33 Or c = 35 Or c = 36 Or c = 37 Or c = 38 Or ..
			c = 39 Or c = 42 Or c = 43 Or c = 45 Or c = 46 Or ..
			c = 94 Or c = 95 Or c = 96 Or c = 124 Or c = 126 Then Continue
		Return False
	Next
	Return True
End Function

' Invalid header is distinct from no mutually supported protocol.
Function _WSSelectSubprotocol:String(request:THTTPRequest, supported:String[])
	Local offers:String = _WSHeaderValues(request, "sec-websocket-protocol")
	If Not offers Then Return ""
	Local selected:String = ""
	For Local offered:String = EachIn offers.Split(",")
		Local name:String = offered.Trim()
		If Not _WSValidToken(name) Then Return Chr(0)
		If supported Then
			For Local candidate:String = EachIn supported
				If Not selected And candidate = name Then selected = name
			Next
		End If
	Next
	Return selected
End Function

Function _WSValidKey:Int(key:String)
	If key.length <> 24 Or key[22] <> 61 Or key[23] <> 61 Then Return False
	For Local i:Int = 0 Until 22
		If _WSBase64Value(key[i]) < 0 Then Return False
	Next
	Return (_WSBase64Value(key[21]) & 15) = 0
End Function

Function _WSBase64Value:Int(c:Int)
	If c >= 65 And c <= 90 Then Return c - 65
	If c >= 97 And c <= 122 Then Return c - 97 + 26
	If c >= 48 And c <= 57 Then Return c - 48 + 52
	If c = 43 Then Return 62
	If c = 47 Then Return 63
	Return -1
End Function

Function _WSValidCloseCode:Int(code:Int)
	If code >= 3000 And code <= 4999 Then Return True
	If code < 1000 Or code > 1014 Then Return False
	Return code <> 1004 And code <> 1005 And code <> 1006
End Function

Function _WSValidUTF8:Int(data:Byte[], offset:Int, count:Int)
	Local finish:Int = offset + count
	Local i:Int = offset
	While i < finish
		Local first:Int = data[i] & 255
		If first < $80 Then i :+ 1; Continue
		Local more:Int
		If first >= $c2 And first <= $df Then
			more = 1
		Else If first >= $e0 And first <= $ef Then
			more = 2
		Else If first >= $f0 And first <= $f4 Then
			more = 3
		Else
			Return False
		End If
		If i + more >= finish Then Return False
		Local second:Int = data[i + 1] & 255
		If second < $80 Or second > $bf Then Return False
		If first = $e0 And second < $a0 Then Return False
		If first = $ed And second > $9f Then Return False
		If first = $f0 And second < $90 Then Return False
		If first = $f4 And second > $8f Then Return False
		For Local j:Int = 2 To more
			Local nextByte:Int = data[i + j] & 255
			If nextByte < $80 Or nextByte > $bf Then Return False
		Next
		i :+ more + 1
	Wend
	Return True
End Function
