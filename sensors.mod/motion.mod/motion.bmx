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
Extern "C"
	Function MotionSensorCount:Int() = "bmx_embedded_motion_sensor_count"
	Function MotionRead:Int(sensor:Int, accelX:Float Var, accelY:Float Var, accelZ:Float Var, gyroX:Float Var, gyroY:Float Var, gyroZ:Float Var, timestampMicroseconds:Long Var) = "bmx_embedded_motion_read"
End Extern
?embedded And Not nrf52
Function MotionSensorCount:Int()
	Return 0
End Function

Function MotionRead:Int(sensor:Int, accelX:Float Var, accelY:Float Var, accelZ:Float Var, gyroX:Float Var, gyroY:Float Var, gyroZ:Float Var, timestampMicroseconds:Long Var)
	Return False
End Function
?embedded
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
