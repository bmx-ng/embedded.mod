' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable UTC calendar clock and absolute alarm services.
about: Calendar time is not retained across complete power loss. Networked
applications can initialize it from Embedded.Network.Time. Alarm callbacks
perform native bookkeeping only; managed code consumes their event count.
End Rem
Module Embedded.System.Calendar
?embedded and (pico or esp32 or esp8266)

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Pub.Time

Extern "C"
?pico
	Function CalendarStart:Int(dateTime:SDateTime Var) = "bmx_pico_calendar_start"
	Function CalendarStop() = "bmx_pico_calendar_stop"
	Function CalendarSet:Int(dateTime:SDateTime Var) = "bmx_pico_calendar_set"
	Function CalendarGet:Int(dateTime:SDateTime Var) = "bmx_pico_calendar_get"
	Function CalendarIsRunning:Int() = "bmx_pico_calendar_is_running"
	Function CalendarResolutionNanoseconds:ULong() = "bmx_pico_calendar_resolution_nanoseconds"
	Function CalendarSetAlarm:Int(dateTime:SDateTime Var, wakeFromLowPower:Int = False) = "bmx_pico_calendar_set_alarm"
	Function CalendarDisableAlarm() = "bmx_pico_calendar_disable_alarm"
	Function PendingCalendarAlarmEvents:UInt() = "bmx_pico_calendar_pending_alarm_events"
	Function TakeCalendarAlarmEvents:UInt() = "bmx_pico_calendar_take_alarm_events"
?esp32
	Function CalendarStart:Int(dateTime:SDateTime Var) = "bmx_esp32_calendar_start"
	Function CalendarStop() = "bmx_esp32_calendar_stop"
	Function CalendarSet:Int(dateTime:SDateTime Var) = "bmx_esp32_calendar_set"
	Function CalendarGet:Int(dateTime:SDateTime Var) = "bmx_esp32_calendar_get"
	Function CalendarIsRunning:Int() = "bmx_esp32_calendar_is_running"
	Function CalendarResolutionNanoseconds:ULong() = "bmx_esp32_calendar_resolution_nanoseconds"
	Function CalendarSetAlarm:Int(dateTime:SDateTime Var, wakeFromLowPower:Int = False) = "bmx_esp32_calendar_set_alarm"
	Function CalendarDisableAlarm() = "bmx_esp32_calendar_disable_alarm"
	Function PendingCalendarAlarmEvents:UInt() = "bmx_esp32_calendar_pending_alarm_events"
	Function TakeCalendarAlarmEvents:UInt() = "bmx_esp32_calendar_take_alarm_events"
?esp8266
	Function CalendarStart:Int(dateTime:SDateTime Var) = "bmx_esp8266_calendar_start"
	Function CalendarStop() = "bmx_esp8266_calendar_stop"
	Function CalendarSet:Int(dateTime:SDateTime Var) = "bmx_esp8266_calendar_set"
	Function CalendarGet:Int(dateTime:SDateTime Var) = "bmx_esp8266_calendar_get"
	Function CalendarIsRunning:Int() = "bmx_esp8266_calendar_is_running"
	Function CalendarResolutionNanoseconds:ULong() = "bmx_esp8266_calendar_resolution_nanoseconds"
	Function CalendarSetAlarm:Int(dateTime:SDateTime Var, wakeFromLowPower:Int = False) = "bmx_esp8266_calendar_set_alarm"
	Function CalendarDisableAlarm() = "bmx_esp8266_calendar_disable_alarm"
	Function PendingCalendarAlarmEvents:UInt() = "bmx_esp8266_calendar_pending_alarm_events"
	Function TakeCalendarAlarmEvents:UInt() = "bmx_esp8266_calendar_take_alarm_events"
?
End Extern
?
