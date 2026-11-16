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

?embedded And nrf52
Private
Extern "C"
	Function _NativeTemperatureSensorCount:Int() = "bmx_embedded_temperature_sensor_count"
	Function _NativeTemperatureSensorKind:Int(sensor:Int) = "bmx_embedded_temperature_sensor_kind"
	Function _NativeTemperatureReadCelsius:Int(sensor:Int, celsius:Float Var) = "bmx_embedded_temperature_read_celsius"
End Extern
?embedded And Not nrf52
Private
Function _NativeTemperatureSensorCount:Int()
	Return 0
End Function

Function _NativeTemperatureSensorKind:Int(sensor:Int)
	Return TemperatureKindUnknown
End Function

Function _NativeTemperatureReadCelsius:Int(sensor:Int, celsius:Float Var)
	Return False
End Function
?embedded
Public
Rem
bbdoc: A temperature source, regardless of its board, bus, or chip.
about: Drivers for external devices extend this type. Each object represents
one physical temperature source. Kind describes what the reading measures,
while the application assigns a location or purpose to the object.
End Rem
Type TTemperatureSensor Abstract
	Method Kind:Int() Abstract
	Method ReadCelsius:Int(celsius:Float Var) Abstract
End Type

Private
Type TBoardTemperatureSensor Extends TTemperatureSensor
	Field index:Int

	Method Kind:Int()
		Return _NativeTemperatureSensorKind(index)
	End Method

	Method ReadCelsius:Int(celsius:Float Var)
		Return _NativeTemperatureReadCelsius(index, celsius)
	End Method
End Type

Public

Rem
bbdoc: Returns the number of temperature sources configured on the board.
about: External sensors opened by an application are separate objects and do
not need to be registered here.
End Rem
Function TemperatureSensorCount:Int()
	Return _NativeTemperatureSensorCount()
End Function

Rem
bbdoc: Returns a board temperature sensor, or Null for an invalid index.
End Rem
Function TemperatureSensorAt:TTemperatureSensor(index:Int)
	If index < 0 Or index >= TemperatureSensorCount() Then Return Null
	Local sensor:TBoardTemperatureSensor = New TBoardTemperatureSensor
	sensor.index = index
	Return sensor
End Function
?
