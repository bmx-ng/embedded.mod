' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable general-purpose digital input and output for embedded targets.
about: Configuration getters describe changes made through this module. Mixing
target-specific GPIO calls with this portable API may make those getters stale.
End Rem
Module Embedded.Hardware.GPIO
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Const GPIOInput:Int = 0
Const GPIOOutput:Int = 1

Const GPIOIRQLevelLow:UInt = $1
Const GPIOIRQLevelHigh:UInt = $2
Const GPIOIRQEdgeFall:UInt = $4
Const GPIOIRQEdgeRise:UInt = $8

Rem
bbdoc: Target-neutral drive capability, ordered from weakest to strongest.
End Rem
Const GPIODriveStrengthLow:Int = 0
Const GPIODriveStrengthMedium:Int = 1
Const GPIODriveStrengthHigh:Int = 2
Const GPIODriveStrengthMaximum:Int = 3

Extern "C"
	Function GPIOIsValid:Int(pin:UInt) = "bmx_embedded_gpio_is_valid"
	Function GPIOIsOutputCapable:Int(pin:UInt) = "bmx_embedded_gpio_is_output_capable"
	Function GPIOIsPullCapable:Int(pin:UInt) = "bmx_embedded_gpio_is_pull_capable"
	Function GPIOInit:Int(pin:UInt) = "bmx_embedded_gpio_init"
	Function GPIOSetDirection:Int(pin:UInt, direction:Int) = "bmx_embedded_gpio_set_direction"
	Function GPIOGetDirection:Int(pin:UInt) = "bmx_embedded_gpio_get_direction"
	Function GPIOSetInput:Int(pin:UInt) = "bmx_embedded_gpio_set_input"
	Function GPIOSetOutput:Int(pin:UInt) = "bmx_embedded_gpio_set_output"
	Function GPIOGet:Int(pin:UInt) = "bmx_embedded_gpio_get"
	Function GPIOPut:Int(pin:UInt, value:Int) = "bmx_embedded_gpio_put"
	Function GPIOGetOutput:Int(pin:UInt) = "bmx_embedded_gpio_get_output"
	Function GPIOSetPulls:Int(pin:UInt, pullUp:Int, pullDown:Int) = "bmx_embedded_gpio_set_pulls"
	Function GPIOPullUp:Int(pin:UInt) = "bmx_embedded_gpio_pull_up"
	Function GPIOPullDown:Int(pin:UInt) = "bmx_embedded_gpio_pull_down"
	Function GPIODisablePulls:Int(pin:UInt) = "bmx_embedded_gpio_disable_pulls"
	Function GPIOIsPulledUp:Int(pin:UInt) = "bmx_embedded_gpio_is_pulled_up"
	Function GPIOIsPulledDown:Int(pin:UInt) = "bmx_embedded_gpio_is_pulled_down"
	Function GPIOSetDriveStrength:Int(pin:UInt, driveStrength:Int) = "bmx_embedded_gpio_set_drive_strength"
	Function GPIOGetDriveStrength:Int(pin:UInt) = "bmx_embedded_gpio_get_drive_strength"
	Function GPIOSetIRQEnabled:Int(pin:UInt, eventMask:UInt, enabled:Int) = "bmx_embedded_gpio_set_irq_enabled"
	Function _GPIOSetEventToken:Int(pin:UInt, token:UInt) = "bmx_embedded_gpio_set_event_token"
	Function GPIOPendingIRQEvents:UInt(pin:UInt) = "bmx_embedded_gpio_pending_irq_events"
	Function GPIOTakeIRQEvents:UInt(pin:UInt) = "bmx_embedded_gpio_take_irq_events"
End Extern
?
