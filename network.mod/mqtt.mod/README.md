# Embedded.Network.MQTT

`Embedded.Network.MQTT` provides one MQTT 3.1.1 client for a Pico W, Pico 2 W,
or network-capable ESP32 board. Importing the module selects the target's MQTT
adapter. Pico uses the Pico SDK lwIP raw MQTT client; ESP32 uses ESP-MQTT. The
API is for unencrypted `mqtt://` connections. TLS, MQTT 5, will messages,
unsubscribe, and multiple concurrent clients are not implemented.

Set up an IP interface first. On Pico, import `Embedded.Network.WiFi`, call
`WiFiInitialize()`, and wait for `WiFiLinkUp` before `TMQTTClient.Connect()`.
ESP32 can use Wi-Fi or a supported Ethernet interface. Set `host`, `port`
(default 1883), `clientId`, optional `username` and `password`, and optional
`keepAliveSeconds` before connecting. The example at
`../../examples/mqtt_client.bmx` demonstrates Wi-Fi, subscribe, publish, and
event handling. Use a unique client ID per device.

`Connect()` starts an asynchronous attempt and returns zero when it was
accepted by the local adapter. `state` becomes `MQTTConnected` when the broker
accepts it. `Subscribe(topic, qos)` remembers up to 16 subscriptions and
replays them after every connection. `Publish(topic, bytes, qos, retained)`
and `PublishText(...)` return zero if the native client accepted the request;
this does not guarantee broker delivery. QoS 0, 1, and 2 requests are accepted.

Call `PollSystem()` or `PollEvent()` regularly. MQTT callbacks copy into an
eight-record native queue; managed events are created only on the application
context during polling. `EVENT_MQTTCONNECTED`, `EVENT_MQTTDISCONNECTED`, and
`EVENT_MQTTERROR` use the client as event source; disconnect and error codes
are in `event.data`. `EVENT_MQTTMESSAGE` carries a `TMQTTMessage` in
`event.extra`, including a binary `payload` and `Text()` helper. Pico's lwIP
incoming callback does not provide QoS or retained flags, so these fields are
zero on Pico. Messages with topics over 127 UTF-8 bytes or payloads over 1024
bytes are discarded and emit an error code of -4. A full event queue increments
`DroppedEvents()`; the oldest queued event is discarded so a later connection
state event can still reach the application.

`autoReconnect` defaults to true. After a disconnect or failed local start,
polling retries after `reconnectDelayMs` (default 5000). `Disconnect()` stops
the client and disables automatic reconnect. Set `autoReconnect = True` before
calling `Connect()` again if desired. Wi-Fi itself must be restored by the
application; the MQTT client does not reconnect the radio.

Build a compile probe from the BlitzMax SDK root with
`bin/bmk makeapp -r -board pico2_w mod/embedded.mod/tests/embedded_mqtt_compile_device.bmx`
or replace `pico2_w` with an ESP32 board profile. For a broker test, copy the
example, fill in private Wi-Fi and broker details, flash, observe the connected
event and echoed message, then restart the broker to check reconnect and
subscription replay. Keep credentials out of the repository.
