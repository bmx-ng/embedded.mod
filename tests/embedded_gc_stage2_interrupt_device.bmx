SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_stage2_interrupt_device.c"

Extern "C"
    Function CheckInterrupts:Int() = "bmx_embedded_gc_stage2_interrupt_device_test"
End Extern

SleepMicroseconds(3000000)
Local failedStep:Int = CheckInterrupts()
While True
    If failedStep Then
        Print "GC_STAGE2_INTERRUPTS,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_INTERRUPTS,format=1,interrupts=1000,ordered=pass,collection=pass,dropped=0,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
