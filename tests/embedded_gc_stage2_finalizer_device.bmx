SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_stage2_finalizer_device.c"

Extern "C"
    Function CheckFinalizers:Int() = "bmx_embedded_gc_stage2_finalizer_device_test"
End Extern

SleepMicroseconds(3000000)
Local failedStep:Int = CheckFinalizers()
While True
    If failedStep Then
        Print "GC_STAGE2_FINALIZER,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_FINALIZER,format=1,allocation=pass,finalizers=pass,reclaim=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
