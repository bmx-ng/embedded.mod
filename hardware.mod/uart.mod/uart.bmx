' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable low-level UART controllers for embedded targets.
about: Controllers and pins are target resources. Query UARTControllerCount,
then configure a valid TX/RX pair for the selected target before initialization.
DefaultController returns UARTUnavailableController when the board's console
does not consume a hardware UART.
End Rem
Module Embedded.Hardware.UART
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Const UARTController0:Int = 0
Const UARTController1:Int = 1
Const UARTUnavailableController:Int = -1

Const UARTParityNone:UInt = 0
Const UARTParityEven:UInt = 1
Const UARTParityOdd:UInt = 2

Const UARTErrorFraming:UInt = $1
Const UARTErrorParity:UInt = $2
Const UARTErrorBreak:UInt = $4
Const UARTErrorOverrun:UInt = $8
Const UARTErrorInvalidArgument:Int = -5

Extern "C"
	Function UARTControllerCount:Int() = "bmx_embedded_uart_controller_count"
	Function UARTDefaultController:Int() = "bmx_embedded_uart_default_controller"
	Function UARTDefaultBaudrate:UInt() = "bmx_embedded_uart_default_baudrate"
	Function UARTConfigurePins:Int(controller:Int, txPin:UInt, rxPin:UInt) = "bmx_embedded_uart_configure_pins"
	Function UARTConfigureFlowControlPins:Int(controller:Int, ctsPin:UInt, rtsPin:UInt) = "bmx_embedded_uart_configure_flow_pins"
	Function UARTInit:UInt(controller:Int, baudrate:UInt) = "bmx_embedded_uart_init"
	Function UARTDeinit:Int(controller:Int) = "bmx_embedded_uart_deinit"
	Function UARTSetBaudrate:UInt(controller:Int, baudrate:UInt) = "bmx_embedded_uart_set_baudrate"
	Function UARTSetFormat:Int(controller:Int, dataBits:UInt, stopBits:UInt, parity:UInt) = "bmx_embedded_uart_set_format"
	Function UARTSetFlowControl:Int(controller:Int, ctsEnabled:Int, rtsEnabled:Int) = "bmx_embedded_uart_set_flow_control"
	Function UARTIsEnabled:Int(controller:Int) = "bmx_embedded_uart_is_enabled"
	Function UARTIsWritable:Int(controller:Int) = "bmx_embedded_uart_is_writable"
	Function UARTIsReadable:Int(controller:Int) = "bmx_embedded_uart_is_readable"
	Function UARTIsReadableWithin:Int(controller:Int, timeoutMicroseconds:UInt) = "bmx_embedded_uart_is_readable_within_us"
	Function UARTWriteBlocking:Int(controller:Int, source:Byte Ptr, length:Int) = "bmx_embedded_uart_write_blocking"
	Function UARTReadBlocking:Int(controller:Int, destination:Byte Ptr, length:Int) = "bmx_embedded_uart_read_blocking"
	Function UARTReadTimeout:Int(controller:Int, destination:Byte Ptr, length:Int, timeoutMicroseconds:UInt) = "bmx_embedded_uart_read_timeout_us"
	Function UARTReadAvailable:Int(controller:Int, destination:Byte Ptr, capacity:Int) = "bmx_embedded_uart_read_available"
	Function UARTPutByte:Int(controller:Int, value:UInt) = "bmx_embedded_uart_put_byte"
	Function UARTTXWaitBlocking:Int(controller:Int) = "bmx_embedded_uart_tx_wait_blocking"
	Function UARTSetBreak:Int(controller:Int, enabled:Int) = "bmx_embedded_uart_set_break"
	Function UARTSetTranslateCRLF:Int(controller:Int, enabled:Int) = "bmx_embedded_uart_set_translate_crlf"
	Function UARTGetErrors:UInt(controller:Int) = "bmx_embedded_uart_get_errors"
	Function UARTClearErrors:Int(controller:Int) = "bmx_embedded_uart_clear_errors"
End Extern
?
