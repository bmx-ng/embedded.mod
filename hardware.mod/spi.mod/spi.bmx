' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable SPI controller operations for embedded targets.
about: Chip-select is deliberately controlled separately through
Embedded.Hardware.GPIO so applications can use more than one peripheral.
End Rem
Module Embedded.Hardware.SPI
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Const SPIController0:Int = 0
Const SPIController1:Int = 1
Const SPIUnavailableController:Int = -1
Const SPIUnavailablePin:UInt = $ffffffff

Const SPIClockPolarity0:UInt = 0
Const SPIClockPolarity1:UInt = 1
Const SPIClockPhase0:UInt = 0
Const SPIClockPhase1:UInt = 1
Const SPIBitOrderLSBFirst:UInt = 0
Const SPIBitOrderMSBFirst:UInt = 1
Const SPIErrorGeneric:Int = -1
Const SPIErrorInvalidArgument:Int = -5

Extern "C"
	Function SPIControllerCount:Int() = "bmx_embedded_spi_controller_count"
	Function SPIDefaultController:Int() = "bmx_embedded_spi_default_controller"
	Function SPIDefaultRXPin:UInt() = "bmx_embedded_spi_default_rx_pin"
	Function SPIDefaultTXPin:UInt() = "bmx_embedded_spi_default_tx_pin"
	Function SPIDefaultClockPin:UInt() = "bmx_embedded_spi_default_sck_pin"
	Function SPIDefaultChipSelectPin:UInt() = "bmx_embedded_spi_default_csn_pin"
	Function SPIConfigurePins:Int(controller:Int, rxPin:UInt, txPin:UInt, clockPin:UInt) = "bmx_embedded_spi_configure_pins"
	Function SPIInit:UInt(controller:Int, baudrate:UInt) = "bmx_embedded_spi_init"
	Function SPIDeinit:Int(controller:Int) = "bmx_embedded_spi_deinit"
	Function SPISetBaudrate:UInt(controller:Int, baudrate:UInt) = "bmx_embedded_spi_set_baudrate"
	Function SPIGetBaudrate:UInt(controller:Int) = "bmx_embedded_spi_get_baudrate"
	Function SPISetFormat:Int(controller:Int, dataBits:UInt, polarity:UInt, phase:UInt, bitOrder:UInt) = "bmx_embedded_spi_set_format"

	Function SPIWriteReadBlocking:Int(controller:Int, source:Byte Ptr, destination:Byte Ptr, length:Int) = "bmx_embedded_spi_write_read_blocking"
	Function SPIWriteBlocking:Int(controller:Int, source:Byte Ptr, length:Int) = "bmx_embedded_spi_write_blocking"
	Function SPIReadBlocking:Int(controller:Int, repeatedData:UInt, destination:Byte Ptr, length:Int) = "bmx_embedded_spi_read_blocking"
	Function SPIWrite16Read16Blocking:Int(controller:Int, source:Short Ptr, destination:Short Ptr, length:Int) = "bmx_embedded_spi_write16_read16_blocking"
	Function SPIWrite16Blocking:Int(controller:Int, source:Short Ptr, length:Int) = "bmx_embedded_spi_write16_blocking"
	Function SPIRead16Blocking:Int(controller:Int, repeatedData:UInt, destination:Short Ptr, length:Int) = "bmx_embedded_spi_read16_blocking"
End Extern
?
