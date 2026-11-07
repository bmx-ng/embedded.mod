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

Function OnMQTT:Object(hookId:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If Not event Or event.source <> mqtt Then Return data
	Select event.id
		Case EVENT_MQTTCONNECTED
			Print "MQTT connected; waiting for commands"
		Case EVENT_MQTTDISCONNECTED
			Print "MQTT disconnected: " + event.data
		Case EVENT_MQTTERROR
			Print "MQTT error: " + event.data
		Case EVENT_MQTTMESSAGE
			Local message:TMQTTMessage = TMQTTMessage(event.extra)
			If message.topic = "devices/blitzmax-command/command" Then
				Select message.Text()
					Case "on"
						Print "Command: on"
					Case "off"
						Print "Command: off"
					Default
						Print "Unknown command: " + message.Text()
				End Select
			End If
	End Select
	Return data
End Function

If NetworkName = "<ssid>" Or BrokerHost = "<broker-ip-or-hostname>" Then RuntimeError "Set network and broker details"
If WiFiInitialize() <> 0 Then RuntimeError "Wi-Fi initialization failed"
If WiFiConnectWait(NetworkName, NetworkPassword) <> 0 Then RuntimeError "Wi-Fi connection failed"

mqtt = New TMQTTClient
mqtt.host = BrokerHost
mqtt.clientId = "blitzmax-command"  ' Change this for each board.
mqtt.Subscribe("devices/blitzmax-command/command", 1)
AddHook EmitEventHook, OnMQTT
If mqtt.Connect() <> 0 Then Print "Initial MQTT attempt failed; reconnect is scheduled"

While True
	PollSystem()
	Delay 10
Wend
