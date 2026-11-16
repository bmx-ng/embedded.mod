' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable three-axis acceleration and angular-velocity readings.
about: Acceleration uses metres per second squared; angular velocity uses
radians per second. Axes follow the sensor's physical orientation. A device
can expose zero or more motion sensors; discover them at runtime.
End Rem
Module Embedded.Sensors.Motion
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

?embedded And nrf52
Private
Extern "C"
	Function _NativeMotionSensorCount:Int() = "bmx_embedded_motion_sensor_count"
	Function _NativeMotionRead:Int(sensor:Int, accelX:Float Var, accelY:Float Var, accelZ:Float Var, gyroX:Float Var, gyroY:Float Var, gyroZ:Float Var, timestampMicroseconds:Long Var) = "bmx_embedded_motion_read"
End Extern
?embedded And Not nrf52
Private
Function _NativeMotionSensorCount:Int()
	Return 0
End Function

Function _NativeMotionRead:Int(sensor:Int, accelX:Float Var, accelY:Float Var, accelZ:Float Var, gyroX:Float Var, gyroY:Float Var, gyroZ:Float Var, timestampMicroseconds:Long Var)
	Return False
End Function
?embedded
Public
Rem
bbdoc: A source of acceleration and angular velocity on any supported target.
about: External device drivers extend this type. One object represents one
physical motion source, whether built into a board or connected externally.
End Rem
Type TMotionSensor Abstract
	Method Read:Int(accelX:Float Var, accelY:Float Var, accelZ:Float Var, gyroX:Float Var, gyroY:Float Var, gyroZ:Float Var, timestampMicroseconds:Long Var) Abstract
End Type

Private
Type TBoardMotionSensor Extends TMotionSensor
	Field index:Int

	Method Read:Int(accelX:Float Var, accelY:Float Var, accelZ:Float Var, gyroX:Float Var, gyroY:Float Var, gyroZ:Float Var, timestampMicroseconds:Long Var)
		Return _NativeMotionRead(index, accelX, accelY, accelZ, gyroX, gyroY, gyroZ, timestampMicroseconds)
	End Method
End Type

Public
Rem
bbdoc: Returns the number of motion sensors configured on the board.
End Rem
Function MotionSensorCount:Int()
	Return _NativeMotionSensorCount()
End Function

Rem
bbdoc: Returns a board motion sensor, or Null for an invalid index.
End Rem
Function MotionSensorAt:TMotionSensor(index:Int)
	If index < 0 Or index >= MotionSensorCount() Then Return Null
	Local sensor:TBoardMotionSensor = New TBoardMotionSensor
	sensor.index = index
	Return sensor
End Function

Rem
bbdoc: Reports inversion relative to an acceleration vector recorded while upright.
about: Both vectors use the same sensor axes. A reading near zero magnitude is
rejected, since free fall cannot establish orientation. Motion and vibration
can make a single reading unreliable; average readings for a stable decision.
End Rem
Function MotionIsUpsideDown:Int(accelX:Float, accelY:Float, accelZ:Float, uprightX:Float, uprightY:Float, uprightZ:Float, minimumCosine:Float = 0.7)
	Local measured:Float = accelX * accelX + accelY * accelY + accelZ * accelZ
	Local reference:Float = uprightX * uprightX + uprightY * uprightY + uprightZ * uprightZ
	If measured < 1.0 Or reference < 1.0 Then Return False
	If minimumCosine < 0.0 Or minimumCosine > 1.0 Then Return False
	Local dot:Float = accelX * uprightX + accelY * uprightY + accelZ * uprightZ
	Return dot < 0.0 And dot * dot > minimumCosine * minimumCosine * measured * reference
End Function
?
