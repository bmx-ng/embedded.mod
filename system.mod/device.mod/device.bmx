' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable device identity and reset services for embedded targets.
about: Identifier byte lengths and sources are target-specific. Reset reasons
are normalized into the constants in this module; unsupported distinctions are
reported as DeviceResetReasonUnknown.
End Rem
Module Embedded.System.Device
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Const DeviceResetReasonUnknown:Int = 0
Const DeviceResetReasonPowerOn:Int = 1
Const DeviceResetReasonExternal:Int = 2
Const DeviceResetReasonSoftware:Int = 3
Const DeviceResetReasonWatchdog:Int = 4
Const DeviceResetReasonPanic:Int = 5
Const DeviceResetReasonDeepSleep:Int = 6
Const DeviceResetReasonBrownout:Int = 7
Const DeviceResetReasonPowerGlitch:Int = 8
Const DeviceResetReasonCPULockup:Int = 9

Extern "C"
	Function UniqueDeviceID:String() = "bmx_embedded_unique_device_id"
	Function UniqueDeviceIDBytes:Byte[]() = "bmx_embedded_unique_device_id_bytes"
	Function DeviceResetReason:Int() = "bmx_embedded_device_reset_reason"

	Rem
	bbdoc: Requests a reboot after delayMilliseconds and returns True if accepted.
	about: A successful zero-delay request does not return. Delayed reboot limits
	are target-specific.
	End Rem
	Function Reboot:Int(delayMilliseconds:UInt = 0) = "bmx_embedded_device_reboot"
End Extern

Function DeviceResetReasonName:String(reason:Int)
	Select reason
		Case DeviceResetReasonPowerOn Return "Power on"
		Case DeviceResetReasonExternal Return "External"
		Case DeviceResetReasonSoftware Return "Software"
		Case DeviceResetReasonWatchdog Return "Watchdog"
		Case DeviceResetReasonPanic Return "Panic"
		Case DeviceResetReasonDeepSleep Return "Deep sleep"
		Case DeviceResetReasonBrownout Return "Brownout"
		Case DeviceResetReasonPowerGlitch Return "Power glitch"
		Case DeviceResetReasonCPULockup Return "CPU lockup"
	End Select
	Return "Unknown"
End Function
?
