' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: CH1116-compatible monochrome OLED displays over portable four-wire SPI.
about: The driver accepts the shared row-major Mono1 display format and
converts it to the CH1116's vertical eight-pixel page layout during synchronous
presentation. The application must configure and initialize the SPI controller
before calling Initialize. Reset is optional because some modules expose only
chip-select, clock, data, and data/command signals.
End Rem
Module Embedded.Drivers.Displays.CH1116
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Drivers.Display
Import Embedded.Hardware.GPIO
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Rem
bbdoc: Indicates that an CH1116 module has no separately controllable reset pin.
End Rem
Const CH1116NoResetPin:UInt = SPIUnavailablePin

Rem
bbdoc: An SPI CH1116-compatible monochrome display.
End Rem
Type TCH1116Display Extends TDisplay
	Private
	Field controller:Int
	Field chipSelectPin:UInt
	Field dataCommandPin:UInt
	Field resetPin:UInt
	Field displayWidth:Int
	Field displayHeight:Int
	Field columnOffset:Int
	Field pageOffset:Int
	Field contrast:Byte
	Field initialized:Int
	Field commandBuffer:Byte[]
	Field dataBuffer:Byte[]

	Public
	Rem
	bbdoc: Creates a configurable SPI CH1116 display description.
	param: The initialized Embedded.Hardware.SPI controller index.
	param: The output-capable GPIO used for active-low chip selection.
	param: The output-capable GPIO selecting commands or display data.
	param: The output-capable reset GPIO, or CH1116NoResetPin when it is not exposed.
	param: The visible width in pixels.
	param: The visible height in pixels.
	param: The visible raster's first column in display RAM.
	param: The visible raster's first eight-pixel page in display RAM.
	param: The clockwise orientation used as logical rotation zero.
	returns: A display description, or Null when its dimensions, offsets, GPIOs, or orientation are invalid.
	about: This does not configure or initialize the selected SPI controller.
	The CH1116 supports at most 132 by 64 pixels arranged as eight pages.
	End Rem
	Function Create:TCH1116Display(controller:Int, chipSelectPin:UInt, ..
			dataCommandPin:UInt, resetPin:UInt, width:Int, height:Int, ..
			columnOffset:Int = 0, pageOffset:Int = 0, ..
			orientation:Int = DisplayOrientation0)
		If controller < 0 Or width <= 0 Or width > 132 Or height <= 0 Or ..
				height > 64 Or columnOffset < 0 Or columnOffset + width > 132 Or ..
				pageOffset < 0 Or pageOffset + ((height + 7) / 8) > 8 Or ..
				Not GPIOIsValid(chipSelectPin) Or Not GPIOIsOutputCapable(chipSelectPin) Or ..
				Not GPIOIsValid(dataCommandPin) Or Not GPIOIsOutputCapable(dataCommandPin) Then
			Return Null
		End If

		If resetPin <> CH1116NoResetPin And ..
				(Not GPIOIsValid(resetPin) Or Not GPIOIsOutputCapable(resetPin)) Then
			Return Null
		End If

		Local display:TCH1116Display = New TCH1116Display
		display.controller = controller
		display.chipSelectPin = chipSelectPin
		display.dataCommandPin = dataCommandPin
		display.resetPin = resetPin
		display.displayWidth = width
		display.displayHeight = height
		display.columnOffset = columnOffset
		display.pageOffset = pageOffset
		display.contrast = $7f
		display.commandBuffer = New Byte[32]
		display.dataBuffer = New Byte[width]
		If Not display.SetOrientation(orientation) Then Return Null
		Return display
	End Function

	Rem
	bbdoc: Creates the common full-size 128x64 CH1116 panel configuration.
	param: The initialized Embedded.Hardware.SPI controller index.
	param: The output-capable GPIO used for active-low chip selection.
	param: The output-capable GPIO selecting commands or display data.
	param: The output-capable reset GPIO, or CH1116NoResetPin when it is not exposed.
	param: The clockwise orientation used as logical rotation zero.
	returns: A 128x64 display description, or Null when its GPIOs or orientation are invalid.
	End Rem
	Function Create128x64:TCH1116Display(controller:Int, chipSelectPin:UInt, ..
			dataCommandPin:UInt, resetPin:UInt = CH1116NoResetPin, ..
			orientation:Int = DisplayOrientation0)
		Return Create(controller, chipSelectPin, dataCommandPin, resetPin, ..
			128, 64, 0, 0, orientation)
	End Function

	Rem
	bbdoc: Returns the configured visible panel width.
	returns: The native width in pixels.
	End Rem
	Method Width:Int() Override
		Return displayWidth
	End Method

	Rem
	bbdoc: Returns the configured visible panel height.
	returns: The native height in pixels.
	End Rem
	Method Height:Int() Override
		Return displayHeight
	End Method

	Rem
	bbdoc: Returns the raster format accepted by this driver.
	returns: DisplayPixelFormatMono1.
	End Rem
	Method PreferredPixelFormat:Int() Override
		Return DisplayPixelFormatMono1
	End Method

	Rem
	bbdoc: Initializes the panel for monochrome page transfers and enables its output.
	returns: True when GPIO, SPI format, and every controller command succeed.
	about: When no reset GPIO is supplied, the module must have completed its
	power-on reset before this method is called. The application must configure
	and initialize the selected SPI controller first.
	End Rem
	Method Initialize:Int()
		If Not GPIOInit(chipSelectPin) Or Not GPIOSetOutput(chipSelectPin) Or ..
				Not GPIOInit(dataCommandPin) Or Not GPIOSetOutput(dataCommandPin) Then
			Return False
		End If

		GPIOPut(chipSelectPin, True)
		GPIOPut(dataCommandPin, True)
		If resetPin <> CH1116NoResetPin Then
			If Not GPIOInit(resetPin) Or Not GPIOSetOutput(resetPin) Then Return False
			GPIOPut(resetPin, True)
		End If

		If Not SPISetFormat(controller, 8, SPIClockPolarity0, SPIClockPhase0, ..
				SPIBitOrderMSBFirst) Then Return False

		SleepMilliseconds(20)
		If resetPin <> CH1116NoResetPin Then
			GPIOPut(resetPin, False)
			SleepMilliseconds(3)
			GPIOPut(resetPin, True)
			SleepMilliseconds(30)
		End If

		Local setup:Byte[] = [Byte($ae), Byte($d5), Byte($80), Byte($a8), Byte($3f), ..
			Byte($d3), Byte($00), Byte($40), ..
			Byte($a1), Byte($c8), Byte($da), Byte($12), Byte($81), contrast, ..
			Byte($d9), Byte($22), Byte($db), Byte($20), Byte($a4), Byte($a6), ..
			Byte($23), Byte($00), Byte($ad), Byte($8b), Byte($00), Byte($10)]
		If Not SendCommands(setup) Then Return False
		Local clearPage:Byte[] = New Byte[132]
		For Local page:Int = 0 Until 8
			Local address:Byte[] = [Byte($b0 | page), Byte($00), Byte($10)]
			If Not SendCommands(address) Then Return False
			GPIOPut(chipSelectPin, False)
			GPIOPut(dataCommandPin, True)
			Local written:Int = SPIWriteBlocking(controller, Varptr clearPage[0], clearPage.length)
			GPIOPut(chipSelectPin, True)
			If written <> clearPage.length Then Return False
		Next

		SleepMilliseconds(100)
		initialized = SendCommand($af)
		Return initialized
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
	returns: True when the initialized controller accepts the command.
	End Rem
	Method SetEnabled:Int(enabled:Int) Override
		If Not initialized Then Return False
		If enabled Then Return SendCommand($af)
		Return SendCommand($ae)
	End Method

	Rem
	bbdoc: Changes the CH1116 segment-current contrast setting.
	param: The controller contrast value from 0 through 255.
	returns: True when the initialized controller accepts the setting.
	End Rem
	Method SetContrast:Int(value:Byte)
		If Not initialized Then Return False
		contrast = value
		Local commands:Byte[] = [Byte($81), value]
		Return SendCommands(commands)
	End Method

	Rem
	bbdoc: Selects normal or inverted monochrome output.
	param: True to exchange lit and unlit pixels, or False for normal output.
	returns: True when the initialized controller accepts the command.
	End Rem
	Method SetInverted:Int(inverted:Int)
		If Not initialized Then Return False
		If inverted Then Return SendCommand($a7)
		Return SendCommand($a6)
	End Method

	Rem
	bbdoc: Forces every panel pixel on or restores display RAM output.
	param: True to illuminate all pixels, False to restore RAM output.
	returns: True when the initialized controller accepts the command.
	End Rem
	Method SetAllPixels:Int(enabled:Int)
		If Not initialized Then Return False
		If enabled Then Return SendCommand($a5)
		Return SendCommand($a4)
	End Method

	Rem
	bbdoc: Reverses both controller scan axes to turn the physical panel upside down.
	param: True for flipped scanning, or False for the preset's normal scanning.
	returns: True when the initialized controller accepts both commands.
	about: This controller setting is independent of the logical display
	orientation used by Graphics2D.
	End Rem
	Method SetFlipped:Int(flipped:Int)
		If Not initialized Then Return False
		If flipped Then
			Local commands:Byte[] = [Byte($a0), Byte($c0)]
			Return SendCommands(commands)
		End If
		Local commands:Byte[] = [Byte($a1), Byte($c8)]
		Return SendCommands(commands)
	End Method

	Rem
	bbdoc: Synchronously transfers a clipped Mono1 raster region over SPI.
	param: A pointer to the first byte of the complete row-major raster.
	param: The number of bytes between adjacent raster rows.
	param: The raster pixel format, which must be DisplayPixelFormatMono1.
	param: The requested physical left edge.
	param: The requested physical top edge.
	param: The requested region width in pixels.
	param: The requested region height in pixels.
	returns: True on success, or a DisplayError value on failure.
	about: The shared row-major, most-significant-bit-first Mono1 raster is
	converted during transfer to the CH1116's vertical eight-pixel page layout.
	The requested rectangle is clipped to the panel and expanded to every
	controller page intersecting its vertical extent.
	End Rem
	Method PresentPixels:Int(pixels:Byte Ptr, stride:Int, format:Int, ..
			x:Int, y:Int, width:Int, height:Int) Override
		If Not initialized Or pixels = Null Then Return DisplayErrorInvalidArgument
		If format <> DisplayPixelFormatMono1 Then Return DisplayErrorUnsupportedFormat
		If stride < DisplayMinimumStride(displayWidth, format) Or width <= 0 Or ..
				height <= 0 Then Return DisplayErrorInvalidArgument

		Local x0:Int = x
		Local y0:Int = y
		Local x1:Int = x + width
		Local y1:Int = y + height
		If x0 < 0 Then x0 = 0
		If y0 < 0 Then y0 = 0
		If x1 > displayWidth Then x1 = displayWidth
		If y1 > displayHeight Then y1 = displayHeight
		If x0 >= x1 Or y0 >= y1 Then Return DisplayErrorInvalidArgument

		Local firstPage:Int = y0 Shr 3
		Local lastPage:Int = (y1 - 1) Shr 3
		For Local page:Int = firstPage To lastPage
			For Local px:Int = x0 Until x1
				Local packed:Byte
				For Local bit:Int = 0 Until 8
					Local py:Int = page * 8 + bit
					If py < displayHeight Then
						Local source:Byte = pixels[py * stride + (px Shr 3)]
						If source & ($80 Shr (px & 7)) Then packed :| Byte(1 Shl bit)
					End If
				Next
				dataBuffer[px - x0] = packed
			Next

			Local ramColumn:Int = columnOffset + x0
			commandBuffer[0] = Byte($b0 | (pageOffset + page))
			commandBuffer[1] = Byte($10 | (ramColumn Shr 4))
			commandBuffer[2] = Byte(ramColumn & $0f)
			If Not SendPageData(x1 - x0) Then Return DisplayErrorGeneric
		Next

		Return True
	End Method

	Private
	Method SendCommand:Int(command:Byte)
		GPIOPut(chipSelectPin, False)
		GPIOPut(dataCommandPin, False)
		Local written:Int = SPIWriteBlocking(controller, Varptr command, 1)
		GPIOPut(chipSelectPin, True)
		Return written = 1
	End Method

	Method SendCommands:Int(commands:Byte[])
		If Not commands Or commands.length = 0 Then Return False
		GPIOPut(chipSelectPin, False)
		GPIOPut(dataCommandPin, False)
		Local written:Int = SPIWriteBlocking(controller, Varptr commands[0], commands.length)
		GPIOPut(chipSelectPin, True)
		Return written = commands.length
	End Method

	Method SendPageData:Int(length:Int)
		If length <= 0 Or length > dataBuffer.length Then Return False
		GPIOPut(chipSelectPin, False)
		GPIOPut(dataCommandPin, False)
		If SPIWriteBlocking(controller, Varptr commandBuffer[0], 3) <> 3 Then
			GPIOPut(chipSelectPin, True)
			Return False
		End If
		GPIOPut(dataCommandPin, True)
		Local written:Int = SPIWriteBlocking(controller, Varptr dataBuffer[0], length)
		GPIOPut(chipSelectPin, True)
		Return written = length
	End Method
End Type
?
