' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import Embedded.System.Power
Import BRL.StandardIO

Local capabilities:UInt = PowerCapabilities()
If Not PowerSupports(PowerCapabilityIdle) Then RuntimeError "embedded idle power capability missing"
If PowerSupports(PowerCapabilitySleepTimer) Then
	If LowPowerSleep(0) <> EPowerResult.InvalidArgument Then RuntimeError "zero-duration sleep was not rejected"
End If
If Not PowerSupports(PowerCapabilityDormantTimer) Then
	If DormantSleep(1) <> EPowerResult.Unavailable Then RuntimeError "unsupported dormant timer did not report unavailable"
End If
If Not PowerSupports(PowerCapabilityDormantGPIO) Then
	If DormantSleepUntilGPIO(0, True, True) <> EPowerResult.Unavailable Then RuntimeError "unsupported dormant GPIO did not report unavailable"
End If
If Not PowerSupports(PowerCapabilityLowLeakagePins) Then
	If SetUnusedPinsLowLeakage() <> EPowerResult.Unavailable Then RuntimeError "unsupported low-leakage pin operation did not report unavailable"
End If

Print "Embedded power conformance passed; capabilities=" + capabilities
