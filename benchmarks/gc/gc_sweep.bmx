SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import "gc_benchmark.c"
Import "gc_sweep.c"
Extern "C"
    Function BenchmarkMulticore:Int() = "bmx_embedded_benchmark_multicore"
    Function Prepare:Int(kind:Int, count:Int) = "bmx_sweep_prepare"
    Function Check:Int(kind:Int, count:Int) = "bmx_sweep_check"
End Extern
Const Samples:Int = 12
If BenchmarkMulticore() Then RuntimeError "GC sweep benchmark requires single-core managed code"
SleepMicroseconds(3000000)
Local count:Int = Int(ArenaCapacity() / 256)
Local labels:String[] = ["all_live", "contiguous", "fragmented", "raw_survivors"]
Local times:ULong[] = New ULong[Samples * 4]
For Local kind:Int = 0 Until 4
    For Local sample:Int = 0 Until Samples
        If Not Prepare(kind, count) Then RuntimeError "GC sweep setup failed"
        Local started:ULong = MonotonicMicroseconds()
        CollectObjects()
        times[kind * Samples + sample] = MonotonicMicroseconds() - started
        If Not Check(kind, count) Then RuntimeError "GC sweep validation failed"
    Next
Next
Print "GC_SWEEP,format=1,mode=single,arena=" + ArenaCapacity() + ",nodes=" + count
For Local kind:Int = 0 Until 4
    For Local sample:Int = 0 Until Samples
        Print "GC_SWEEP,case=" + labels[kind] + ",sample=" + sample + ",us=" + times[kind * Samples + sample]
    Next
Next
Print "GC_SWEEP,checks=pass"
Print "GC_SWEEP,done=1"
While True
    SleepMicroseconds(1000000)
Wend
