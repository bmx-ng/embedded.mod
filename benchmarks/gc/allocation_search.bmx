SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import "gc_benchmark.c"
Import "allocation_search.c"
Extern "C"
    Function BenchmarkMulticore:Int() = "bmx_embedded_benchmark_multicore"
    Function Prepare:Int(kind:Int, count:Int) = "bmx_allocation_prepare"
    Function RunBatch:Int(kind:Int) = "bmx_allocation_run"
    Function Check:Int(kind:Int) = "bmx_allocation_check"
End Extern
Function Fail(message:String)
    Print "ALLOC_SEARCH,format=1,mode=single"
    Print "ALLOC_SEARCH,error=" + message
    Print "ALLOC_SEARCH,done=1"
    While True
        SleepMicroseconds(1000000)
    Wend
End Function
Const Samples:Int = 12
If BenchmarkMulticore() Then Fail "Allocation benchmark requires single-core managed code"
SleepMicroseconds(3000000)
Local count:Int = Int(ArenaCapacity() / 512)
Local labels:String[] = ["head", "middle", "tail", "split", "miss", "churn"]
Local times:ULong[] = New ULong[Samples * labels.Length]
For Local kind:Int = 0 Until labels.Length
    For Local sample:Int = 0 Until Samples
        If Not Prepare(kind, count) Then Fail "Allocation setup failed: " + labels[kind]
        Local started:ULong = MonotonicMicroseconds()
        Local succeeded:Int = RunBatch(kind)
        times[kind * Samples + sample] = MonotonicMicroseconds() - started
        Local checked:Int = Check(kind)
        If Not succeeded Or checked <> 1 Then Fail "Allocation check failed: " + labels[kind] + ",line=" + (-checked)
    Next
Next
Print "ALLOC_SEARCH,format=1,mode=single,arena=" + ArenaCapacity() + ",holes=" + count + ",batch=32,churn_steps=2048"
For Local kind:Int = 0 Until labels.Length
    For Local sample:Int = 0 Until Samples
        Print "ALLOC_SEARCH,case=" + labels[kind] + ",sample=" + sample + ",us=" + times[kind * Samples + sample]
    Next
Next
Print "ALLOC_SEARCH,checks=pass"
Print "ALLOC_SEARCH,done=1"
While True
    SleepMicroseconds(1000000)
Wend
