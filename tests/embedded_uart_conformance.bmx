SuperStrict

Framework BRL.StandardIO
Import Embedded.Hardware.UART

?pico
Const TestController:Int = UARTController1
Const TestTXPin:UInt = 4
Const TestRXPin:UInt = 5
?esp32
Const TestController:Int = UARTController1
Const TestTXPin:UInt = 17
Const TestRXPin:UInt = 18
?

Local checksPassed:Int = UARTControllerCount() >= 2
Local defaultController:Int = UARTDefaultController()
checksPassed :& (defaultController = UARTUnavailableController And UARTDefaultBaudrate() = 0) Or ..
	(defaultController >= 0 And defaultController < UARTControllerCount() And UARTDefaultBaudrate() > 0)
checksPassed :& Not UARTConfigurePins(UARTControllerCount(), TestTXPin, TestRXPin)
checksPassed :& UARTConfigurePins(TestController, TestTXPin, TestRXPin)

Local actualRate:UInt = UARTInit(TestController, 115200)
checksPassed :& actualRate >= 114000 And actualRate <= 116000
checksPassed :& UARTIsEnabled(TestController) And UARTIsWritable(TestController)
actualRate = UARTSetBaudrate(TestController, 230400)
checksPassed :& actualRate >= 228000 And actualRate <= 233000
checksPassed :& UARTSetFormat(TestController, 7, 2, UARTParityEven)
checksPassed :& UARTSetFormat(TestController, 8, 1, UARTParityNone)
checksPassed :& Not UARTSetFormat(TestController, 9, 1, UARTParityNone)
checksPassed :& UARTSetFlowControl(TestController, False, False)
checksPassed :& UARTSetTranslateCRLF(TestController, False)

Local outgoing:Byte[1]
outgoing[0] = Asc("U")
checksPassed :& UARTWriteBlocking(TestController, outgoing, outgoing.length) = outgoing.length
checksPassed :& UARTTXWaitBlocking(TestController)
checksPassed :& UARTSetBreak(TestController, True)
Delay 1
checksPassed :& UARTSetBreak(TestController, False)

Local incoming:Byte[1]
checksPassed :& UARTReadTimeout(TestController, incoming, incoming.length, 1000) = 0
checksPassed :& UARTReadAvailable(TestController, incoming, incoming.length) = 0
checksPassed :& Not UARTIsReadable(TestController)
checksPassed :& Not UARTIsReadableWithin(TestController, 100)
checksPassed :& UARTGetErrors(TestController) = 0
checksPassed :& UARTClearErrors(TestController)
checksPassed :& UARTWriteBlocking(UARTControllerCount(), outgoing, 1) = UARTErrorInvalidArgument
checksPassed :& UARTDeinit(TestController)
checksPassed :& Not UARTIsEnabled(TestController) And Not UARTDeinit(TestController)
checksPassed :& UARTWriteBlocking(TestController, outgoing, 1) = UARTErrorInvalidArgument
checksPassed :& Not UARTSetFormat(TestController, 8, 1, UARTParityNone)
checksPassed :& Not UARTClearErrors(TestController)

If checksPassed Then
	Print "Embedded UART conformance test passed"
Else
	RuntimeError "Embedded UART conformance test failed"
End If
