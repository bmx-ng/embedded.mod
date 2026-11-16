' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable Celsius temperature readings from identified sensor sources.
about: Device temperature is measured inside a chip and should not be treated
as an accurate ambient reading without calibration. Sensor indices are local
to the selected board and discovered at runtime.
End Rem
Module Embedded.Sensors.Temperature
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Const TemperatureKindUnknown:Int = 0
Const TemperatureKindDevice:Int = 1
Const TemperatureKindAmbient:Int = 2

?nrf52
Extern "C"
	Function TemperatureSensorCount:Int() = "bmx_embedded_temperature_sensor_count"
	Function TemperatureSensorKind:Int(sensor:Int) = "bmx_embedded_temperature_sensor_kind"
	Function TemperatureReadCelsius:Int(sensor:Int, celsius:Float Var) = "bmx_embedded_temperature_read_celsius"
End Extern
?Not nrf52
Function TemperatureSensorCount:Int()
	Return 0
End Function

Function TemperatureSensorKind:Int(sensor:Int)
	Return TemperatureKindUnknown
End Function

Function TemperatureReadCelsius:Int(sensor:Int, celsius:Float Var)
	Return False
End Function
?
?
