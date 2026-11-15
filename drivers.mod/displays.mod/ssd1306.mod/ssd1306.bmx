' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: SSD1306-compatible monochrome OLED displays over portable I2C.
about: The driver accepts the row-major Mono1 format from
Embedded.Drivers.Display and converts it to the controller's vertical page
layout during synchronous presentation. The I2C controller must already be
configured and initialized by the application.
End Rem
Module Embedded.Drivers.Displays.SSD1306
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Drivers.Display
Import Embedded.Hardware.I2C

Rem
bbdoc: The common seven-bit I2C address used by SSD1306 display modules.
End Rem
Const SSD1306DefaultAddress:UInt = $3c

Rem
bbdoc: An I2C SSD1306-compatible monochrome display.
End Rem
Type TSSD1306Display Extends TDisplay
	Private
	Field controller:Int
	Field address:UInt
	Field displayWidth:Int
	Field displayHeight:Int
	Field columnOffset:Int
	Field pageOffset:Int
	Field contrast:Byte
	Field precharge:Byte
	Field vcomh:Byte
	Field comPins:Byte
	Field internalIRef:Int
	Field initialized:Int
	Field commandBuffer:Byte[]
	Field dataBuffer:Byte[]

	Public
	Rem
	bbdoc: Creates a general SSD1306 display description.
	param: The initialized Embedded.Hardware.I2C controller index.
	param: The panel's seven-bit I2C address.
	param: The visible width in pixels.
	param: The visible height in pixels.
	param: The visible raster's first column in the controller's display RAM.
	param: The visible raster's first eight-pixel page in display RAM.
	param: The clockwise orientation used as logical rotation zero.
	returns: A display description, or Null when its dimensions, offsets, address, or orientation are invalid.
	about: This does not configure or initialize the I2C controller. Width may be
	up to 128 pixels and height up to 64 pixels.
	End Rem
	Function Create:TSSD1306Display(controller:Int, address:UInt, width:Int, ..
		height:Int, columnOffset:Int = 0, pageOffset:Int = 0, orientation:Int = DisplayOrientation0)
		If controller < 0 Or address > $7f Or width <= 0 Or width > 128 Or ..
				height <= 0 Or height > 64 Or columnOffset < 0 Or ..
				columnOffset + width > 128 Or pageOffset < 0 Or ..
				pageOffset + ((height + 7) / 8) > 8 Then
			Return Null
		End If

		Local display:TSSD1306Display = New TSSD1306Display
		display.controller = controller
		display.address = address
		display.displayWidth = width
		display.displayHeight = height
		display.columnOffset = columnOffset
		display.pageOffset = pageOffset
		If Not display.SetOrientation(orientation) Then Return Null
		display.contrast = $7f
		display.precharge = $f1
		display.vcomh = $40
		display.comPins = $02
		If height > 32 Then
			display.comPins = $12
		End If

		display.commandBuffer = New Byte[32]
		display.dataBuffer = New Byte[width + 1]
		Return display
	End Function

	Rem
	bbdoc: Creates the common EastRising-compatible 72x40 SSD1306 configuration.
	param: The initialized Embedded.Hardware.I2C controller index.
	param: The panel's seven-bit I2C address.
	param: The clockwise orientation used as logical rotation zero.
	returns: A 72x40 display description, or Null when its address or orientation is invalid.
	about: This preset uses a 28-column RAM offset and the panel-specific IREF,
	contrast, precharge, and VCOMH settings used by 0.42-inch modules.
	End Rem
	Function Create72x40:TSSD1306Display(controller:Int, ..
		address:UInt = SSD1306DefaultAddress, orientation:Int = DisplayOrientation0)
		Local display:TSSD1306Display = Create(controller, address, 72, 40, 28, 0, orientation)
		If Not display Then
			Return Null
		End If

		display.internalIRef = True
		display.contrast = $af
		display.precharge = $22
		display.vcomh = $20
		display.comPins = $12
		Return display
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
	bbdoc: Initializes the panel and enables its output.
	returns: True when every I2C controller command succeeds.
	about: The application must configure and initialize the selected I2C
	controller and its data and clock pins before calling this method.
	End Rem
	Method Initialize:Int()
		Local first:Byte[] = [Byte($ae), Byte($d5), Byte($80), ..
			Byte($a8), Byte(displayHeight - 1), Byte($d3), Byte(0)]
		If Not SendCommands(first) Then
			Return False
		End If

		If internalIRef And Not SendPair($ad, $30) Then
			Return False
		End If

		Local second:Byte[] = [Byte($8d), Byte($14), Byte($40), Byte($a6), ..
			Byte($a4), Byte($20), Byte(0), Byte($a1), Byte($c8), ..
			Byte($da), comPins, Byte($81), contrast, Byte($d9), precharge, ..
			Byte($db), vcomh, Byte($2e)]
		If Not SendCommands(second) Then
			Return False
		End If

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
		If Not initialized Then
			Return False
		End If

		If enabled Then
			Return SendCommand($af)
		End If

		Return SendCommand($ae)
	End Method

	Rem
	bbdoc: Changes the SSD1306 segment-current contrast setting.
	param: The controller contrast value from 0 through 255.
	returns: True when the initialized controller accepts the command.
	End Rem
	Method SetContrast:Int(value:Byte)
		If Not initialized Then
			Return False
		End If

		contrast = value
		Return SendPair($81, value)
	End Method

	Rem
	bbdoc: Selects normal or inverted monochrome output.
	param: True to exchange lit and unlit pixels, or False for normal output.
	returns: True when the initialized controller accepts the command.
	End Rem
	Method SetInverted:Int(inverted:Int)
		If Not initialized Then
			Return False
		End If

		If inverted Then
			Return SendCommand($a7)
		End If

		Return SendCommand($a6)
	End Method

	Rem
	bbdoc: Reverses both scan axes to turn the physical panel upside down.
	param: True for flipped scanning, or False for the preset's normal scanning.
	returns: True when the initialized controller accepts both commands.
	about: This is a controller scan setting independent of the logical display
	orientation used by Graphics2D.
	End Rem
	Method SetFlipped:Int(flipped:Int)
		If Not initialized Then
			Return False
		End If

		If flipped Then
			Local commands:Byte[] = [Byte($a0), Byte($c0)]
			Return SendCommands(commands)
		End If

		Local commands:Byte[] = [Byte($a1), Byte($c8)]
		Return SendCommands(commands)
	End Method

	Rem
	bbdoc: Synchronously transfers a clipped Mono1 raster region over I2C.
	param: A pointer to the first byte of the complete row-major raster.
	param: The number of bytes between adjacent raster rows.
	param: The raster pixel format, which must be DisplayPixelFormatMono1.
	param: The requested physical left edge.
	param: The requested physical top edge.
	param: The requested region width in pixels.
	param: The requested region height in pixels.
	returns: True on success, or a DisplayError value on failure.
	about: The shared row-major, most-significant-bit-first Mono1 raster is
	converted during transfer to the SSD1306's vertical eight-pixel page layout.
	The requested rectangle is clipped to the visible panel and expanded to the
	controller pages intersecting its vertical extent.
	End Rem
	Method PresentPixels:Int(pixels:Byte Ptr, stride:Int, format:Int, ..
			x:Int, y:Int, width:Int, height:Int) Override
		If Not initialized Or pixels = Null Then
			Return DisplayErrorInvalidArgument
		End If

		If format <> DisplayPixelFormatMono1 Then
			Return DisplayErrorUnsupportedFormat
		End If

		If stride < DisplayMinimumStride(displayWidth, format) Or width <= 0 Or ..
				height <= 0 Then
			Return DisplayErrorInvalidArgument
		End If

		Local x0:Int = x
		Local y0:Int = y
		Local x1:Int = x + width
		Local y1:Int = y + height
		If x0 < 0 Then
			x0 = 0
		End If

		If y0 < 0 Then
			y0 = 0
		End If

		If x1 > displayWidth Then
			x1 = displayWidth
		End If

		If y1 > displayHeight Then
			y1 = displayHeight
		End If

		If x0 >= x1 Or y0 >= y1 Then
			Return DisplayErrorInvalidArgument
		End If

		Local firstPage:Int = y0 Shr 3
		Local lastPage:Int = (y1 - 1) Shr 3
		For Local page:Int = firstPage To lastPage
			Local ramColumn:Int = columnOffset + x0
			commandBuffer[0] = 0
			commandBuffer[1] = Byte($b0 | (pageOffset + page))
			commandBuffer[2] = Byte($10 | (ramColumn Shr 4))
			commandBuffer[3] = Byte(ramColumn & $0f)
			If I2CWriteBlocking(controller, address, Varptr commandBuffer[0], 4) <> 4 Then
				Return DisplayErrorGeneric
			End If

			dataBuffer[0] = $40
			For Local px:Int = x0 Until x1
				Local packed:Byte
				For Local bit:Int = 0 Until 8
					Local py:Int = page * 8 + bit
					If py < displayHeight Then
						Local source:Byte = pixels[py * stride + (px Shr 3)]
						If source & ($80 Shr (px & 7)) Then
							packed :| Byte(1 Shl bit)
						End If
					End If
				Next

				dataBuffer[px - x0 + 1] = packed
			Next

			Local transferLength:Int = x1 - x0 + 1
			If I2CWriteBlocking(controller, address, Varptr dataBuffer[0], transferLength) <> transferLength Then
				Return DisplayErrorGeneric
			End If
		Next

		Return True
	End Method

	Private
	Method SendCommand:Int(command:Byte)
		commandBuffer[0] = 0
		commandBuffer[1] = command
		Return I2CWriteBlocking(controller, address, Varptr commandBuffer[0], 2) = 2
	End Method

	Method SendPair:Int(command:Byte, argument:Byte)
		commandBuffer[0] = 0
		commandBuffer[1] = command
		commandBuffer[2] = argument
		Return I2CWriteBlocking(controller, address, Varptr commandBuffer[0], 3) = 3
	End Method

	Method SendCommands:Int(commands:Byte[])
		If Not commands Or commands.length = 0 Or commands.length + 1 > commandBuffer.length Then
			Return False
		End If

		commandBuffer[0] = 0
		For Local index:Int = 0 Until commands.length
			commandBuffer[index + 1] = commands[index]
		Next

		Local length:Int = commands.length + 1
		Return I2CWriteBlocking(controller, address, Varptr commandBuffer[0], length) = length
	End Method
End Type
?
