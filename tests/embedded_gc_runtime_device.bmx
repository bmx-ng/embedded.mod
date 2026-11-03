SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_runtime_device.c"

Extern "C"
    Function CheckRuntimeGC:Int() = "bmx_embedded_gc_runtime_device_test"
End Extern

SleepMicroseconds(3000000)
Local failedStep:Int = CheckRuntimeGC()
If failedStep Then
    While True
        Print "GC_RUNTIME,failed_step=" + failedStep
        SleepMicroseconds(1000000)
    Wend
End If
While True
    Print "GC_RUNTIME,format=1,roots=pass,timeout=pass,done=1"
    SleepMicroseconds(1000000)
Wend
