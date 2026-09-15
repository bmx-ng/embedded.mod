' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Interrupt-buffered UART streams shared by embedded targets.
End Rem
Module Embedded.IO.BufferedUART
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import BRL.Stream
Import BRL.System
Import Embedded.Hardware.UART
Import Embedded.Runtime.Events

Rem
bbdoc: Emitted when an asynchronous UART transmit queue has drained.
about: EventSource is the TBufferedUARTStream and EventMods contains its UART
controller. Call Flush when all bits must have physically left the UART.
End Rem
Global EVENT_UARTTXEMPTY:Int = AllocUserEventId("UARTTXEmpty")

Rem
bbdoc: Emitted when the UART reports framing, parity, break, or overrun errors.
about: EventData contains UARTError flags and EventMods contains the controller.
End Rem
Global EVENT_UARTERROR:Int = AllocUserEventId("UARTError")

Private

Extern "C"
	Function _UARTAsyncOpen:Int(controller:Int, rxCapacity:UInt, txCapacity:UInt, rxToken:UInt, txToken:UInt, errorToken:UInt) = "bmx_embedded_uart_async_open"
	Function _UARTAsyncClose:Int(controller:Int) = "bmx_embedded_uart_async_close"
	Function _UARTAsyncIsOpen:Int(controller:Int) = "bmx_embedded_uart_async_is_open"
	Function _UARTAsyncRead:Int(controller:Int, destination:Byte Ptr, capacity:Int) = "bmx_embedded_uart_async_read"
	Function _UARTAsyncWrite:Int(controller:Int, source:Byte Ptr, length:Int) = "bmx_embedded_uart_async_write"
	Function _UARTAsyncReadAvailable:UInt(controller:Int) = "bmx_embedded_uart_async_read_available"
	Function _UARTAsyncWriteAvailable:UInt(controller:Int) = "bmx_embedded_uart_async_write_available"
	Function _UARTAsyncRXDropped:UInt(controller:Int) = "bmx_embedded_uart_async_rx_dropped"
	Function _UARTAsyncTXIdle:Int(controller:Int) = "bmx_embedded_uart_async_tx_idle"
End Extern

Public

Rem
bbdoc: A non-seekable TStream backed by an asynchronous native UART driver.
about: Read and Write wait until at least one byte can be transferred. Available
and WriteAvailable are non-blocking. Native interrupt or driver-task code only
moves bytes and posts numeric events; managed event objects are created later.
The UART must already be initialized and its pins configured. Capacities must
be powers of two and are the requested native software-buffer capacities.
End Rem
Type TBufferedUARTStream Extends TStream
	Private
	Field controller:Int = -1
	Field rxToken:UInt
	Field txToken:UInt
	Field errorToken:UInt
	Field nativeOpen:Int

	Public
	Function Create:TBufferedUARTStream(controller:Int, rxCapacity:UInt = 256, ..
			txCapacity:UInt = 256)
		If Not UARTIsEnabled(controller) Or rxCapacity < 2 Or txCapacity < 2 Or ..
				(rxCapacity & (rxCapacity - 1)) Or (txCapacity & (txCapacity - 1)) Then Return Null
		Local stream:TBufferedUARTStream = New TBufferedUARTStream
		stream.controller = controller
		stream.rxToken = RegisterEmbeddedEventSource(stream, EVENT_STREAMAVAIL, True)
		stream.txToken = RegisterEmbeddedEventSource(stream, EVENT_UARTTXEMPTY, True)
		stream.errorToken = RegisterEmbeddedEventSource(stream, EVENT_UARTERROR, True)
		If stream.rxToken = 0 Or stream.txToken = 0 Or stream.errorToken = 0 Then
			stream.Close()
			Return Null
		End If
		stream.nativeOpen = _UARTAsyncOpen(controller, rxCapacity, txCapacity, ..
			stream.rxToken, stream.txToken, stream.errorToken)
		If Not stream.nativeOpen Then
			stream.Close()
			Return Null
		End If
		Return stream
	End Function

	Method Controller:Int()
		Return controller
	End Method

	Method IsOpen:Int()
		Return controller >= 0 And nativeOpen And _UARTAsyncIsOpen(controller)
	End Method

	Method Available:UInt()
		If controller < 0 Then Return 0
		Return _UARTAsyncReadAvailable(controller)
	End Method

	Method WriteAvailable:UInt()
		If controller < 0 Then Return 0
		Return _UARTAsyncWriteAvailable(controller)
	End Method

	Method DroppedBytes:UInt()
		If controller < 0 Then Return 0
		Return _UARTAsyncRXDropped(controller)
	End Method

	Method Eof:Int() Override
		Return Not IsOpen()
	End Method

	Method Read:Long(buffer:Byte Ptr, count:Long) Override
		If count <= 0 Then Return 0
		If buffer = Null Then Throw "Buffered UART read received a null buffer"
		While IsOpen()
			Local amount:Int = Int(Min(count, Long($7fffffff)))
			Local result:Int = _UARTAsyncRead(controller, buffer, amount)
			If result < 0 Then Throw "Buffered UART read failed"
			If result Then Return result
			WaitSystem()
		Wend
		Return 0
	End Method

	Method Write:Long(buffer:Byte Ptr, count:Long) Override
		If count <= 0 Then Return 0
		If buffer = Null Then Throw "Buffered UART write received a null buffer"
		While IsOpen()
			Local amount:Int = Int(Min(count, Long($7fffffff)))
			Local result:Int = _UARTAsyncWrite(controller, buffer, amount)
			If result < 0 Then Throw "Buffered UART write failed"
			If result Then Return result
			WaitSystem()
		Wend
		Return 0
	End Method

	Method Flush() Override
		While IsOpen() And Not _UARTAsyncTXIdle(controller)
			WaitSystem()
		Wend
	End Method

	Method Close() Override
		If controller >= 0 And nativeOpen And _UARTAsyncIsOpen(controller)
			Flush()
			_UARTAsyncClose(controller)
		End If
		nativeOpen = False
		If rxToken Then ReleaseEmbeddedEventSource(rxToken)
		If txToken Then ReleaseEmbeddedEventSource(txToken)
		If errorToken Then ReleaseEmbeddedEventSource(errorToken)
		rxToken = 0
		txToken = 0
		errorToken = 0
		controller = -1
	End Method
End Type

Rem
bbdoc: Opens an interrupt-buffered stream for an initialized UART controller.
End Rem
Function OpenBufferedUARTStream:TBufferedUARTStream(controller:Int, ..
		rxCapacity:UInt = 256, txCapacity:UInt = 256)
	Return TBufferedUARTStream.Create(controller, rxCapacity, txCapacity)
End Function
?
