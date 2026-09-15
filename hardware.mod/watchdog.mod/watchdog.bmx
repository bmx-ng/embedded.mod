' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable watchdog services for embedded targets.
about: The watchdog monitors the application execution context. Once enabled,
call WatchdogFeed before the configured timeout. Target modules expose details
such as debugger pausing and remaining hardware time where available.
End Rem
Module Embedded.Hardware.Watchdog
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Extern "C"
	Function WatchdogMaximumDelayMilliseconds:UInt() = "bmx_embedded_watchdog_maximum_delay_ms"
	Function WatchdogEnable:Int(delayMilliseconds:UInt) = "bmx_embedded_watchdog_enable"
	Function WatchdogDisable:Int() = "bmx_embedded_watchdog_disable"
	Function WatchdogFeed:Int() = "bmx_embedded_watchdog_feed"
	Function WatchdogIsEnabled:Int() = "bmx_embedded_watchdog_is_enabled"
	Function WatchdogCausedReboot:Int() = "bmx_embedded_watchdog_caused_reboot"
End Extern
?
