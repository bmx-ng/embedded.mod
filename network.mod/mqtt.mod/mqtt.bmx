' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict
Module Embedded.Network.MQTT
?embedded and (pico or esp32)

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import BRL.System

Const MQTTDisconnected:Int = 0
Const MQTTConnecting:Int = 1
Const MQTTConnected:Int = 2
Const MQTTError:Int = -1
Const MQTTMaximumTopicBytes:Int = 127
Const MQTTMaximumPayloadBytes:Int = 1024

Global EVENT_MQTTCONNECTED:Int = AllocUserEventId("MQTTConnected")
Global EVENT_MQTTDISCONNECTED:Int = AllocUserEventId("MQTTDisconnected")
Global EVENT_MQTTMESSAGE:Int = AllocUserEventId("MQTTMessage")
Global EVENT_MQTTERROR:Int = AllocUserEventId("MQTTError")

Type TMQTTMessage
	Field topic:String
	Field payload:Byte[]
	Field qos:Int
	Field retained:Int

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

Type TMQTTClient
	Field host:String
	Field port:Int = 1883
	Field clientId:String
	Field username:String
	Field password:String
	Field keepAliveSeconds:Int = 60
	Field autoReconnect:Int = True
	Field reconnectDelayMs:UInt = 5000
	Field state:Int = MQTTDisconnected
	Field lastError:Int
	Field nextRetry:UInt
	Field subscriptions:String[16]
	Field subscriptionQoS:Int[16]
	Field subscriptionCount:Int

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
	about: Keep payload valid until this method returns. A zero length may use a Null pointer.
	End Rem
	Method Publish:Int(topic:String, payload:Byte Ptr, length:Int, qos:Int = 0, retained:Int = False)
		If _active <> Self Or state <> MQTTConnected Or Not topic Or topic.length = 0 Or length < 0 Or (length > 0 And Not payload) Or qos < 0 Or qos > 2 Then Return MQTTError
		Local t:Byte Ptr = topic.ToUTF8String()
		Local result:Int = _Publish(t, payload, length, qos, retained)
		MemFree(t)
		Return result
	End Method

	Method Publish:Int(topic:String, payload:Byte[], qos:Int = 0, retained:Int = False)
		If Not payload Or payload.length = 0 Then Return Publish(topic, Null, 0, qos, retained)
		Return Publish(topic, Varptr payload[0], payload.length, qos, retained)
	End Method

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

	Method DroppedEvents:UInt()
		Return _Dropped()
	End Method
End Type

AddHook PollSystemHook, _Poll
?
