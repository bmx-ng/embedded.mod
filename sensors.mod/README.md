# Sensors

`Embedded.Sensors.Temperature` and `Embedded.Sensors.Motion` expose sensor
objects. A board-provided sensor and an external sensor use the same reading
methods. The application may keep several objects and give each a name or
purpose of its own.

To obtain a board sensor, check the count and request an object:

```blitzmax
Import Embedded.Sensors.Temperature

Local deviceTemp:TTemperatureSensor = TemperatureSensorAt(0)
If deviceTemp Then
    Local celsius:Float
    If deviceTemp.ReadCelsius(celsius) Then Print celsius
End If
```

`TemperatureSensorAt` and `MotionSensorAt` return `Null` if the index is not
configured. `TemperatureSensorCount` and `MotionSensorCount` count only the
sensors configured on the board. External sensors are opened by their chip
drivers and return the same `TTemperatureSensor` or `TMotionSensor` types; they
do not need to be added to a global registry. This keeps separate sensors and
locations explicit in the application.

`TTemperatureSensor.Kind()` distinguishes a device's internal temperature
from an ambient temperature measurement. It does not identify the chip model
or the sensor's location. External drivers should expose their bus and address
when they create the object. One physical device that measures both motion and
temperature may expose both capabilities while sharing its underlying device
state.

The current built-in implementation covers the XIAO nRF52840 Sense and Sense
Plus IMU. Portable external chip drivers are still to be added.
