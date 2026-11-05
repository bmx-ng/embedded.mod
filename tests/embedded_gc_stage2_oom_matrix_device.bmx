SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_stage2_oom_matrix_device.c"

Extern "C"
    Function CheckOOMMatrix:Int() = "bmx_embedded_gc_stage2_oom_matrix_device_test"
End Extern

SleepMicroseconds(3000000)
Local failedStep:Int = CheckOOMMatrix()
While True
    If failedStep Then
        Print "GC_STAGE2_OOM_MATRIX,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_OOM_MATRIX,format=1,fragmented=pass,object=pass,array=pass,string=pass,arena=pass,recovery=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
