SuperStrict

Framework BRL.StandardIO

Global conditionChecks:Int
Global messageChecks:Int

Function AssertionCondition:Int(value:Int)
	conditionChecks :+ 1
	Return value
End Function

Function AssertionMessage:String()
	messageChecks :+ 1
	Return "lazy assertion failure"
End Function

Function GenericAssert<T>(condition:Int)
	Assert condition, "generic assertion failure"
End Function

Function CatchOrdinaryAssert:Int()
	Try
		Assert AssertionCondition(False), AssertionMessage()
	Catch failure:TRuntimeException
		Return failure.ToString() = "lazy assertion failure"
	End Try
	Return False
End Function

Function CatchGenericAssert:Int()
	Try
		GenericAssert<Int>(False)
	Catch failure:TRuntimeException
		Return failure.ToString() = "generic assertion failure"
	End Try
	Return False
End Function

Local caughtOrdinary:Int = CatchOrdinaryAssert()
Local caughtGeneric:Int = CatchGenericAssert()
Assert AssertionCondition(True), AssertionMessage()

If caughtOrdinary And caughtGeneric And conditionChecks = 2 And messageChecks = 1 Then
	Print "Embedded debug Assert conformance passed"
Else
	RuntimeError "Embedded debug Assert conformance failed"
End If
