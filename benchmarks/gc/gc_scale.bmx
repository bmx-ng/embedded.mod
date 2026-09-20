SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import "gc_benchmark.c"

Extern "C"
	Function BenchmarkMulticore:Int() = "bmx_embedded_benchmark_multicore"
End Extern

Const Samples:Int = 8

Type TScaleNode
	Field next:TScaleNode
	Field value:Int
End Type

Function BuildForward:TScaleNode(count:Int)
	Local head:TScaleNode = New TScaleNode
	Local cursor:TScaleNode = head
	For Local index:Int = 0 Until count
		cursor.value = index + 1
		If index < count - 1 Then
			cursor.next = New TScaleNode
			cursor = cursor.next
		End If
	Next
	Return head
End Function

Function BuildZigzag:TScaleNode(count:Int)
	Local nodes:TScaleNode[] = New TScaleNode[count]
	For Local index:Int = 0 Until count
		nodes[index] = New TScaleNode
		nodes[index].value = index + 1
	Next
	Local head:TScaleNode
	Local cursor:TScaleNode
	For Local position:Int = 0 Until count
		Local index:Int
		If position Mod 2 = 0 Then
			index = position / 2
		Else
			index = count - 1 - position / 2
		End If
		If cursor Then
			cursor.next = nodes[index]
		Else
			head = nodes[index]
		End If
		cursor = nodes[index]
	Next
	Return head
End Function

Function SumChain:Long(head:TScaleNode, count:Int)
	Local total:Long
	Local cursor:TScaleNode = head
	For Local index:Int = 0 Until count
		If Not cursor Then RuntimeError "GC scale chain is short"
		total :+ cursor.value
		cursor = cursor.next
	Next
	If cursor Then RuntimeError "GC scale chain is long"
	Return total
End Function

Function Measure(label:String, times:ULong[])
	For Local index:Int = 0 Until Samples
		Local started:ULong = MonotonicMicroseconds()
		CollectObjects()
		times[index] = MonotonicMicroseconds() - started
	Next
	ReachabilityAudit()
	If InvalidReferenceCount() <> 0 Or Not HeapIntegrityValid() Then ..
		RuntimeError "GC scale heap check failed"
End Function

Function PrintSamples(label:String, times:ULong[])
	For Local index:Int = 0 Until Samples
		Print "GC_SCALE,case=" + label + ",sample=" + index + ",us=" + times[index]
	Next
End Function

If BenchmarkMulticore() Then RuntimeError "GC scale benchmark requires single-core managed code"
SleepMicroseconds(3000000)

Local count:Int = Int(ArenaCapacity() / 128)
If count < 32 Then RuntimeError "GC scale heap is too small"
Local expected:Long = Long(count) * (count + 1) / 2
Local forwardTimes:ULong[] = New ULong[Samples]
Local zigzagTimes:ULong[] = New ULong[Samples]

Local graph:TScaleNode = BuildForward(count)
Measure("forward", forwardTimes)
If SumChain(graph, count) <> expected Then RuntimeError "GC scale forward graph failed"
graph = Null
CollectObjects()

graph = BuildZigzag(count)
Measure("zigzag", zigzagTimes)
If SumChain(graph, count) <> expected Then RuntimeError "GC scale zigzag graph failed"
graph = Null
CollectObjects()

Print "GC_SCALE,format=1,arena=" + ArenaCapacity() + ",nodes=" + count + ",checksum=" + (expected * 2)
PrintSamples("forward", forwardTimes)
PrintSamples("zigzag", zigzagTimes)
Print "GC_SCALE,checks=pass"
Print "GC_SCALE,done=1"

While True
	SleepMicroseconds(1000000)
Wend
