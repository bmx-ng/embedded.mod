' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable single-reading analogue-to-digital conversion for embedded targets.
about: Raw values are target-quantized. Target modules expose attenuation,
calibration, FIFO, DMA, and other converter-specific facilities.
End Rem
Module Embedded.Hardware.ADC
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Extern "C"
	Function ADCIsValidPin:Int(pin:UInt) = "bmx_embedded_adc_is_valid_pin"
	Function ADCInitPin:Int(pin:UInt) = "bmx_embedded_adc_init_pin"
	Function ADCDeinitPin:Int(pin:UInt) = "bmx_embedded_adc_deinit_pin"

	Rem
	bbdoc: Reads one raw conversion into value and returns True on success.
	End Rem
	Function ADCReadRaw:Int(pin:UInt, value:UInt Var) = "bmx_embedded_adc_read_raw"

	Function ADCResolutionBitsForPin:UInt(pin:UInt) = "bmx_embedded_adc_resolution_bits"
	Function ADCMaximumValueForPin:UInt(pin:UInt) = "bmx_embedded_adc_maximum_value"
End Extern
?
