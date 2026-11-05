SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import "../runtime.mod/native/embedded_gc_handshake.c"
?pico
Import "embedded_gc_handshake_pico.c"
?esp32
Import "embedded_gc_handshake_esp32.c"
?

Extern "C"
    Function CheckHandshake:Int() = "bmx_embedded_gc_handshake_device_test"
End Extern

SleepMicroseconds(3000000)
Local failedStep:Int = CheckHandshake()
If failedStep Then
    While True
        Print "GC_HANDSHAKE,failed_step=" + failedStep
        SleepMicroseconds(1000000)
    Wend
End If
While True
    Print "GC_HANDSHAKE,format=1,checks=pass,done=1"
    SleepMicroseconds(1000000)
Wend
