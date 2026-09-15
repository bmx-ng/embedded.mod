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
	Return "release assertion failure"
End Function

Function GenericAssert<T>(condition:Int)
	Assert condition, "generic release assertion failure"
End Function

Assert AssertionCondition(False), AssertionMessage()
GenericAssert<Int>(False)

If conditionChecks = 0 And messageChecks = 0 Then
	Print "Embedded release Assert elision passed"
Else
	RuntimeError "Embedded release Assert evaluated an operand"
End If
