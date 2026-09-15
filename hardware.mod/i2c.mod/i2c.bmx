' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable I2C master controllers for embedded targets.
about: The combined write/read operation performs an atomic repeated-Start
transaction and is the portable way to read a device register.
End Rem
Module Embedded.Hardware.I2C
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Const I2CController0:Int = 0
Const I2CController1:Int = 1
Const I2CUnavailableController:Int = -1
Const I2CUnavailablePin:UInt = $ffffffff

Const I2CSpeedStandard:UInt = 100000
Const I2CSpeedFast:UInt = 400000
Const I2CSpeedFastPlus:UInt = 1000000

Const I2CErrorGeneric:Int = -1
Const I2CErrorTimeout:Int = -2
Const I2CErrorInvalidArgument:Int = -5

Extern "C"
	Function I2CControllerCount:Int() = "bmx_embedded_i2c_controller_count"
	Function I2CDefaultController:Int() = "bmx_embedded_i2c_default_controller"
	Function I2CDefaultSDAPin:UInt() = "bmx_embedded_i2c_default_sda_pin"
	Function I2CDefaultSCLPin:UInt() = "bmx_embedded_i2c_default_scl_pin"
	Function I2CConfigurePins:Int(controller:Int, sdaPin:UInt, sclPin:UInt, pullUps:Int) = "bmx_embedded_i2c_configure_pins"
	Function I2CInit:UInt(controller:Int, baudrate:UInt) = "bmx_embedded_i2c_init"
	Function I2CDeinit:Int(controller:Int) = "bmx_embedded_i2c_deinit"
	Function I2CSetBaudrate:UInt(controller:Int, baudrate:UInt) = "bmx_embedded_i2c_set_baudrate"

	Function I2CWriteBlocking:Int(controller:Int, address:UInt, data:Byte Ptr, length:Int) = "bmx_embedded_i2c_write_blocking"
	Function I2CReadBlocking:Int(controller:Int, address:UInt, data:Byte Ptr, length:Int) = "bmx_embedded_i2c_read_blocking"
	Function I2CWriteTimeout:Int(controller:Int, address:UInt, data:Byte Ptr, length:Int, timeoutMicroseconds:UInt) = "bmx_embedded_i2c_write_timeout_us"
	Function I2CReadTimeout:Int(controller:Int, address:UInt, data:Byte Ptr, length:Int, timeoutMicroseconds:UInt) = "bmx_embedded_i2c_read_timeout_us"

	Rem
	bbdoc: Writes bytes, emits a repeated Start, then reads bytes from the same 7-bit address.
	about: On success, returns the number of bytes read.
	End Rem
	Function I2CWriteReadBlocking:Int(controller:Int, address:UInt, writeData:Byte Ptr, writeLength:Int, readData:Byte Ptr, readLength:Int) = "bmx_embedded_i2c_write_read_blocking"
	Function I2CWriteReadTimeout:Int(controller:Int, address:UInt, writeData:Byte Ptr, writeLength:Int, readData:Byte Ptr, readLength:Int, timeoutMicroseconds:UInt) = "bmx_embedded_i2c_write_read_timeout_us"
End Extern
?
