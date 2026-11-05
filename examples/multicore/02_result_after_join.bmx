' A simple result handoff: the owner reads the value only after join.
SuperStrict

Framework BRL.StandardIO
Import Embedded.Runtime.Worker

Global workerResult:Int

Function Calculate()
    Local total:Int
    For Local number:Int = 1 To 1000
        total :+ number
    Next
    workerResult = total
End Function

If Not StartManagedWorker(Calculate) Then RuntimeError "Could not start worker"

' This work overlaps the worker's calculation. Do not read workerResult yet.
Local ownerResult:Int
For Local number:Int = 1 To 1000
    ownerResult :+ number * 2
Next

Local result:Int
Repeat
    result = JoinManagedWorker()
Until result <> 0
If result <> 1 Then RuntimeError "Worker failed"

Print "Worker result: " + workerResult
Print "Owner result: " + ownerResult
