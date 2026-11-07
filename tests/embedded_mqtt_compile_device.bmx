SuperStrict
Import Embedded.Network.MQTT
Import BRL.StandardIO

Local client:TMQTTClient = New TMQTTClient
client.host = "127.0.0.1"
client.clientId = "mqtt-compile-test"
client.Subscribe("test/topic", 1)
If client.state <> MQTTDisconnected Then RuntimeError "initial MQTT state"
Print "MQTT_COMPILE_OK"
