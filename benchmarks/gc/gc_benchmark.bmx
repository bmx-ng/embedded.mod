SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import "gc_benchmark.c"

Extern "C"
	Function BenchmarkMulticore:Int() = "bmx_embedded_benchmark_multicore"
End Extern

Const Samples:Int = 12
Const LiveNodes:Int = 96
Const GarbageNodes:Int = 32
Const MutatorRounds:Int = 120000

Type TGCNode
	Field next:TGCNode
	Field value:UInt
End Type

Function BuildBackwardChain:TGCNode(count:Int)
	Local head:TGCNode
	For Local index:Int = 0 Until count
		Local node:TGCNode = New TGCNode
		node.value = UInt(index + 1)
		node.next = head
		head = node
	Next
	Return head
End Function

Function MakeGarbage(count:Int)
	Local discarded:TGCNode = BuildBackwardChain(count)
	If Not discarded Then RuntimeError "Benchmark allocation failed"
End Function

Function Mutate:UInt(head:TGCNode, rounds:Int)
	Local checksum:UInt
	For Local round:Int = 0 Until rounds
		Local node:TGCNode = head
		For Local index:Int = 0 Until LiveNodes
			node.value :+ 1
			checksum :+ node.value
			node = node.next
		Next
	Next
	Return checksum
End Function

Function PrintSamples(label:String, times:ULong[])
	For Local index:Int = 0 Until times.Length
		Print "GC_BENCH,case=" + label + ",sample=" + index + ",us=" + times[index]
	Next
End Function

If BenchmarkMulticore() Then RuntimeError "Multi-core GC benchmark requires the managed task handshake"

' Allow the USB serial monitor to reconnect after a firmware upload.
SleepMicroseconds(3000000)

Local head:TGCNode = BuildBackwardChain(LiveNodes)
Local liveTimes:ULong[] = New ULong[Samples]
Local garbageTimes:ULong[] = New ULong[Samples]
Local checksum:UInt

' Warm up code, timer and arena before measuring.
checksum = Mutate(head, 1)
CollectObjects()

Local started:ULong = MonotonicMicroseconds()
checksum :+ Mutate(head, MutatorRounds)
Local mutatorUs:ULong = MonotonicMicroseconds() - started

For Local index:Int = 0 Until Samples
	started = MonotonicMicroseconds()
	CollectObjects()
	liveTimes[index] = MonotonicMicroseconds() - started
Next

For Local index:Int = 0 Until Samples
	MakeGarbage(GarbageNodes)
	started = MonotonicMicroseconds()
	CollectObjects()
	garbageTimes[index] = MonotonicMicroseconds() - started
Next

If Not HeapIntegrityValid() Or InvalidReferenceCount() <> 0 Or ..
	ObjectLiveCount() < LiveNodes Then RuntimeError "GC benchmark heap check failed"

Print "GC_BENCH,format=1,mode=single" + ..
	",arena_capacity=" + ArenaCapacity() + ",arena_high_water=" + ArenaHighWater()
Print "GC_BENCH,case=mutator,rounds=" + MutatorRounds + ",us=" + mutatorUs + ",checksum=" + checksum
PrintSamples("live_backward_chain", liveTimes)
PrintSamples("reclaim_garbage", garbageTimes)
Print "GC_BENCH,done=1"

' Keep USB service active so the board can be reset for the next run.
While True
	SleepMicroseconds(1000000)
Wend
