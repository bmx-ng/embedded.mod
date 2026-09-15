' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable pin-oriented pulse-width modulation for embedded targets.
about: Duty uses a target-neutral 0 through PWMDutyMaximum scale. Frequency and
duty are quantized to the target hardware. Initialization or retuning may fail
when the target cannot allocate an independent timing resource without changing
another configured pin.
End Rem
Module Embedded.Hardware.PWM
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Const PWMDutyMaximum:UInt = 65535

Extern "C"
	Function PWMIsValidPin:Int(pin:UInt) = "bmx_embedded_pwm_is_valid_pin"

	Rem
	bbdoc: Configures and enables PWM on a pin, returning the achieved frequency.
	End Rem
	Function PWMInitPin:UInt(pin:UInt, frequency:UInt, duty:UInt = 0, inverted:Int = False) = "bmx_embedded_pwm_init_pin"

	Function PWMDeinitPin:Int(pin:UInt) = "bmx_embedded_pwm_deinit_pin"
	Function PWMSetPinFrequency:UInt(pin:UInt, frequency:UInt) = "bmx_embedded_pwm_set_pin_frequency"
	Function PWMGetPinFrequency:UInt(pin:UInt) = "bmx_embedded_pwm_get_pin_frequency"
	Function PWMSetPinDuty:Int(pin:UInt, duty:UInt) = "bmx_embedded_pwm_set_pin_duty"
	Function PWMGetPinDuty:UInt(pin:UInt) = "bmx_embedded_pwm_get_pin_duty"
	Function PWMSetPinPolarity:Int(pin:UInt, inverted:Int) = "bmx_embedded_pwm_set_pin_polarity"
	Function PWMGetPinPolarity:Int(pin:UInt) = "bmx_embedded_pwm_get_pin_polarity"
	Function PWMSetPinEnabled:Int(pin:UInt, enabled:Int) = "bmx_embedded_pwm_set_pin_enabled"
	Function PWMGetPinEnabled:Int(pin:UInt) = "bmx_embedded_pwm_get_pin_enabled"
End Extern
?
