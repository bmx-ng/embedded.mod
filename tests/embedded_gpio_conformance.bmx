SuperStrict

Framework BRL.StandardIO
Import Embedded.Hardware.GPIO

?pico
Const TestPin:UInt = 2
?esp32
Const TestPin:UInt = 4
?

Local checksPassed:Int = GPIOIsValid(TestPin) And GPIOIsOutputCapable(TestPin)
checksPassed :& GPIOIsPullCapable(TestPin)
checksPassed :& Not GPIOIsValid($ffffffff) And Not GPIOInit($ffffffff)
Local started:Int = MilliSecs()
Delay 1
UDelay 1
checksPassed :& MilliSecs() - started >= 0
checksPassed :& GPIOInit(TestPin)
checksPassed :& GPIOSetOutput(TestPin)
checksPassed :& GPIOGetDirection(TestPin) = GPIOOutput
checksPassed :& GPIOPut(TestPin, False)
checksPassed :& GPIOGetOutput(TestPin) = False
checksPassed :& GPIOGet(TestPin) = False
checksPassed :& GPIOPut(TestPin, True)
checksPassed :& GPIOGetOutput(TestPin) = True
checksPassed :& GPIOGet(TestPin) = True

checksPassed :& GPIOSetDriveStrength(TestPin, GPIODriveStrengthHigh)
checksPassed :& GPIOGetDriveStrength(TestPin) = GPIODriveStrengthHigh
checksPassed :& GPIOSetPulls(TestPin, True, False)
checksPassed :& GPIOIsPulledUp(TestPin) And Not GPIOIsPulledDown(TestPin)
checksPassed :& GPIOPullDown(TestPin)
checksPassed :& Not GPIOIsPulledUp(TestPin) And GPIOIsPulledDown(TestPin)
checksPassed :& GPIODisablePulls(TestPin)
checksPassed :& Not GPIOIsPulledUp(TestPin) And Not GPIOIsPulledDown(TestPin)
checksPassed :& GPIOSetInput(TestPin)
checksPassed :& GPIOGetDirection(TestPin) = GPIOInput

If checksPassed Then
	Print "Embedded GPIO conformance test passed"
Else
	RuntimeError "Embedded GPIO conformance test failed"
End If
