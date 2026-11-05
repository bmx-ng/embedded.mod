SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "embedded_gc_stage2_managed_allocator_device.c"

Extern "C"
    Function CheckManagedAllocator:Int() = "bmx_embedded_gc_stage2_managed_allocator_device_test"
End Extern

SleepMicroseconds(3000000)
Local failedStep:Int = CheckManagedAllocator()
While True
    If failedStep Then
        Print "GC_STAGE2_ALLOCATOR,failed_step=" + failedStep
    Else
        Print "GC_STAGE2_ALLOCATOR,format=1,objects=pass,arrays=pass,strings=pass,oom=pass,native_safe=pass,done=1"
    End If
    SleepMicroseconds(1000000)
Wend
