SuperStrict

Framework BRL.StandardIO
Import BRL.SystemDefault
Import Embedded.Network.WiFi
Import Embedded.Network.Time

' Copy this example before entering local credentials; do not commit them.
Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"

If NetworkName = "<ssid>" Then RuntimeError "Set the Wi-Fi credentials in a local copy"
If WiFiInitialize() <> 0 Then RuntimeError "Wi-Fi initialization failed"
If WiFiConnectWait(NetworkName, NetworkPassword) <> 0 Then RuntimeError "Wi-Fi connection failed"

If Not SynchronizeNetworkTime("pool.ntp.org", 10000) Then
	RuntimeError "NTP synchronization failed"
End If

Local now:SDateTime
If Not CalendarGet(now) Then RuntimeError "Calendar read failed"
Print "UTC date: " + now.year + "-" + now.month + "-" + now.day
Print "UTC time: " + now.hour + ":" + now.minute + ":" + now.second

If WiFiDisconnect() <> 0 Then RuntimeError "Wi-Fi disconnect failed"
If WiFiDeinitialize() <> 0 Then RuntimeError "Wi-Fi deinitialization failed"
