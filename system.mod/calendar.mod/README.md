# Embedded calendar

`Embedded.System.Calendar` supplies the same UTC calendar-clock and one-shot
absolute-alarm API on Pico, ESP32, and ESP8266. The clock starts from an
application-provided `SDateTime`, or can be synchronized from an NTP server by
`Embedded.Network.Time`.

```blitzmax
SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Calendar

Local initial:SDateTime = New SDateTime(2026, 11, 9, 12, 0, 0, 0, True)
If Not CalendarStart(initial) Then RuntimeError "Calendar start failed"

Local now:SDateTime
If CalendarGet(now) Then Print now.year + "-" + now.month + "-" + now.day
```

Calendar time does not survive a restart or complete loss of power. Pico and
ESP32 can optionally use an absolute alarm as a low-power wake source. ESP8266
supports the same ordinary one-shot alarm, but rejects
`wakeFromLowPower = True` because that target requires its separate sleep-wake
mechanisms.
