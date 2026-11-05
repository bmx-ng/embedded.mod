SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_stage2_stress_device.c"

Extern "C"
    Function CheckStress:Int() = "bmx_embedded_gc_stage2_stress_device_test"
End Extern

SleepMicroseconds(3000000)
Local started:ULong = MonotonicMicroseconds()
Local failedStep:Int = CheckStress()
Local elapsed:ULong = MonotonicMicroseconds() - started
While True
    If failedStep Then
        Print "GC_STAGE2_STRESS,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_STRESS,format=1,rounds=10000,concurrent=pass,cycles=pass,mutation=pass,oom=pass,reclaim=pass,duration_us=" + elapsed + ",done=1"
    End If
    SleepMicroseconds(1000000)
Wend
