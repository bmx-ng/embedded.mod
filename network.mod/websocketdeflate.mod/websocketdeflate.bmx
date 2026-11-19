' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional RFC 7692 permessage-deflate codec for Embedded.Network.WebSocket.
about: Import this module and opt in per route. Both directions use no context
takeover, so native compression memory is released after each message.
End Rem
Module Embedded.Network.WebSocketDeflate
?not win32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Network.WebSocket
Import "../../../archive.mod/zlib.mod/zlib/adler32.c"
Import "../../../archive.mod/zlib.mod/zlib/crc32.c"
Import "../../../archive.mod/zlib.mod/zlib/deflate.c"
Import "../../../archive.mod/zlib.mod/zlib/inflate.c"
Import "../../../archive.mod/zlib.mod/zlib/inffast.c"
Import "../../../archive.mod/zlib.mod/zlib/inftrees.c"
Import "../../../archive.mod/zlib.mod/zlib/trees.c"
Import "../../../archive.mod/zlib.mod/zlib/zutil.c"
Import "deflate.c"

Extern
	Function _ws_deflate:Int(source:Byte Ptr, sourceLength:Int, output:Byte Ptr, outputCapacity:Int)
	Function _ws_inflate:Int(source:Byte Ptr, sourceLength:Int, output:Byte Ptr, outputCapacity:Int)
End Extern

Rem
bbdoc: Optional permessage-deflate factory for a WebSocket upgrade route.
about: Pass Create() to THTTPWebSocketUpgrade.SetCompressionFactory. A client
must offer client_max_window_bits for this bounded 9-bit negotiation.
End Rem
Type THTTPWebSocketDeflateFactory Implements IHTTPWebSocketCompressionFactory
	Rem
	bbdoc: Creates a factory to negotiate compression per connection.
	returns: A factory for THTTPWebSocketUpgrade.SetCompressionFactory.
	End Rem
	Function Create:THTTPWebSocketDeflateFactory()
		Return New THTTPWebSocketDeflateFactory
	End Function

	Rem
	bbdoc: Accepts a compatible permessage-deflate offer.
	param: Combined extension offers from the client's handshake.
	returns: A new codec, or Null when no compatible offer is present.
	End Rem
	Method Negotiate:IHTTPWebSocketCompression(offers:String)
		For Local offer:String = EachIn offers.Split(",")
			Local parts:String[] = offer.Split(";")
			If parts.length = 0 Or parts[0].Trim().ToLower() <> "permessage-deflate" Then Continue
			Local seen:Int
			Local valid:Int = True
			For Local i:Int = 1 Until parts.length
				Local parameter:String = parts[i].Trim().ToLower()
				Select parameter
					Case "server_no_context_takeover"
						If seen & 1 Then valid = False
						seen :| 1
					Case "client_no_context_takeover"
						If seen & 2 Then valid = False
						seen :| 2
					Default
						If parameter = "client_max_window_bits" Or ..
							parameter.StartsWith("client_max_window_bits=") And ..
							_WSDeflateWindow(parameter[23..]) >= 9 Then
							If seen & 8 Then valid = False
							seen :| 8
						Else If parameter.StartsWith("server_max_window_bits=") And ..
							_WSDeflateWindow(parameter[23..]) >= 9 Then
							If seen & 4 Then valid = False
							seen :| 4
						Else
							valid = False
						End If
				End Select
			Next
			If valid And (seen & 8) Then Return New THTTPWebSocketDeflate
		Next
		Return Null
	End Method
End Type

Function _WSDeflateWindow:Int(value:String)
	If value.length <> 1 And value.length <> 2 Then Return 0
	For Local i:Int = 0 Until value.length
		If value[i] < 48 Or value[i] > 57 Then Return 0
	Next
	Local bits:Int = value.ToInt()
	If bits < 8 Or bits > 15 Or String(bits) <> value Then Return 0
	Return bits
End Function

Rem
bbdoc: Per-connection codec created by THTTPWebSocketDeflateFactory.
about: This is normally managed by the WebSocket upgrade handler.
End Rem
Type THTTPWebSocketDeflate Implements IHTTPWebSocketCompression
	Field lastDecodeError:Int = WebSocketInvalidData

	Rem
	bbdoc: Describes the negotiated 9-bit, no-context-takeover extension.
	returns: Value for the Sec-WebSocket-Extensions response header.
	End Rem
	Method ResponseHeader:String()
		Return "permessage-deflate; server_no_context_takeover; client_no_context_takeover; server_max_window_bits=9; client_max_window_bits=9"
	End Method

	Rem
	bbdoc: Compresses one outgoing WebSocket message.
	param: Complete uncompressed message bytes.
	returns: Encoded bytes, or Null if compression fails.
	End Rem
	Method Encode:Byte[](data:Byte[])
		Local output:Byte[] = New Byte[data.length + 64]
		Local count:Int = _ws_deflate(Varptr data[0], data.length, Varptr output[0], output.length)
		If count < 0 Then Return Null
		Return output[..count]
	End Method

	Rem
	bbdoc: Decompresses one message within the route's size limit.
	param: Complete compressed message bytes.
	param: Maximum permitted decoded bytes.
	returns: Decoded bytes, or Null for invalid data or a limit failure.
	End Rem
	Method Decode:Byte[](data:Byte[], maxOutput:Int)
		Local output:Byte[] = New Byte[maxOutput + 1]
		Local input:Byte Ptr
		If data.length Then input = Varptr data[0]
		Local count:Int = _ws_inflate(input, data.length, Varptr output[0], output.length)
		If count < 0 Or count > maxOutput Then
			lastDecodeError = WebSocketInvalidData
			If count = -2 Or count > maxOutput Then lastDecodeError = WebSocketMessageTooBig
			If count = -3 Then lastDecodeError = WebSocketInternalError
			Return Null
		End If
		Return output[..count]
	End Method

	Rem
	bbdoc: Gets the close code for the latest decompression failure.
	returns: Invalid-data, message-too-big or internal-error close code.
	End Rem
	Method DecodeFailureCode:Int()
		Return lastDecodeError
	End Method
End Type
