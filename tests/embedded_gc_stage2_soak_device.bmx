SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_stage2_worker_lifecycle_device.c"

Extern "C"
    Function CheckWorkerLifecycle:Int(cycles:UInt) = "bmx_embedded_gc_stage2_worker_lifecycle_device_test"
End Extern

SleepMicroseconds(3000000)
Local started:ULong = MonotonicMicroseconds()
Local failedStep:Int = CheckWorkerLifecycle(1000000)
Local elapsed:ULong = MonotonicMicroseconds() - started
While True
    If failedStep Then
        Print "GC_STAGE2_SOAK,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_SOAK,format=1,cycles=1000000,oom=pass,exception=pass,reclaim=pass,duration_us=" + elapsed + ",done=1"
    End If
    SleepMicroseconds(1000000)
Wend
