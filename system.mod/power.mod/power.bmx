' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable low-power sleep services for embedded targets.
about: Query PowerCapabilities before using an optional operation. Returning
sleep operations preserve the running application; target-specific sleep modes
which resume through a reboot are deliberately outside this portable contract.
End Rem
Module Embedded.System.Power
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Const PowerCapabilityIdle:UInt = $01
Const PowerCapabilitySleepInterrupt:UInt = $02
Const PowerCapabilitySleepTimer:UInt = $04
Const PowerCapabilityDormantGPIO:UInt = $08
Const PowerCapabilityDormantTimer:UInt = $10
Const PowerCapabilityLowLeakagePins:UInt = $20

Enum EPowerResult:Int
	Success = 0
	Error = -1
	Timeout = -2
	NotPermitted = -4
	InvalidArgument = -5
	InsufficientResources = -9
	InvalidState = -12
	PreconditionNotMet = -14
	InvalidData = -16
	Unavailable = -17
	ResourceInUse = -21
End Enum

Extern "C"
	Function PowerCapabilities:UInt() = "bmx_embedded_power_capabilities"
	Function PowerIdle() = "bmx_embedded_power_idle"
	Function LowPowerSleepUntilInterrupt:EPowerResult() = "bmx_embedded_power_sleep_until_interrupt"
	Function LowPowerSleep:EPowerResult(milliseconds:UInt, exclusive:Int = True) = "bmx_embedded_power_sleep_for_ms"
	Function DormantSleep:EPowerResult(milliseconds:UInt) = "bmx_embedded_power_dormant_for_ms"
	Function DormantSleepUntilGPIO:EPowerResult(pin:UInt, edge:Int, high:Int) = "bmx_embedded_power_dormant_until_gpio"
	Function SetUnusedPinsLowLeakage:EPowerResult(excludeMask:ULong = 0) = "bmx_embedded_power_set_unused_pins_low_leakage"
End Extern

Function PowerSupports:Int(capabilities:UInt)
	Return (PowerCapabilities() & capabilities) = capabilities
End Function
?
