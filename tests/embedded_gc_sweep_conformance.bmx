SuperStrict
Framework BRL.StandardIO
Import Embedded.Runtime.Memory
Import Embedded.System.Time
Import "embedded_gc_sweep_conformance.c"
Extern "C"
    Function CheckSweep:Int() = "bmx_embedded_gc_sweep_conformance"
End Extern
SleepMicroseconds(3000000)
Local failedLine:Int = CheckSweep()
If failedLine Then RuntimeError "GC sweep conformance failed at C line " + failedLine
Print "GC_CHECK,format=1,checks=pass"
Print "GC_CHECK,done=1"
While True
    SleepMicroseconds(1000000)
Wend
