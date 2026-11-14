' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: ST7735-compatible colour TFT displays over portable SPI.
about: The application configures and initializes the SPI controller before
calling Initialize. Chip-select, data/command, and reset are ordinary GPIOs
owned by this display instance. RGB565 display buffers are converted from the
shared little-endian representation to the controller's wire byte order while
being transferred; no frame-sized staging buffer is allocated.
End Rem
Module Embedded.Drivers.Displays.ST7735
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Drivers.Display
Import Embedded.Hardware.GPIO
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const ST7735CommandSoftwareReset:Byte = $01
Const ST7735CommandSleepIn:Byte = $10
Const ST7735CommandSleepOut:Byte = $11
Const ST7735CommandNormalOn:Byte = $13
Const ST7735CommandDisplayInversionOff:Byte = $20
Const ST7735CommandDisplayInversionOn:Byte = $21
Const ST7735CommandDisplayOff:Byte = $28
Const ST7735CommandDisplayOn:Byte = $29
Const ST7735CommandColumnAddress:Byte = $2a
Const ST7735CommandRowAddress:Byte = $2b
Const ST7735CommandMemoryWrite:Byte = $2c
Const ST7735CommandMemoryAccess:Byte = $36
Const ST7735CommandPixelFormat:Byte = $3a

Const ST7735MemoryAccessRowAddressOrder:Byte = $80
Const ST7735MemoryAccessColumnAddressOrder:Byte = $40
Const ST7735MemoryAccessRowColumnExchange:Byte = $20
Const ST7735MemoryAccessVerticalRefreshOrder:Byte = $10
Const ST7735MemoryAccessBGR:Byte = $08

Rem
bbdoc: An SPI ST7735-compatible colour display.
End Rem
Type TST7735Display Extends TDisplay
	Private
	Field controller:Int
	Field chipSelectPin:UInt
	Field dataCommandPin:UInt
	Field resetPin:UInt
	Field displayWidth:Int
	Field displayHeight:Int
	Field columnOffset:Int
	Field rowOffset:Int
	Field bgrOrder:Int
	Field inverted:Int
	Field initialized:Int
	Field commandBuffer:Byte[]
	Field transferBuffer:Byte[]

	Public
	Rem
	bbdoc: Creates a configurable ST7735 display description.
	about: Width and height describe the visible portrait raster. Column and row
	offsets locate it within the controller's 132x162 display RAM. The application
	must configure and initialize the selected SPI controller before Initialize.
	End Rem
	Function Create:TST7735Display(controller:Int, chipSelectPin:UInt, ..
			dataCommandPin:UInt, resetPin:UInt, width:Int, height:Int, ..
			columnOffset:Int = 0, rowOffset:Int = 0, bgrOrder:Int = True, ..
			inverted:Int = False, orientation:Int = DisplayOrientation0)
		If controller < 0 Or width <= 0 Or height <= 0 Or width > 132 Or ..
				height > 162 Or columnOffset < 0 Or rowOffset < 0 Or ..
				columnOffset + width > 132 Or rowOffset + height > 162 Or ..
				Not GPIOIsValid(chipSelectPin) Or Not GPIOIsOutputCapable(chipSelectPin) Or ..
				Not GPIOIsValid(dataCommandPin) Or Not GPIOIsOutputCapable(dataCommandPin) Or ..
				Not GPIOIsValid(resetPin) Or Not GPIOIsOutputCapable(resetPin) Then Return Null

		Local display:TST7735Display = New TST7735Display
		display.controller = controller
		display.chipSelectPin = chipSelectPin
		display.dataCommandPin = dataCommandPin
		display.resetPin = resetPin
		display.displayWidth = width
		display.displayHeight = height
		display.columnOffset = columnOffset
		display.rowOffset = rowOffset
		display.bgrOrder = bgrOrder <> 0
		display.inverted = inverted <> 0
		display.commandBuffer = New Byte[16]
		display.transferBuffer = New Byte[512]
		If Not display.SetOrientation(orientation) Then Return Null
		Return display
	End Function

	Rem
	bbdoc: Creates the common full-size 128x160 ST7735S panel configuration.
	End Rem
	Function Create128x160:TST7735Display(controller:Int, chipSelectPin:UInt, ..
			dataCommandPin:UInt, resetPin:UInt, bgrOrder:Int = True, ..
			inverted:Int = False, orientation:Int = DisplayOrientation0)
		Return Create(controller, chipSelectPin, dataCommandPin, resetPin, ..
			128, 160, 0, 0, bgrOrder, inverted, orientation)
	End Function

	Method Width:Int() Override
		Return displayWidth
	End Method

	Method Height:Int() Override
		Return displayHeight
	End Method

	Method PreferredPixelFormat:Int() Override
		Return DisplayPixelFormatRGB565
	End Method

	Rem
	bbdoc: Resets and initializes the controller for 16-bit RGB565 transfers.
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

		If Not SendCommand(ST7735CommandSoftwareReset, 0) Then Return False
		SleepMilliseconds(150)
		If Not SendCommand(ST7735CommandSleepOut, 0) Then Return False
		SleepMilliseconds(120)

		' Conservative ST7735R/ST7735S power, frame-rate, and gamma setup. The
		' values are accepted by common full-size modules and remain independent
		' of the visible panel offsets configured above.
		commandBuffer[0] = $01; commandBuffer[1] = $2c; commandBuffer[2] = $2d
		If Not SendCommand($b1, 3) Or Not SendCommand($b2, 3) Then Return False
		commandBuffer[0] = $01; commandBuffer[1] = $2c; commandBuffer[2] = $2d
		commandBuffer[3] = $01; commandBuffer[4] = $2c; commandBuffer[5] = $2d
		If Not SendCommand($b3, 6) Then Return False
		commandBuffer[0] = $07
		If Not SendCommand($b4, 1) Then Return False
		commandBuffer[0] = $a2; commandBuffer[1] = $02; commandBuffer[2] = $84
		If Not SendCommand($c0, 3) Then Return False
		commandBuffer[0] = $c5
		If Not SendCommand($c1, 1) Then Return False
		commandBuffer[0] = $0a; commandBuffer[1] = $00
		If Not SendCommand($c2, 2) Then Return False
		commandBuffer[0] = $8a; commandBuffer[1] = $2a
		If Not SendCommand($c3, 2) Then Return False
		commandBuffer[0] = $8a; commandBuffer[1] = $ee
		If Not SendCommand($c4, 2) Then Return False
		commandBuffer[0] = $0e
		If Not SendCommand($c5, 1) Then Return False

		Local memoryAccess:Byte = ST7735MemoryAccessRowAddressOrder | ..
			ST7735MemoryAccessColumnAddressOrder
		If bgrOrder Then memoryAccess :| ST7735MemoryAccessBGR
		commandBuffer[0] = memoryAccess
		If Not SendCommand(ST7735CommandMemoryAccess, 1) Then Return False
		commandBuffer[0] = $05
		If Not SendCommand(ST7735CommandPixelFormat, 1) Then Return False

		If inverted Then
			If Not SendCommand(ST7735CommandDisplayInversionOn, 0) Then Return False
		Else
			If Not SendCommand(ST7735CommandDisplayInversionOff, 0) Then Return False
		End If

		If Not SendCommand(ST7735CommandNormalOn, 0) Then Return False
		SleepMilliseconds(10)
		If Not SendCommand(ST7735CommandDisplayOn, 0) Then Return False
		SleepMilliseconds(100)
		initialized = True
		Return True
	End Method

	Method IsInitialized:Int()
		Return initialized
	End Method

	Method SetEnabled:Int(enabled:Int) Override
		If Not initialized Then Return False
		If enabled Then Return SendCommand(ST7735CommandDisplayOn, 0)
		Return SendCommand(ST7735CommandDisplayOff, 0)
	End Method

	Method SetInverted:Int(inverted:Int)
		If Not initialized Then Return False
		Self.inverted = inverted <> 0
		If Self.inverted Then Return SendCommand(ST7735CommandDisplayInversionOn, 0)
		Return SendCommand(ST7735CommandDisplayInversionOff, 0)
	End Method

	Method PresentPixels:Int(pixels:Byte Ptr, stride:Int, format:Int, ..
			x:Int, y:Int, width:Int, height:Int) Override
		If Not initialized Or pixels = Null Then Return DisplayErrorInvalidArgument
		If format <> DisplayPixelFormatRGB565 Then Return DisplayErrorUnsupportedFormat
		If stride < DisplayMinimumStride(displayWidth, format) Or width <= 0 Or height <= 0 Then ..
			Return DisplayErrorInvalidArgument

		Local x0:Int = x
		Local y0:Int = y
		Local x1:Int = x + width
		Local y1:Int = y + height
		If x0 < 0 Then x0 = 0
		If y0 < 0 Then y0 = 0
		If x1 > displayWidth Then x1 = displayWidth
		If y1 > displayHeight Then y1 = displayHeight
		If x0 >= x1 Or y0 >= y1 Then Return DisplayErrorInvalidArgument

		If Not BeginMemoryWrite(x0, y0, x1 - x0, y1 - y0) Then Return DisplayErrorGeneric

		Local outputCount:Int
		For Local py:Int = y0 Until y1
			Local source:Byte Ptr = pixels + py * stride + x0 * 2
			For Local px:Int = x0 Until x1
				' TDisplayBuffer stores RGB565 little-endian; the serial controller
				' consumes each pixel most-significant byte first.
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
		Local firstColumn:Int = columnOffset + x
		Local lastColumn:Int = firstColumn + width - 1
		Local firstRow:Int = rowOffset + y
		Local lastRow:Int = firstRow + height - 1

		commandBuffer[0] = Byte(firstColumn Shr 8)
		commandBuffer[1] = Byte(firstColumn)
		commandBuffer[2] = Byte(lastColumn Shr 8)
		commandBuffer[3] = Byte(lastColumn)
		If Not SendCommand(ST7735CommandColumnAddress, 4) Then Return False
		commandBuffer[0] = Byte(firstRow Shr 8)
		commandBuffer[1] = Byte(firstRow)
		commandBuffer[2] = Byte(lastRow Shr 8)
		commandBuffer[3] = Byte(lastRow)
		If Not SendCommand(ST7735CommandRowAddress, 4) Then Return False

		GPIOPut(chipSelectPin, False)
		GPIOPut(dataCommandPin, False)
		Local commandByte:Byte = ST7735CommandMemoryWrite
		If SPIWriteBlocking(controller, Varptr commandByte, 1) <> 1 Then
			GPIOPut(chipSelectPin, True)
			Return False
		End If
		GPIOPut(dataCommandPin, True)
		Return True
	End Method
End Type
?
