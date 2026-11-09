# Network time

`Embedded.Network.Time` synchronizes `Embedded.System.Calendar` from an NTP
server over UDP. The same API works on Pico W, network-capable ESP32 boards,
and ESP8266 boards.

The smallest one-shot use is:

```blitzmax
SuperStrict

Framework BRL.StandardIO
Import BRL.SystemDefault
Import Embedded.Network.WiFi
Import Embedded.Network.Time

' Initialize and connect Wi-Fi first.
If Not SynchronizeNetworkTime("pool.ntp.org", 10000) Then
	RuntimeError "Unable to synchronize time"
End If

Local now:SDateTime
If CalendarGet(now) Then
	Print now.year + "-" + now.month + "-" + now.day + " " + ..
		now.hour + ":" + now.minute + ":" + now.second + " UTC"
End If
```

For an application which remains online, create a `TNetworkTimeClient`, call
`Start()`, and call `Service()` regularly. By default it synchronizes hourly
and retries a failed attempt after 30 seconds. `Service()` never waits for a
network response; DNS resolution during the start of an attempt may still use
the platform resolver and can therefore block according to that target's DNS
configuration.

The client validates the NTP mode, version, leap state, stratum, originate
timestamp, and transmit timestamp before changing the clock. It uses a single
48-byte request and one UDP socket, which is closed between updates. Call
`Stop()` before tearing down the network interface.

The synchronized value is UTC. `TNetworkTimeClient.lastTime` records the last
accepted value, `lastRoundTripMs` records request latency, and
`synchronizationCount` counts successful updates. A success or failure also
emits `EVENT_NETWORKTIMESYNCHRONIZED` or `EVENT_NETWORKTIMEERROR` respectively.

ESP8266's SDK calendar uses a signed 32-bit `time_t`, so that target accepts
dates from 1970 through January 2038. Pico and ESP32 do not have that specific
limit.
