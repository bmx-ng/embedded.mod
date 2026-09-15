SuperStrict

Import BRL.StandardIO
Import Embedded.Hardware.ADC

Local invalidPin:UInt = $ffffffff
Local passed:Int = Not ADCIsValidPin(invalidPin) And ..
	Not ADCInitPin(invalidPin) And Not ADCDeinitPin(invalidPin) And ..
	ADCResolutionBitsForPin(invalidPin) = 0 And ADCMaximumValueForPin(invalidPin) = 0
Local raw:UInt
passed :& Not ADCReadRaw(invalidPin, raw)

Local pin:UInt = invalidPin
For Local candidate:UInt = 0 Until 256
	If ADCIsValidPin(candidate) Then
		pin = candidate
		Exit
	End If
Next

passed :& pin <> invalidPin
If pin <> invalidPin Then
	Local bits:UInt = ADCResolutionBitsForPin(pin)
	Local maximum:UInt = ADCMaximumValueForPin(pin)
	passed :& bits > 0 And bits < 32
	passed :& maximum = ((1:UInt Shl bits) - 1)
	passed :& ADCInitPin(pin)
	passed :& ADCReadRaw(pin, raw) And raw <= maximum
	passed :& ADCDeinitPin(pin)
	passed :& Not ADCReadRaw(pin, raw)
End If

If passed Then
	Print "Embedded ADC conformance test passed"
Else
	Print "Embedded ADC conformance test failed"
End If
