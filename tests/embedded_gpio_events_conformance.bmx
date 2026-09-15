SuperStrict

Framework BRL.EventQueue
Import Embedded.Hardware.GPIOEvents
Import BRL.StandardIO

?pico
Const TestPin:UInt = 2
?esp32
Const TestPin:UInt = 4
?

Local checksPassed:Int = GPIOInit(TestPin)
checksPassed :& TGPIOIRQSource.Create(TestPin, 0) = Null
Local source:TGPIOIRQSource = TGPIOIRQSource.Create(TestPin, GPIOIRQEdgeRise | GPIOIRQEdgeFall)
checksPassed :& source <> Null And source.IsOpen()
If source
	checksPassed :& source.Pin() = TestPin
	checksPassed :& source.EventMask() = (GPIOIRQEdgeRise | GPIOIRQEdgeFall)
	checksPassed :& GPIOPendingIRQEvents(TestPin) = 0
	checksPassed :& GPIOTakeIRQEvents(TestPin) = 0
	source.Close()
	checksPassed :& Not source.IsOpen()
End If

If checksPassed Then
	Print "Embedded GPIO events conformance test passed"
Else
	RuntimeError "Embedded GPIO events conformance test failed"
End If
