' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: ILI9341-compatible 240x320 colour TFT displays over portable SPI.
about: The application configures and initializes the SPI controller before
calling Initialize. Chip-select, data/command, and reset are ordinary GPIOs
owned by this display instance. RGB565 display buffers are converted from the
shared little-endian representation to the controller's wire byte order while
being transferred; no frame-sized staging buffer is allocated.
End Rem
Module Embedded.Drivers.Displays.ILI9341
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Drivers.Display
Import Embedded.Hardware.GPIO
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const ILI9341CommandSoftwareReset:Byte = $01
Const ILI9341CommandSleepIn:Byte = $10
Const ILI9341CommandSleepOut:Byte = $11
Const ILI9341CommandDisplayInversionOff:Byte = $20
Const ILI9341CommandDisplayInversionOn:Byte = $21
Const ILI9341CommandDisplayOff:Byte = $28
Const ILI9341CommandDisplayOn:Byte = $29
Const ILI9341CommandColumnAddress:Byte = $2a
Const ILI9341CommandRowAddress:Byte = $2b
Const ILI9341CommandMemoryWrite:Byte = $2c
Const ILI9341CommandMemoryAccess:Byte = $36
Const ILI9341CommandPixelFormat:Byte = $3a

Const ILI9341MemoryAccessRowAddressOrder:Byte = $80
Const ILI9341MemoryAccessColumnAddressOrder:Byte = $40
Const ILI9341MemoryAccessRowColumnExchange:Byte = $20
Const ILI9341MemoryAccessVerticalRefreshOrder:Byte = $10
Const ILI9341MemoryAccessBGR:Byte = $08

Rem
bbdoc: An SPI ILI9341-compatible 240x320 colour display.
End Rem
Type TILI9341Display Extends TDisplay
	Private
	Field controller:Int
	Field chipSelectPin:UInt
	Field dataCommandPin:UInt
	Field resetPin:UInt
	Field bgrOrder:Int
	Field inverted:Int
	Field initialized:Int
	Field commandBuffer:Byte[]
	Field transferBuffer:Byte[]

	Public
	Rem
	bbdoc: Creates a 240x320 ILI9341 display description.
	param: The initialized Embedded.Hardware.SPI controller index.
	param: The output-capable GPIO used for active-low chip selection.
	param: The output-capable GPIO selecting command or pixel data.
	param: The output-capable GPIO connected to the panel reset input.
	param: True when the panel uses BGR rather than RGB subpixel order.
	param: True when the panel requires inverted display drive.
	param: The clockwise orientation used as logical rotation zero.
	returns: A display description, or Null when GPIOs or orientation are invalid.
	End Rem
	Function Create:TILI9341Display(controller:Int, chipSelectPin:UInt, ..
			dataCommandPin:UInt, resetPin:UInt, bgrOrder:Int = True, ..
			inverted:Int = False, orientation:Int = DisplayOrientation0)
		If controller < 0 Or ..
				Not GPIOIsValid(chipSelectPin) Or Not GPIOIsOutputCapable(chipSelectPin) Or ..
				Not GPIOIsValid(dataCommandPin) Or Not GPIOIsOutputCapable(dataCommandPin) Or ..
				Not GPIOIsValid(resetPin) Or Not GPIOIsOutputCapable(resetPin) Then Return Null

		Local display:TILI9341Display = New TILI9341Display
		display.controller = controller
		display.chipSelectPin = chipSelectPin
		display.dataCommandPin = dataCommandPin
		display.resetPin = resetPin
		display.bgrOrder = bgrOrder <> 0
		display.inverted = inverted <> 0
		display.commandBuffer = New Byte[16]
		display.transferBuffer = New Byte[1024]
		If Not display.SetOrientation(orientation) Then Return Null
		Return display
	End Function

	Rem
	bbdoc: Returns the native portrait width.
	returns: 240 pixels.
	End Rem
	Method Width:Int() Override
		Return 240
	End Method

	Rem
	bbdoc: Returns the native portrait height.
	returns: 320 pixels.
	End Rem
	Method Height:Int() Override
		Return 320
	End Method

	Rem
	bbdoc: Returns the raster format accepted by this driver.
	returns: DisplayPixelFormatRGB565.
	End Rem
	Method PreferredPixelFormat:Int() Override
		Return DisplayPixelFormatRGB565
	End Method

	Rem
	bbdoc: Resets and initializes the controller for 16-bit RGB565 transfers.
	returns: True when GPIO, SPI format, and every controller command succeed.
	End Rem
	Method Initialize:Int()
		If Not GPIOInit(chipSelectPin) Or Not GPIOSetOutput(chipSelectPin) Or ..
				Not GPIOInit(dataCommandPin) Or Not GPIOSetOutput(dataCommandPin) Or ..
				Not GPIOInit(resetPin) Or Not GPIOSetOutput(resetPin) Then Return False
		GPIOPut(chipSelectPin, True)
		GPIOPut(dataCommandPin, True)
		GPIOPut(resetPin, True)
		If Not SPISetFormat(controller, 8, SPIClockPolarity0, SPIClockPhase0, ..
				SPIBitOrderMSBFirst) Then Return False

		SleepMilliseconds(10)
		GPIOPut(resetPin, False)
		SleepMilliseconds(20)
		GPIOPut(resetPin, True)
		SleepMilliseconds(120)
		If Not SendCommand(ILI9341CommandSoftwareReset, 0) Then Return False
		SleepMilliseconds(150)

		commandBuffer[0] = $03; commandBuffer[1] = $80; commandBuffer[2] = $02
		If Not SendCommand($ef, 3) Then Return False
		commandBuffer[0] = $00; commandBuffer[1] = $c1; commandBuffer[2] = $30
		If Not SendCommand($cf, 3) Then Return False
		commandBuffer[0] = $64; commandBuffer[1] = $03; commandBuffer[2] = $12; commandBuffer[3] = $81
		If Not SendCommand($ed, 4) Then Return False
		commandBuffer[0] = $85; commandBuffer[1] = $00; commandBuffer[2] = $78
		If Not SendCommand($e8, 3) Then Return False
		commandBuffer[0] = $39; commandBuffer[1] = $2c; commandBuffer[2] = $00
		commandBuffer[3] = $34; commandBuffer[4] = $02
		If Not SendCommand($cb, 5) Then Return False
		commandBuffer[0] = $20
		If Not SendCommand($f7, 1) Then Return False
		commandBuffer[0] = $00; commandBuffer[1] = $00
		If Not SendCommand($ea, 2) Then Return False

		commandBuffer[0] = $23
		If Not SendCommand($c0, 1) Then Return False
		commandBuffer[0] = $10
		If Not SendCommand($c1, 1) Then Return False
		commandBuffer[0] = $3e; commandBuffer[1] = $28
		If Not SendCommand($c5, 2) Then Return False
		commandBuffer[0] = $86
		If Not SendCommand($c7, 1) Then Return False

		Local memoryAccess:Byte = ILI9341MemoryAccessColumnAddressOrder
		If bgrOrder Then memoryAccess :| ILI9341MemoryAccessBGR
		commandBuffer[0] = memoryAccess
		If Not SendCommand(ILI9341CommandMemoryAccess, 1) Then Return False
		commandBuffer[0] = $55
		If Not SendCommand(ILI9341CommandPixelFormat, 1) Then Return False

		commandBuffer[0] = $00; commandBuffer[1] = $18
		If Not SendCommand($b1, 2) Then Return False
		commandBuffer[0] = $08; commandBuffer[1] = $82; commandBuffer[2] = $27
		If Not SendCommand($b6, 3) Then Return False
		commandBuffer[0] = $00
		If Not SendCommand($f2, 1) Then Return False
		commandBuffer[0] = $01
		If Not SendCommand($26, 1) Then Return False

		commandBuffer[0] = $0f; commandBuffer[1] = $31; commandBuffer[2] = $2b
		commandBuffer[3] = $0c; commandBuffer[4] = $0e; commandBuffer[5] = $08
		commandBuffer[6] = $4e; commandBuffer[7] = $f1; commandBuffer[8] = $37
		commandBuffer[9] = $07; commandBuffer[10] = $10; commandBuffer[11] = $03
		commandBuffer[12] = $0e; commandBuffer[13] = $09; commandBuffer[14] = $00
		If Not SendCommand($e0, 15) Then Return False
		commandBuffer[0] = $00; commandBuffer[1] = $0e; commandBuffer[2] = $14
		commandBuffer[3] = $03; commandBuffer[4] = $11; commandBuffer[5] = $07
		commandBuffer[6] = $31; commandBuffer[7] = $c1; commandBuffer[8] = $48
		commandBuffer[9] = $08; commandBuffer[10] = $0f; commandBuffer[11] = $0c
		commandBuffer[12] = $31; commandBuffer[13] = $36; commandBuffer[14] = $0f
		If Not SendCommand($e1, 15) Then Return False

		If inverted Then
			If Not SendCommand(ILI9341CommandDisplayInversionOn, 0) Then Return False
		Else
			If Not SendCommand(ILI9341CommandDisplayInversionOff, 0) Then Return False
		End If
		If Not SendCommand(ILI9341CommandSleepOut, 0) Then Return False
		SleepMilliseconds(120)
		If Not SendCommand(ILI9341CommandDisplayOn, 0) Then Return False
		SleepMilliseconds(100)
		initialized = True
		Return True
	End Method

	Method IsInitialized:Int()
		Return initialized
	End Method

	Method SetEnabled:Int(enabled:Int) Override
		If Not initialized Then Return False
		If enabled Then Return SendCommand(ILI9341CommandDisplayOn, 0)
		Return SendCommand(ILI9341CommandDisplayOff, 0)
	End Method

	Method SetInverted:Int(inverted:Int)
		If Not initialized Then Return False
		Self.inverted = inverted <> 0
		If Self.inverted Then Return SendCommand(ILI9341CommandDisplayInversionOn, 0)
		Return SendCommand(ILI9341CommandDisplayInversionOff, 0)
	End Method

	Rem
	bbdoc: Synchronously transfers a clipped RGB565 raster region over SPI.
	param: A pointer to the first byte of the complete raster.
	param: The number of bytes between adjacent raster rows.
	param: The raster pixel format, which must be DisplayPixelFormatRGB565.
	param: The requested physical left edge.
	param: The requested physical top edge.
	param: The requested region width in pixels.
	param: The requested region height in pixels.
	returns: True on success, or a DisplayError value on failure.
	End Rem
	Method PresentPixels:Int(pixels:Byte Ptr, stride:Int, format:Int, ..
			x:Int, y:Int, width:Int, height:Int) Override
		If Not initialized Or pixels = Null Then Return DisplayErrorInvalidArgument
		If format <> DisplayPixelFormatRGB565 Then Return DisplayErrorUnsupportedFormat
		If stride < DisplayMinimumStride(240, format) Or width <= 0 Or height <= 0 Then ..
			Return DisplayErrorInvalidArgument

		Local x0:Int = x
		Local y0:Int = y
		Local x1:Int = x + width
		Local y1:Int = y + height
		If x0 < 0 Then x0 = 0
		If y0 < 0 Then y0 = 0
		If x1 > 240 Then x1 = 240
		If y1 > 320 Then y1 = 320
		If x0 >= x1 Or y0 >= y1 Then Return DisplayErrorInvalidArgument
		If Not BeginMemoryWrite(x0, y0, x1 - x0, y1 - y0) Then Return DisplayErrorGeneric

		Local outputCount:Int
		For Local py:Int = y0 Until y1
			Local source:Byte Ptr = pixels + py * stride + x0 * 2
			For Local px:Int = x0 Until x1
				transferBuffer[outputCount] = source[1]
				transferBuffer[outputCount + 1] = source[0]
				outputCount :+ 2
				source :+ 2
				If outputCount = transferBuffer.length Then
					If SPIWriteBlocking(controller, Varptr transferBuffer[0], outputCount) <> outputCount Then
						GPIOPut(chipSelectPin, True)
						Return DisplayErrorGeneric
					End If
					outputCount = 0
				End If
			Next
		Next
		If outputCount And SPIWriteBlocking(controller, Varptr transferBuffer[0], outputCount) <> outputCount Then
			GPIOPut(chipSelectPin, True)
			Return DisplayErrorGeneric
		End If
		GPIOPut(chipSelectPin, True)
		Return True
	End Method

	Private
	Method SendCommand:Int(command:Byte, argumentCount:Int)
		If argumentCount < 0 Or argumentCount > commandBuffer.length Then Return False
		GPIOPut(chipSelectPin, False)
		GPIOPut(dataCommandPin, False)
		Local commandByte:Byte = command
		If SPIWriteBlocking(controller, Varptr commandByte, 1) <> 1 Then
			GPIOPut(chipSelectPin, True)
			Return False
		End If
		If argumentCount Then
			GPIOPut(dataCommandPin, True)
			If SPIWriteBlocking(controller, Varptr commandBuffer[0], argumentCount) <> argumentCount Then
				GPIOPut(chipSelectPin, True)
				Return False
			End If
		End If
		GPIOPut(chipSelectPin, True)
		Return True
	End Method

	Method BeginMemoryWrite:Int(x:Int, y:Int, width:Int, height:Int)
		Local lastColumn:Int = x + width - 1
		Local lastRow:Int = y + height - 1
		commandBuffer[0] = Byte(x Shr 8); commandBuffer[1] = Byte(x)
		commandBuffer[2] = Byte(lastColumn Shr 8); commandBuffer[3] = Byte(lastColumn)
		If Not SendCommand(ILI9341CommandColumnAddress, 4) Then Return False
		commandBuffer[0] = Byte(y Shr 8); commandBuffer[1] = Byte(y)
		commandBuffer[2] = Byte(lastRow Shr 8); commandBuffer[3] = Byte(lastRow)
		If Not SendCommand(ILI9341CommandRowAddress, 4) Then Return False
		GPIOPut(chipSelectPin, False)
		GPIOPut(dataCommandPin, False)
		Local commandByte:Byte = ILI9341CommandMemoryWrite
		If SPIWriteBlocking(controller, Varptr commandByte, 1) <> 1 Then
			GPIOPut(chipSelectPin, True)
			Return False
		End If
		GPIOPut(dataCommandPin, True)
		Return True
	End Method
End Type
?
