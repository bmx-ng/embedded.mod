SuperStrict

Framework BRL.EventQueue
Import Embedded.Hardware.UART
Import Embedded.IO.BufferedUART
Import BRL.StandardIO

?pico
Const TestController:Int = UARTController1
Const TestTXPin:UInt = 4
Const TestRXPin:UInt = 5
?esp32
Const TestController:Int = UARTController1
Const TestTXPin:UInt = 17
Const TestRXPin:UInt = 18
?

Local checksPassed:Int = UARTConfigurePins(TestController, TestTXPin, TestRXPin)
checksPassed :& UARTInit(TestController, 115200) > 0
Local stream:TBufferedUARTStream = OpenBufferedUARTStream(TestController, 64, 64)
checksPassed :& stream <> Null And stream.IsOpen()
If stream
	checksPassed :& stream.Available() = 0
	checksPassed :& stream.WriteAvailable() = 64
	checksPassed :& stream.DroppedBytes() = 0
	Local outgoing:Byte[1]
	outgoing[0] = Asc("U")
	checksPassed :& stream.Write(outgoing, 1) = 1
	stream.Flush()
	stream.Close()
	checksPassed :& Not stream.IsOpen()
End If
checksPassed :& UARTDeinit(TestController)

If checksPassed Then
	Print "Embedded buffered UART conformance test passed"
Else
	RuntimeError "Embedded buffered UART conformance test failed"
End If
