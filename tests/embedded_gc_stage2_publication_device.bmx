SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_stage2_publication_device.c"

Extern "C"
    Function CheckPublication:Int() = "bmx_embedded_gc_stage2_publication_device_test"
End Extern

SleepMicroseconds(3000000)
Local failedStep:Int = CheckPublication()
While True
    If failedStep Then
        Print "GC_STAGE2_PUBLICATION,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_PUBLICATION,format=1,objects=pass,arrays=pass,strings=pass,cycle=pass,mutation=pass,reclaim=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
