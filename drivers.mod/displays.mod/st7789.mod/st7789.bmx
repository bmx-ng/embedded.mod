' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: ST7789-compatible colour TFT displays over portable SPI.
about: The application configures and initializes the SPI controller before
calling Initialize. Chip-select, data/command, and reset are ordinary GPIOs
owned by this display instance. RGB565 display buffers are converted from the
shared little-endian representation to the controller's wire byte order while
being transferred; no frame-sized staging buffer is allocated.
End Rem
Module Embedded.Drivers.Displays.ST7789
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Drivers.Display
Import Embedded.Hardware.GPIO
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Rem
bbdoc: Requests an ST7789 controller software reset.
End Rem
Const ST7789CommandSoftwareReset:Byte = $01

Rem
bbdoc: Places an ST7789 controller into its low-power sleep state.
End Rem
Const ST7789CommandSleepIn:Byte = $10

Rem
bbdoc: Wakes an ST7789 controller from its sleep state.
End Rem
Const ST7789CommandSleepOut:Byte = $11

Rem
bbdoc: Selects normal display mode on an ST7789 controller.
End Rem
Const ST7789CommandNormalOn:Byte = $13

Rem
bbdoc: Disables ST7789 display inversion.
End Rem
Const ST7789CommandDisplayInversionOff:Byte = $20

Rem
bbdoc: Enables ST7789 display inversion.
End Rem
Const ST7789CommandDisplayInversionOn:Byte = $21

Rem
bbdoc: Disables ST7789 display output without changing display RAM.
End Rem
Const ST7789CommandDisplayOff:Byte = $28

Rem
bbdoc: Enables ST7789 display output.
End Rem
Const ST7789CommandDisplayOn:Byte = $29

Rem
bbdoc: Selects the inclusive ST7789 display-RAM column range.
End Rem
Const ST7789CommandColumnAddress:Byte = $2a

Rem
bbdoc: Selects the inclusive ST7789 display-RAM row range.
End Rem
Const ST7789CommandRowAddress:Byte = $2b

Rem
bbdoc: Begins writing pixel data to ST7789 display RAM.
End Rem
Const ST7789CommandMemoryWrite:Byte = $2c

Rem
bbdoc: Configures ST7789 address order, axis exchange, refresh direction, and RGB order.
End Rem
Const ST7789CommandMemoryAccess:Byte = $36

Rem
bbdoc: Configures the ST7789 wire pixel format.
End Rem
Const ST7789CommandPixelFormat:Byte = $3a

Rem
bbdoc: Reverses ST7789 row address order in the memory-access register.
End Rem
Const ST7789MemoryAccessRowAddressOrder:Byte = $80

Rem
bbdoc: Reverses ST7789 column address order in the memory-access register.
End Rem
Const ST7789MemoryAccessColumnAddressOrder:Byte = $40

Rem
bbdoc: Exchanges ST7789 row and column addressing axes.
End Rem
Const ST7789MemoryAccessRowColumnExchange:Byte = $20

Rem
bbdoc: Reverses the ST7789 vertical refresh order.
End Rem
Const ST7789MemoryAccessVerticalRefreshOrder:Byte = $10

Rem
bbdoc: Selects BGR rather than RGB subpixel order on the ST7789 panel.
End Rem
Const ST7789MemoryAccessBGR:Byte = $08

Rem
bbdoc: An SPI ST7789-compatible colour display.
End Rem
Type TST7789Display Extends TDisplay
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
	bbdoc: Creates a configurable ST7789 display description.
	param: The initialized Embedded.Hardware.SPI controller index.
	param: The output-capable GPIO used for active-low chip selection.
	param: The output-capable GPIO selecting command or pixel data.
	param: The output-capable GPIO connected to the panel reset input.
	param: The visible portrait width in pixels.
	param: The visible portrait height in pixels.
	param: The visible raster's first column in controller display RAM.
	param: The visible raster's first row in controller display RAM.
	param: True when the panel uses BGR rather than RGB subpixel order.
	param: True when the panel requires inverted display drive.
	param: The clockwise orientation used as logical rotation zero.
	returns: A display description, or Null when dimensions, offsets, GPIOs, or orientation are invalid.
	End Rem
	Function Create:TST7789Display(controller:Int, chipSelectPin:UInt, ..
			dataCommandPin:UInt, resetPin:UInt, width:Int, height:Int, ..
			columnOffset:Int = 0, rowOffset:Int = 0, bgrOrder:Int = False, ..
			inverted:Int = True, orientation:Int = DisplayOrientation0)
		If controller < 0 Or width <= 0 Or height <= 0 Or width > 240 Or ..
				height > 320 Or columnOffset < 0 Or rowOffset < 0 Or ..
				columnOffset + width > 240 Or rowOffset + height > 320 Or ..
				Not GPIOIsValid(chipSelectPin) Or Not GPIOIsOutputCapable(chipSelectPin) Or ..
				Not GPIOIsValid(dataCommandPin) Or Not GPIOIsOutputCapable(dataCommandPin) Or ..
				Not GPIOIsValid(resetPin) Or Not GPIOIsOutputCapable(resetPin) Then Return Null

		Local display:TST7789Display = New TST7789Display
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
		display.transferBuffer = New Byte[1024]
		If Not display.SetOrientation(orientation) Then Return Null
		Return display
	End Function

	Rem
	bbdoc: Creates the common full-size 240x320 ST7789 panel configuration.
	param: The initialized Embedded.Hardware.SPI controller index.
	param: The output-capable GPIO used for active-low chip selection.
	param: The output-capable GPIO selecting command or pixel data.
	param: The output-capable GPIO connected to the panel reset input.
	param: True when the panel uses BGR rather than RGB subpixel order.
	param: True when the panel requires inverted display drive.
	param: The clockwise orientation used as logical rotation zero.
	returns: A 240x320 display description, or Null when its GPIOs or orientation are invalid.
	End Rem
	Function Create240x320:TST7789Display(controller:Int, chipSelectPin:UInt, ..
			dataCommandPin:UInt, resetPin:UInt, bgrOrder:Int = False, ..
			inverted:Int = True, orientation:Int = DisplayOrientation0)
		Return Create(controller, chipSelectPin, dataCommandPin, resetPin, ..
			240, 320, 0, 0, bgrOrder, inverted, orientation)
	End Function

	Rem
	bbdoc: Returns the configured visible panel width.
	returns: The native portrait width in pixels.
	End Rem
	Method Width:Int() Override
		Return displayWidth
	End Method

	Rem
	bbdoc: Returns the configured visible panel height.
	returns: The native portrait height in pixels.
	End Rem
	Method Height:Int() Override
		Return displayHeight
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
		If Not SendCommand(ST7789CommandSoftwareReset, 0) Then Return False
		SleepMilliseconds(150)
		If Not SendCommand(ST7789CommandSleepOut, 0) Then Return False
		SleepMilliseconds(120)

		commandBuffer[0] = $55
		If Not SendCommand(ST7789CommandPixelFormat, 1) Then Return False
		SleepMilliseconds(10)

		Local memoryAccess:Byte = ST7789MemoryAccessRowAddressOrder | ..
			ST7789MemoryAccessColumnAddressOrder
		If bgrOrder Then memoryAccess :| ST7789MemoryAccessBGR
		commandBuffer[0] = memoryAccess
		If Not SendCommand(ST7789CommandMemoryAccess, 1) Then Return False

		commandBuffer[0] = $0c; commandBuffer[1] = $0c; commandBuffer[2] = $00
		commandBuffer[3] = $33; commandBuffer[4] = $33
		If Not SendCommand($b2, 5) Then Return False
		commandBuffer[0] = $35
		If Not SendCommand($b7, 1) Then Return False
		commandBuffer[0] = $19
		If Not SendCommand($bb, 1) Then Return False
		commandBuffer[0] = $2c
		If Not SendCommand($c0, 1) Then Return False
		commandBuffer[0] = $01
		If Not SendCommand($c2, 1) Then Return False
		commandBuffer[0] = $12
		If Not SendCommand($c3, 1) Then Return False
		commandBuffer[0] = $20
		If Not SendCommand($c4, 1) Then Return False
		commandBuffer[0] = $0f
		If Not SendCommand($c6, 1) Then Return False
		commandBuffer[0] = $a4; commandBuffer[1] = $a1
		If Not SendCommand($d0, 2) Then Return False

		commandBuffer[0] = $d0; commandBuffer[1] = $04; commandBuffer[2] = $0d
		commandBuffer[3] = $11; commandBuffer[4] = $13; commandBuffer[5] = $2b
		commandBuffer[6] = $3f; commandBuffer[7] = $54; commandBuffer[8] = $4c
		commandBuffer[9] = $18; commandBuffer[10] = $0d; commandBuffer[11] = $0b
		commandBuffer[12] = $1f; commandBuffer[13] = $23
		If Not SendCommand($e0, 14) Then Return False
		commandBuffer[0] = $d0; commandBuffer[1] = $04; commandBuffer[2] = $0c
		commandBuffer[3] = $11; commandBuffer[4] = $13; commandBuffer[5] = $2c
		commandBuffer[6] = $3f; commandBuffer[7] = $44; commandBuffer[8] = $51
		commandBuffer[9] = $2f; commandBuffer[10] = $1f; commandBuffer[11] = $1f
		commandBuffer[12] = $20; commandBuffer[13] = $23
		If Not SendCommand($e1, 14) Then Return False

		If inverted Then
			If Not SendCommand(ST7789CommandDisplayInversionOn, 0) Then Return False
		Else
			If Not SendCommand(ST7789CommandDisplayInversionOff, 0) Then Return False
		End If
		If Not SendCommand(ST7789CommandNormalOn, 0) Then Return False
		SleepMilliseconds(10)
		If Not SendCommand(ST7789CommandDisplayOn, 0) Then Return False
		SleepMilliseconds(100)
		initialized = True
		Return True
	End Method

	Rem
	bbdoc: Reports whether controller initialization completed successfully.
	returns: True after a successful Initialize call.
	End Rem
	Method IsInitialized:Int()
		Return initialized
	End Method

	Rem
	bbdoc: Enables or disables panel output while preserving display RAM.
	param: True to turn the display on, or False to turn it off.
	returns: True when the controller accepts the command.
	End Rem
	Method SetEnabled:Int(enabled:Int) Override
		If Not initialized Then Return False
		If enabled Then Return SendCommand(ST7789CommandDisplayOn, 0)
		Return SendCommand(ST7789CommandDisplayOff, 0)
	End Method

	Rem
	bbdoc: Enables or disables the controller's display-inversion mode.
	param: True for inverted drive, or False for normal drive.
	returns: True when the initialized controller accepts the command.
	End Rem
	Method SetInverted:Int(inverted:Int)
		If Not initialized Then Return False
		Self.inverted = inverted <> 0
		If Self.inverted Then Return SendCommand(ST7789CommandDisplayInversionOn, 0)
		Return SendCommand(ST7789CommandDisplayInversionOff, 0)
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
		If Not SendCommand(ST7789CommandColumnAddress, 4) Then Return False
		commandBuffer[0] = Byte(firstRow Shr 8)
		commandBuffer[1] = Byte(firstRow)
		commandBuffer[2] = Byte(lastRow Shr 8)
		commandBuffer[3] = Byte(lastRow)
		If Not SendCommand(ST7789CommandRowAddress, 4) Then Return False
		GPIOPut(chipSelectPin, False)
		GPIOPut(dataCommandPin, False)
		Local commandByte:Byte = ST7789CommandMemoryWrite
		If SPIWriteBlocking(controller, Varptr commandByte, 1) <> 1 Then
			GPIOPut(chipSelectPin, True)
			Return False
		End If
		GPIOPut(dataCommandPin, True)
		Return True
	End Method
End Type
?
