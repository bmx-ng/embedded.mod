# MQTT on Pico W and ESP32

`Embedded.Network.MQTT` is an MQTT 3.1.1 client for Pico W, Pico 2 W, and
network-capable ESP32 boards. To try it, you need:

- A broker reachable from the board, such as one running on your LAN. The
  module is a client; it does not run a broker.
- The board's Wi-Fi name and password, or an initialized Ethernet connection
  on a supported ESP32 board.
- The broker's LAN IP address or hostname. The default port is 1883, using
  plain TCP.

## Get a message flowing

1. Copy [mqtt_client.bmx](../../examples/mqtt_client.bmx) **outside this
   repository**. Enter your Wi-Fi name, Wi-Fi password, and broker IP address
   in the three constants at the top. Use a unique `clientId` for each board.
2. From the BlitzMax SDK root, build for your board. For example:

   ```sh
   bin/bmk makeapp -r -board pico2_w /path/to/mqtt_client.bmx
   ```

   For ESP32, replace `pico2_w` with the board profile for your device. Follow
   the [Pico](../../../pico.mod/README.md) or
   [ESP32](../../../esp32.mod/README.md) target instructions to flash the
   resulting image and open its serial output.
3. Run the board. It should print `MQTT connected`, then
   `blitzmax/example: hello from BlitzMax`. The example subscribes to the
   topic before connecting and publishes to that same topic on connection.
4. Publish another message to `blitzmax/example` from any MQTT client to see
   it on the board. Restart the broker to see the client reconnect and restore
   the subscription.

The broker must be reachable from the board's network. Use the broker's LAN
address, not `localhost` (which would refer to the board). Keep Wi-Fi and
broker credentials out of version control.

## Examples

| Example | What it shows |
| --- | --- |
| [mqtt_client.bmx](../../examples/mqtt_client.bmx) | Smallest round trip: connect, subscribe, publish, print the received message |
| [mqtt_heartbeat.bmx](../../examples/mqtt_heartbeat.bmx) | Publish a periodic uptime message only while connected |
| [mqtt_commands.bmx](../../examples/mqtt_commands.bmx) | Subscribe to a command topic and handle incoming text |

Each example is a complete program. Copy one outside the repository, edit its
three connection constants, build it for your board, and flash it. All three
use Wi-Fi; on ESP32 you can also bring up a supported Ethernet interface
before calling `Connect()`.

## Minimal program

```blitzmax
SuperStrict
Framework BRL.StandardIO
Import BRL.EventQueue
Import Embedded.Network.WiFi
Import Embedded.Network.MQTT

Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"
Const BrokerHost:String = "<broker-lan-ip>"

Global mqtt:TMQTTClient

Function OnMQTT:Object(hookId:Int, data:Object, context:Object)
    Local event:TEvent = TEvent(data)
    If Not event Or event.source <> mqtt Then Return data
    Select event.id
        Case EVENT_MQTTCONNECTED
            Print "MQTT connected"
            mqtt.PublishText("blitzmax/example", "hello from BlitzMax", 1)
        Case EVENT_MQTTMESSAGE
            Local message:TMQTTMessage = TMQTTMessage(event.extra)
            Print message.topic + ": " + message.Text()
        Case EVENT_MQTTDISCONNECTED, EVENT_MQTTERROR
            Print "MQTT status code: " + event.data
    End Select
    Return data
End Function

If WiFiInitialize() <> 0 Then RuntimeError "Wi-Fi initialization failed"
If WiFiConnectWait(NetworkName, NetworkPassword) <> 0 Then RuntimeError "Wi-Fi connection failed"

mqtt = New TMQTTClient
mqtt.host = BrokerHost
mqtt.clientId = "unique-board-name"  ' Use a different ID on every board.
mqtt.Subscribe("blitzmax/example", 1)
AddHook EmitEventHook, OnMQTT
If mqtt.Connect() <> 0 Then Print "Initial MQTT attempt failed; reconnect is scheduled"

While True
    PollSystem()
    Delay 10
Wend
```

Replace the three placeholders, then build and flash as above. Publish in
`EVENT_MQTTCONNECTED`: `Connect()` only starts an attempt. Keep calling
`PollSystem()` or `PollEvent()` to deliver events and drive reconnect attempts.

## API at a glance

| Task | API | Notes |
| --- | --- | --- |
| Configure | `mqtt.host`, `port`, `clientId` | `port` defaults to 1883. Set a unique client ID per device. |
| Broker login | `mqtt.username`, `password` | Optional broker credentials; separate from Wi-Fi credentials. |
| Connect | `mqtt.Connect()` | `0` means the local adapter accepted the attempt. Wait for `EVENT_MQTTCONNECTED` before publishing. |
| Subscribe | `mqtt.Subscribe(topic, qos)` | Call before or after connecting. Up to 16 topics are remembered and restored after reconnect. |
| Send text | `mqtt.PublishText(topic, text, qos, retained)` | Call while connected. `qos` and `retained` are optional. |
| Send bytes | `mqtt.Publish(topic, byteArray, qos, retained)` | Use for binary payloads. |
| Send a buffer | `mqtt.Publish(topic, data:Byte Ptr, length, qos, retained)` | Pass an existing buffer without first making a `Byte[]`. Keep it valid until the call returns. |
| Receive | `EVENT_MQTTMESSAGE` | `TMQTTMessage(event.extra)` contains `topic`, `payload`, and `Text()`. |
| Check status | `mqtt.state`, `mqtt.lastError` | States: `MQTTDisconnected`, `MQTTConnecting`, `MQTTConnected`. |
| Stop | `mqtt.Disconnect()` | Stops this client and disables automatic reconnect. |

`EVENT_MQTTDISCONNECTED` and `EVENT_MQTTERROR` put the native code in
`event.data`. `Publish` and `PublishText` returning zero means the local MQTT
adapter accepted the request; it does not confirm delivery to the broker.
QoS 0, 1, and 2 can be requested.

For a buffer you already own, pass its address and byte count:

```blitzmax
Local payload:Byte[] = New Byte[3]
payload[0] = 1
payload[1] = 2
payload[2] = 3
Local result:Int = mqtt.Publish("devices/board/data", Varptr payload[0], payload.length, 1)
```

The pointer overload also accepts `Null` with length `0` for an empty
message. It rejects a negative length or a Null pointer with a positive
length. The caller owns the buffer.

MQTT carries individual messages rather than an open byte stream. To send
data from a `TStream`, read a bounded payload into a buffer and publish that
as one message. There is no `TStream` overload: it would need to choose
whether to buffer the entire stream or split it into multiple messages, and
splitting requires application-level chunk IDs and reassembly. Pico's lwIP
MQTT output queue is small, so test the payload size your application needs.

Automatic reconnect is on by default, with a five-second retry delay. The
client restores remembered subscriptions after a new connection. Your app is
responsible for restoring Wi-Fi if the radio connection is lost. If you call
`Disconnect()`, set `mqtt.autoReconnect = True` before connecting again when
you want automatic retries.

## Limits

- One MQTT client per application. Up to 16 remembered subscriptions.
- Incoming topics are limited to 127 UTF-8 bytes and payloads to 1024 bytes.
  Oversized messages are discarded and reported through `EVENT_MQTTERROR`.
- Eight native events are queued. `mqtt.DroppedEvents()` reports how many were
  displaced when the queue filled. Poll frequently while messages arrive.
- Incoming `qos` and `retained` fields are zero on Pico because its lwIP
  callback does not provide them.
- Plain `mqtt://` only. TLS, MQTT 5, will messages, and unsubscribe are not
  implemented.
