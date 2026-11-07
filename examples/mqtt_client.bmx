' Copy this file outside the module before filling in local Wi-Fi and broker details.
SuperStrict
Framework BRL.StandardIO
Import BRL.EventQueue
Import Embedded.Network.WiFi
Import Embedded.Network.MQTT

Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"
Const BrokerHost:String = "<broker-ip-or-hostname>"

Global mqtt:TMQTTClient

Function OnMQTT:Object(hookId:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If Not event Or event.source <> mqtt Then Return data
	Select event.id
		Case EVENT_MQTTCONNECTED
			Print "MQTT connected"
			mqtt.PublishText("blitzmax/example", "hello from BlitzMax", 1)
		Case EVENT_MQTTDISCONNECTED
			Print "MQTT disconnected: " + event.data
		Case EVENT_MQTTERROR
			Print "MQTT error: " + event.data
		Case EVENT_MQTTMESSAGE
			Local message:TMQTTMessage = TMQTTMessage(event.extra)
			Print message.topic + ": " + message.Text()
	End Select
	Return data
End Function

If NetworkName = "<ssid>" Or BrokerHost = "<broker-ip-or-hostname>" Then RuntimeError "Set network and broker details"
If WiFiInitialize() <> 0 Then RuntimeError "Wi-Fi initialization failed"
If WiFiConnectWait(NetworkName, NetworkPassword) <> 0 Then RuntimeError "Wi-Fi connection failed"

mqtt = New TMQTTClient
mqtt.host = BrokerHost
mqtt.clientId = "blitzmax-example"
mqtt.Subscribe("blitzmax/example", 1)
AddHook EmitEventHook, OnMQTT
If mqtt.Connect() <> 0 Then Print "Initial MQTT attempt failed; reconnect is scheduled"

While True
	PollSystem()
	Delay 10
Wend
