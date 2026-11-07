' Copy outside the repository and fill in your own network details.
SuperStrict
Framework BRL.StandardIO
Import BRL.EventQueue
Import Embedded.Network.WiFi
Import Embedded.Network.MQTT

Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"
Const BrokerHost:String = "<broker-ip-or-hostname>"

Global mqtt:TMQTTClient
Global nextSend:UInt

Function OnMQTT:Object(hookId:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If Not event Or event.source <> mqtt Then Return data
	Select event.id
		Case EVENT_MQTTCONNECTED
			Print "MQTT connected"
			nextSend = MilliSecs()
		Case EVENT_MQTTDISCONNECTED
			Print "MQTT disconnected: " + event.data
		Case EVENT_MQTTERROR
			Print "MQTT error: " + event.data
	End Select
	Return data
End Function

If NetworkName = "<ssid>" Or BrokerHost = "<broker-ip-or-hostname>" Then RuntimeError "Set network and broker details"
If WiFiInitialize() <> 0 Then RuntimeError "Wi-Fi initialization failed"
If WiFiConnectWait(NetworkName, NetworkPassword) <> 0 Then RuntimeError "Wi-Fi connection failed"

mqtt = New TMQTTClient
mqtt.host = BrokerHost
mqtt.clientId = "blitzmax-heartbeat"  ' Change this for each board.
AddHook EmitEventHook, OnMQTT
If mqtt.Connect() <> 0 Then Print "Initial MQTT attempt failed; reconnect is scheduled"

While True
	PollSystem()
	If mqtt.state = MQTTConnected And MilliSecs() - nextSend < UInt($80000000) Then
		Local result:Int = mqtt.PublishText("devices/blitzmax-heartbeat/uptime", "uptime_ms=" + MilliSecs())
		If result <> 0 Then Print "Publish failed: " + result
		nextSend = MilliSecs() + 10000
	End If
	Delay 10
Wend
