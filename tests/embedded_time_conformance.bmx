SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time

Local startedMicroseconds:ULong = MonotonicMicroseconds()
SleepMicroseconds(2000)
Local afterMicroseconds:ULong = MonotonicMicroseconds()

Local startedMilliseconds:ULong = MonotonicMilliseconds()
SleepMilliseconds(2)
Local afterMilliseconds:ULong = MonotonicMilliseconds()

Local checksPassed:Int = afterMicroseconds >= startedMicroseconds + 2000:ULong
checksPassed :& afterMilliseconds >= startedMilliseconds + 2:ULong
checksPassed :& MonotonicMicroseconds() >= afterMicroseconds
checksPassed :& MonotonicMilliseconds() >= afterMilliseconds

If checksPassed Then
	Print "Embedded time conformance test passed"
Else
	RuntimeError "Embedded time conformance test failed"
End If
