SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_stage2_events_device.c"

Extern "C"
    Function CheckEvents:Int() = "bmx_embedded_gc_stage2_events_device_test"
End Extern

SleepMicroseconds(3000000)
Local failedStep:Int = CheckEvents()
While True
    If failedStep Then
        Print "GC_STAGE2_EVENTS,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_EVENTS,format=1,events=100000,ordered=pass,collection=pass,dropped=0,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
