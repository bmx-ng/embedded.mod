SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_stage2_worker_lifecycle_device.c"

Extern "C"
    Function CheckWorkerLifecycle:Int() = "bmx_embedded_gc_stage2_worker_lifecycle_device_test"
End Extern

SleepMicroseconds(3000000)
Local failedStep:Int = CheckWorkerLifecycle()
While True
    If failedStep Then
        Print "GC_STAGE2_WORKER,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_WORKER,format=1,cycles=16,objects=pass,arrays=pass,strings=pass,oom=pass,exception=pass,reclaim=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
