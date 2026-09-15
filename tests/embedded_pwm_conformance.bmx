SuperStrict

Import BRL.StandardIO
Import Embedded.Hardware.PWM

Local invalidPin:UInt = $ffffffff
Local passed:Int = Not PWMIsValidPin(invalidPin) And ..
	PWMInitPin(invalidPin, 1000) = 0 And Not PWMDeinitPin(invalidPin) And ..
	PWMSetPinFrequency(invalidPin, 2000) = 0 And ..
	Not PWMSetPinDuty(invalidPin, PWMDutyMaximum / 2) And ..
	Not PWMSetPinEnabled(invalidPin, True)

Local pin:UInt = invalidPin
For Local candidate:UInt = 0 Until 256
	If PWMIsValidPin(candidate) Then
		pin = candidate
		Exit
	End If
Next

passed :& pin <> invalidPin
If pin <> invalidPin Then
	Local achieved:UInt = PWMInitPin(pin, 1000, PWMDutyMaximum / 4)
	passed :& achieved > 0 And PWMGetPinFrequency(pin) = achieved
	passed :& PWMGetPinDuty(pin) = PWMDutyMaximum / 4
	passed :& PWMGetPinEnabled(pin)
	passed :& PWMSetPinDuty(pin, PWMDutyMaximum / 2)
	passed :& PWMGetPinDuty(pin) = PWMDutyMaximum / 2
	passed :& PWMSetPinPolarity(pin, True) And PWMGetPinPolarity(pin)
	passed :& PWMSetPinFrequency(pin, 2000) > 0
	passed :& PWMSetPinEnabled(pin, False) And Not PWMGetPinEnabled(pin)
	passed :& PWMSetPinEnabled(pin, True) And PWMGetPinEnabled(pin)
	passed :& PWMDeinitPin(pin)
	passed :& PWMGetPinFrequency(pin) = 0 And Not PWMGetPinEnabled(pin)
End If

If passed Then
	Print "Embedded PWM conformance test passed"
Else
	Print "Embedded PWM conformance test failed"
End If
