' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: MQTT 3.1.1 client for supported embedded network targets.
about: Connect an IP interface before using this module. MQTT events are delivered while the application calls `PollSystem()` or `PollEvent()`.
End Rem
Module Embedded.Network.MQTT
?embedded and (pico or esp32)

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import BRL.System

Rem
bbdoc: The client is stopped or disconnected from the broker.
End Rem
Const MQTTDisconnected:Int = 0
Rem
bbdoc: The client is attempting to connect to the broker.
End Rem
Const MQTTConnecting:Int = 1
Rem
bbdoc: The broker has accepted the client connection.
End Rem
Const MQTTConnected:Int = 2
Rem
bbdoc: A local MQTT API call failed validation or could not be started.
End Rem
Const MQTTError:Int = -1
Rem
bbdoc: Maximum UTF-8 topic bytes in an incoming message.
End Rem
Const MQTTMaximumTopicBytes:Int = 127
Rem
bbdoc: Maximum payload bytes in an incoming message.
End Rem
Const MQTTMaximumPayloadBytes:Int = 1024

Rem
bbdoc: Emitted when the broker accepts the connection.
about: The event source is the `TMQTTClient`. Remembered subscriptions are restored before this event is emitted.
End Rem
Global EVENT_MQTTCONNECTED:Int = AllocUserEventId("MQTTConnected")
Rem
bbdoc: Emitted when the connection closes or an attempt fails.
about: The event source is the `TMQTTClient`; `event.data` contains the native status code.
End Rem
Global EVENT_MQTTDISCONNECTED:Int = AllocUserEventId("MQTTDisconnected")
Rem
bbdoc: Emitted when a subscribed message arrives.
about: The event source is the `TMQTTClient`; `event.extra` contains a `TMQTTMessage`.
End Rem
Global EVENT_MQTTMESSAGE:Int = AllocUserEventId("MQTTMessage")
Rem
bbdoc: Emitted for a native MQTT error or an oversized incoming message.
about: The event source is the `TMQTTClient`; `event.data` contains the error code.
End Rem
Global EVENT_MQTTERROR:Int = AllocUserEventId("MQTTError")

Rem
bbdoc: An incoming MQTT message delivered through `EVENT_MQTTMESSAGE`.
End Rem
Type TMQTTMessage
	Rem
	bbdoc: Message topic decoded from UTF-8.
	End Rem
	Field topic:String
	Rem
	bbdoc: Message body as raw bytes, including any embedded zero bytes.
	End Rem
	Field payload:Byte[]
	Rem
	bbdoc: Incoming quality-of-service level; always zero on Pico because lwIP does not supply it.
	End Rem
	Field qos:Int
	Rem
	bbdoc: Whether the broker marked the message retained; always zero on Pico.
	End Rem
	Field retained:Int

	Rem
	bbdoc: Decodes the payload as UTF-8 text.
	returns: The decoded text, or an empty string for an empty payload.
	End Rem
	Method Text:String()
		If Not payload Or payload.length = 0 Then Return ""
		Return String.FromUTF8Bytes(Varptr payload[0], payload.length)
	End Method
End Type

Private

Const NativeConnected:Int = 1
Const NativeDisconnected:Int = 2
Const NativeMessage:Int = 3
Const NativeError:Int = 4

Extern "C"
	Function _Start:Int(host:Byte Ptr, port:Int, clientId:Byte Ptr, user:Byte Ptr, password:Byte Ptr, keepAlive:Int) = "bmx_embedded_mqtt_start"
	Function _Stop() = "bmx_embedded_mqtt_stop"
	Function _State:Int() = "bmx_embedded_mqtt_state"
	Function _Publish:Int(topic:Byte Ptr, payload:Byte Ptr, length:Int, qos:Int, retained:Int) = "bmx_embedded_mqtt_publish"
	Function _Subscribe:Int(topic:Byte Ptr, qos:Int) = "bmx_embedded_mqtt_subscribe"
	Function _Take:Int(kind:Int Var, code:Int Var, topic:Byte Ptr, topicLength:Int Var, payload:Byte Ptr, payloadLength:Int Var, qos:Int Var, retained:Int Var) = "bmx_embedded_mqtt_take_event"
	Function _Dropped:UInt() = "bmx_embedded_mqtt_dropped_events"
End Extern

Global _active:TMQTTClient

Function _Poll:Object(hookId:Int, data:Object, context:Object)
	If Not _active Then Return data
	Local client:TMQTTClient = _active
	Local kind:Int, code:Int, topicLength:Int, payloadLength:Int, qos:Int, retained:Int
	Local topic:Byte[MQTTMaximumTopicBytes + 1]
	Local payload:Byte[MQTTMaximumPayloadBytes]
	While _active = client And _Take(kind, code, topic, topicLength, payload, payloadLength, qos, retained)
		Select kind
			Case NativeConnected
				client.state = MQTTConnected
				client.lastError = 0
				For Local i:Int = 0 Until client.subscriptionCount
					client.Subscribe(client.subscriptions[i], client.subscriptionQoS[i])
				Next
				EmitEvent(CreateEvent(EVENT_MQTTCONNECTED, client))
			Case NativeDisconnected
				client.state = MQTTDisconnected
				client.lastError = code
				client.nextRetry = MilliSecs() + client.reconnectDelayMs
				EmitEvent(CreateEvent(EVENT_MQTTDISCONNECTED, client, code))
			Case NativeError
				client.lastError = code
				EmitEvent(CreateEvent(EVENT_MQTTERROR, client, code))
			Case NativeMessage
				Local message:TMQTTMessage = New TMQTTMessage
				message.topic = String.FromUTF8Bytes(topic, topicLength)
				message.payload = New Byte[payloadLength]
				If payloadLength Then MemCopy(Varptr message.payload[0], Varptr payload[0], Size_T(payloadLength))
				message.qos = qos
				message.retained = retained
				EmitEvent(CreateEvent(EVENT_MQTTMESSAGE, client, qos, retained, 0, 0, message))
		End Select
	Wend
	If client.autoReconnect And client.state = MQTTDisconnected And MilliSecs() - client.nextRetry < UInt($80000000) Then
		client.Connect()
	End If
	Return data
End Function

Public

Rem
bbdoc: One MQTT client connection to a broker.
about: Configure the connection fields before calling `Connect()`. Only one instance can be active at a time. Call `PollSystem()` or `PollEvent()` regularly to receive events and drive retries.
End Rem
Type TMQTTClient
	Rem
	bbdoc: Broker IP address or hostname, without a URI scheme.
	End Rem
	Field host:String
	Rem
	bbdoc: Broker TCP port; defaults to 1883.
	End Rem
	Field port:Int = 1883
	Rem
	bbdoc: Client identifier; use a unique value for each connected device.
	End Rem
	Field clientId:String
	Rem
	bbdoc: Optional broker username, separate from Wi-Fi credentials.
	End Rem
	Field username:String
	Rem
	bbdoc: Optional broker password, separate from Wi-Fi credentials.
	End Rem
	Field password:String
	Rem
	bbdoc: MQTT keep-alive interval in seconds; defaults to 60.
	End Rem
	Field keepAliveSeconds:Int = 60
	Rem
	bbdoc: Whether to retry a failed or closed connection automatically; defaults to True.
	End Rem
	Field autoReconnect:Int = True
	Rem
	bbdoc: Delay between automatic connection attempts in milliseconds; defaults to 5000.
	End Rem
	Field reconnectDelayMs:UInt = 5000
	Rem
	bbdoc: Current connection state: `MQTTDisconnected`, `MQTTConnecting`, or `MQTTConnected`.
	End Rem
	Field state:Int = MQTTDisconnected
	Rem
	bbdoc: Most recent native connection or start error code; zero after connection.
	End Rem
	Field lastError:Int
	Rem
	bbdoc: Next scheduled retry time in milliseconds; managed internally.
	End Rem
	Field nextRetry:UInt
	Rem
	bbdoc: Remembered subscription topics; managed by `Subscribe()`.
	End Rem
	Field subscriptions:String[16]
	Rem
	bbdoc: Requested QoS for each remembered subscription; managed by `Subscribe()`.
	End Rem
	Field subscriptionQoS:Int[16]
	Rem
	bbdoc: Number of remembered subscriptions; managed by `Subscribe()`.
	End Rem
	Field subscriptionCount:Int

	Rem
	bbdoc: Starts an asynchronous broker connection attempt.
	returns: Zero if the local adapter accepted the attempt, or an error code if it could not start.
	about: Wait for `EVENT_MQTTCONNECTED` before publishing. A zero return does not mean the broker accepted the connection. Automatic retries require regular polling.
	End Rem
	Method Connect:Int()
		If _active And _active <> Self Then Return MQTTError
		If _active = Self And state <> MQTTDisconnected Then Return 0
		If Not host Or host.length = 0 Or Not clientId Or clientId.length = 0 Or port < 1 Or port > 65535 Then Return MQTTError
		Local h:Byte Ptr = host.ToUTF8String()
		Local id:Byte Ptr = clientId.ToUTF8String()
		Local u:Byte Ptr, p:Byte Ptr
		If username Then u = username.ToUTF8String()
		If password Then p = password.ToUTF8String()
		_active = Self
		Local result:Int = _Start(h, port, id, u, p, keepAliveSeconds)
		MemFree(h); MemFree(id)
		If u Then MemFree(u)
		If p Then MemFree(p)
		If result = 0 Then
			state = MQTTConnecting
		Else
			lastError = result
			state = MQTTDisconnected
			nextRetry = MilliSecs() + reconnectDelayMs
		End If
		Return result
	End Method

	Rem
	bbdoc: Stops this client and disables automatic reconnection.
	about: Set `autoReconnect` to True before a later `Connect()` call if retries should resume.
	End Rem
	Method Disconnect()
		autoReconnect = False
		If _active = Self Then
			_Stop()
			_active = Null
		End If
		state = MQTTDisconnected
	End Method

	Rem
	bbdoc: Publishes a buffer as one MQTT message.
	param: Topic to publish to.
	param: Address of the payload bytes; may be Null only when the length is zero.
	param: Number of payload bytes.
	param: Requested quality-of-service level, from zero to two.
	param: Whether the broker should retain the message.
	returns: Zero if the local adapter accepted the publish request, or an error code.
	about: Keep the payload valid until this method returns. A zero return does not confirm broker delivery.
	End Rem
	Method Publish:Int(topic:String, payload:Byte Ptr, length:Int, qos:Int = 0, retained:Int = False)
		If _active <> Self Or state <> MQTTConnected Or Not topic Or topic.length = 0 Or length < 0 Or (length > 0 And Not payload) Or qos < 0 Or qos > 2 Then Return MQTTError
		Local t:Byte Ptr = topic.ToUTF8String()
		Local result:Int = _Publish(t, payload, length, qos, retained)
		MemFree(t)
		Return result
	End Method

	Rem
	bbdoc: Publishes a byte array as one MQTT message.
	param: Topic to publish to.
	param: Payload bytes; Null or an empty array sends an empty message.
	param: Requested quality-of-service level, from zero to two.
	param: Whether the broker should retain the message.
	returns: Zero if the local adapter accepted the publish request, or an error code.
	about: A zero return does not confirm broker delivery.
	End Rem
	Method Publish:Int(topic:String, payload:Byte[], qos:Int = 0, retained:Int = False)
		If Not payload Or payload.length = 0 Then Return Publish(topic, Null, 0, qos, retained)
		Return Publish(topic, Varptr payload[0], payload.length, qos, retained)
	End Method

	Rem
	bbdoc: Encodes text as UTF-8 and publishes it as one MQTT message.
	param: Topic to publish to.
	param: Text to send.
	param: Requested quality-of-service level, from zero to two.
	param: Whether the broker should retain the message.
	returns: Zero if the local adapter accepted the publish request, or an error code.
	about: A zero return does not confirm broker delivery.
	End Rem
	Method PublishText:Int(topic:String, value:String, qos:Int = 0, retained:Int = False)
		If Not topic Or topic.length = 0 Or Not value Then Return MQTTError
		Local length:Size_T
		Local bytes:Byte Ptr = value.ToUTF8String(length)
		Local t:Byte Ptr = topic.ToUTF8String()
		Local result:Int = MQTTError
		If _active = Self And state = MQTTConnected And qos >= 0 And qos <= 2 Then result = _Publish(t, bytes, Int(length), qos, retained)
		MemFree(t); MemFree(bytes)
		Return result
	End Method

	Rem
	bbdoc: Remembers a topic subscription and submits it when connected.
	param: Topic filter to subscribe to.
	param: Requested quality-of-service level, from zero to two.
	returns: Zero when remembered while disconnected or accepted locally while connected, or an error code.
	about: Up to 16 subscriptions are remembered and replayed after each connection. Calling again for the same topic updates its requested QoS.
	End Rem
	Method Subscribe:Int(topic:String, qos:Int = 0)
		If Not topic Or topic.length = 0 Or qos < 0 Or qos > 2 Then Return MQTTError
		Local found:Int = False
		For Local i:Int = 0 Until subscriptionCount
			If subscriptions[i] = topic Then
				subscriptionQoS[i] = qos
				found = True
				Exit
			End If
		Next
		If Not found Then
			If subscriptionCount = subscriptions.length Then Return MQTTError
			subscriptions[subscriptionCount] = topic
			subscriptionQoS[subscriptionCount] = qos
			subscriptionCount :+ 1
		End If
		If _active <> Self Or state <> MQTTConnected Then Return 0
		Local t:Byte Ptr = topic.ToUTF8String()
		Local result:Int = _Subscribe(t, qos)
		MemFree(t)
		Return result
	End Method

	Rem
	bbdoc: Counts MQTT events displaced from the native queue when it fills.
	returns: Total dropped events since startup.
	about: Poll frequently when messages arrive; the queue holds eight events.
	End Rem
	Method DroppedEvents:UInt()
		Return _Dropped()
	End Method
End Type

AddHook PollSystemHook, _Poll
?
