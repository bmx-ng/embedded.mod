' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Bounded NTP calendar synchronization for networked embedded targets.
about: The client uses one UDP request at a time. Call Service regularly for
nonblocking operation, or use SynchronizeNetworkTime for a bounded blocking
one-shot synchronization.
End Rem
Module Embedded.Network.Time
?embedded and (pico or esp32 or esp8266)

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import BRL.Socket
Import BRL.System
Import Embedded.System.Calendar

Const NetworkTimeStopped:Int = 0
Const NetworkTimeWaiting:Int = 1
Const NetworkTimeSynchronized:Int = 2
Const NetworkTimeFailed:Int = -1

Const NetworkTimeErrorInvalidConfiguration:Int = -1
Const NetworkTimeErrorDNS:Int = -2
Const NetworkTimeErrorSocket:Int = -3
Const NetworkTimeErrorSend:Int = -4
Const NetworkTimeErrorTimeout:Int = -5
Const NetworkTimeErrorResponse:Int = -6
Const NetworkTimeErrorCalendar:Int = -7

Rem
bbdoc: Emitted by Service after a valid NTP response updates the calendar.
about: The event source is the TNetworkTimeClient.
End Rem
Global EVENT_NETWORKTIMESYNCHRONIZED:Int = AllocUserEventId("NetworkTimeSynchronized")
Rem
bbdoc: Emitted by Service when an NTP attempt fails.
about: The event source is the TNetworkTimeClient and event.data is a
NetworkTimeError constant. With automatic updates enabled, the client retries
after retryIntervalMs.
End Rem
Global EVENT_NETWORKTIMEERROR:Int = AllocUserEventId("NetworkTimeError")

Private

Const _NTPPacketBytes:Int = 48
Const _NTPUnixEpochOffset:ULong = 2208988800:ULong
Const _NTPSecondsPerEra:ULong = 4294967296:ULong

Function _NetworkTimeDateTime:SDateTime(seconds:Long, fractionNanoseconds:Long)
	Local days:Long = seconds / 86400
	Local withinDay:Long = seconds Mod 86400
	If withinDay < 0 Then
		withinDay :+ 86400
		days :- 1
	End If
	Local shifted:Long = days + 719468
	Local era:Long
	If shifted >= 0 Then
		era = shifted / 146097
	Else
		era = (shifted - 146096) / 146097
	End If
	Local dayOfEra:Int = Int(shifted - era * 146097)
	Local yearOfEra:Int = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - ..
		dayOfEra / 146096) / 365
	Local year:Int = yearOfEra + Int(era) * 400
	Local dayOfYear:Int = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - ..
		yearOfEra / 100)
	Local monthPrime:Int = (5 * dayOfYear + 2) / 153
	Local day:Int = dayOfYear - (153 * monthPrime + 2) / 5 + 1
	Local month:Int
	If monthPrime < 10 Then
		month = monthPrime + 3
	Else
		month = monthPrime - 9
	End If
	If month <= 2 Then year :+ 1
	Return New SDateTime(year, month, day, Int(withinDay / 3600), ..
		Int((withinDay / 60) Mod 60), Int(withinDay Mod 60), ..
		Int(fractionNanoseconds / 1000000), True, 0, 0)
End Function

Public

Rem
bbdoc: A service-driven NTP client which maintains the embedded UTC calendar.
End Rem
Type TNetworkTimeClient
	Field server:String = "pool.ntp.org"
	Field port:Int = 123
	Field timeoutMs:UInt = 10000
	Field updateIntervalMs:UInt = 3600000
	Field retryIntervalMs:UInt = 30000
	Field autoUpdate:Int = True

	Field state:Int = NetworkTimeStopped
	Field lastError:Int
	Field lastTime:SDateTime
	Field lastRoundTripMs:UInt
	Field synchronizationCount:UInt

	Private
	Field socket:TSocket
	Field requestStarted:UInt
	Field nextAttempt:UInt
	Field running:Int

	Method _CloseSocket()
		If socket Then CloseSocket socket
		socket = Null
	End Method

	Method _Fail:Int(code:Int)
		_CloseSocket()
		state = NetworkTimeFailed
		lastError = code
		If autoUpdate And running Then nextAttempt = MilliSecs() + retryIntervalMs
		EmitEvent(CreateEvent(EVENT_NETWORKTIMEERROR, Self, code))
		Return code
	End Method

	Method _Begin:Int()
		_CloseSocket()
		If Not server Or port < 1 Or port > 65535 Or timeoutMs = 0 Then
			Return _Fail(NetworkTimeErrorInvalidConfiguration)
		End If
		Local hints:TAddrInfo = New TAddrInfo(AF_INET_, SOCK_DGRAM_)
		Local addresses:TAddrInfo[] = AddrInfo(server, String(port), hints)
		If Not addresses Or addresses.length = 0 Then Return _Fail(NetworkTimeErrorDNS)
		socket = TSocket.Create(addresses[0])
		If Not socket Or Not ConnectSocket(socket, addresses[0]) Then
			Return _Fail(NetworkTimeErrorSocket)
		End If
		Local packet:Byte[_NTPPacketBytes]
		packet[0] = $23 ' No leap warning, NTP v4, client mode.
		If socket.TrySend(packet, Size_T(packet.length)) <> packet.length Then
			Return _Fail(NetworkTimeErrorSend)
		End If
		requestStarted = MilliSecs()
		state = NetworkTimeWaiting
		lastError = 0
		Return 0
	End Method

	Method _Accept:Int(packet:Byte[], count:Int)
		If count < _NTPPacketBytes Then Return _Fail(NetworkTimeErrorResponse)
		Local leap:Int = (packet[0] Shr 6) & 3
		Local version:Int = (packet[0] Shr 3) & 7
		Local mode:Int = packet[0] & 7
		Local stratum:Int = packet[1] & $ff
		If leap = 3 Or version < 3 Or (mode <> 4 And mode <> 5) Or ..
				stratum < 1 Or stratum > 15 Then
			Return _Fail(NetworkTimeErrorResponse)
		End If
		' Our request transmit timestamp is zero; a conforming reply copies it
		' into the originate field.
		For Local i:Int = 24 Until 32
			If packet[i] <> 0 Then Return _Fail(NetworkTimeErrorResponse)
		Next
		Local ntpSeconds:ULong = (ULong(packet[40] & $ff) Shl 24) | ..
			(ULong(packet[41] & $ff) Shl 16) | (ULong(packet[42] & $ff) Shl 8) | ..
			ULong(packet[43] & $ff)
		Local fraction:ULong = (ULong(packet[44] & $ff) Shl 24) | ..
			(ULong(packet[45] & $ff) Shl 16) | (ULong(packet[46] & $ff) Shl 8) | ..
			ULong(packet[47] & $ff)
		If ntpSeconds = 0 Then Return _Fail(NetworkTimeErrorResponse)
		' Select the post-2036 era when the 32-bit NTP seconds field has wrapped.
		If ntpSeconds < _NTPUnixEpochOffset Then ntpSeconds :+ _NTPSecondsPerEra
		Local unixSeconds:Long = Long(ntpSeconds - _NTPUnixEpochOffset)
		Local fractionNanoseconds:Long = Long((fraction * 1000000000:ULong) Shr 32)
		Local value:SDateTime = _NetworkTimeDateTime(unixSeconds, fractionNanoseconds)
		If value.year < 1970 Or Not CalendarStart(value) Then
			Return _Fail(NetworkTimeErrorCalendar)
		End If
		_CloseSocket()
		lastTime = value
		lastRoundTripMs = MilliSecs() - requestStarted
		synchronizationCount :+ 1
		state = NetworkTimeSynchronized
		lastError = 0
		If autoUpdate Then nextAttempt = MilliSecs() + updateIntervalMs
		EmitEvent(CreateEvent(EVENT_NETWORKTIMESYNCHRONIZED, Self))
		Return 1
	End Method

	Public

	Rem
	bbdoc: Starts the first NTP synchronization attempt.
	returns: Zero when the request was started, or a NetworkTimeError value.
	End Rem
	Method Start:Int()
		Stop()
		running = True
		Return _Begin()
	End Method

	Rem
	bbdoc: Stops synchronization and closes its UDP socket.
	End Rem
	Method Stop()
		_CloseSocket()
		running = False
		state = NetworkTimeStopped
		nextAttempt = 0
	End Method

	Rem
	bbdoc: Services a pending request and scheduled retry without waiting.
	returns: One after a calendar update, zero when there is no state change, or
	a NetworkTimeError value when an attempt fails.
	End Rem
	Method Service:Int()
		If Not running Then Return 0
		If state = NetworkTimeWaiting Then
			Local packet:Byte[_NTPPacketBytes]
			Local amount:Int = socket.TryRecv(packet, Size_T(packet.length))
			If amount > 0 Then Return _Accept(packet, amount)
			If amount <> -2 Then Return _Fail(NetworkTimeErrorSocket)
			If MilliSecs() - requestStarted >= timeoutMs Then
				Return _Fail(NetworkTimeErrorTimeout)
			End If
			Return 0
		End If
		If autoUpdate And (state = NetworkTimeSynchronized Or state = NetworkTimeFailed) And ..
				MilliSecs() - nextAttempt < UInt($80000000) Then
			Return _Begin()
		End If
		Return 0
	End Method

	Method IsRunning:Int()
		Return running
	End Method
End Type

Rem
bbdoc: Performs one bounded NTP synchronization and updates the UTC calendar.
returns: True on success.
about: The board must already have a working IP connection. For periodic,
nonblocking synchronization use TNetworkTimeClient and call Service regularly.
End Rem
Function SynchronizeNetworkTime:Int(server:String = "pool.ntp.org", ..
		timeoutMs:UInt = 10000, port:Int = 123)
	Local client:TNetworkTimeClient = New TNetworkTimeClient
	client.server = server
	client.port = port
	client.timeoutMs = timeoutMs
	client.autoUpdate = False
	If client.Start() <> 0 Then Return False
	While client.state = NetworkTimeWaiting
		client.Service()
		If client.state = NetworkTimeWaiting Then Delay 1
	Wend
	Local result:Int = client.state = NetworkTimeSynchronized
	client.Stop()
	Return result
End Function
?
