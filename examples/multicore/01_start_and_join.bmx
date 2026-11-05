' Run one managed job on the second core while the owner keeps working.
SuperStrict

Framework BRL.StandardIO
Import Embedded.Runtime.Worker
Import Embedded.System.Time

Function BackgroundJob()
    Local message:String = "Hello from the worker"
    If message.Length = 0 Then Throw "worker failed"
    SleepMilliseconds(500)
End Function

If Not StartManagedWorker(BackgroundJob) Then RuntimeError "Could not start worker"

For Local tick:Int = 1 To 5
    Print "Owner is still running: " + tick
    SleepMilliseconds(100)
Next

Local result:Int
Repeat
    result = JoinManagedWorker()
Until result <> 0
If result <> 1 Then RuntimeError "Worker failed"
Print "Both tasks finished"
