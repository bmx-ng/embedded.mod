SuperStrict

Framework BRL.StandardIO
Import Embedded.System.Time
Import Embedded.Runtime.Memory
Import "gc_benchmark.c"

Extern "C"
	Function BenchmarkMulticore:Int() = "bmx_embedded_benchmark_multicore"
End Extern

Const Samples:Int = 12

Type TVariedNode
	Field next:TVariedNode
	Field children:TVariedNode[]
	Field values:Int[]
	Field label:String
	Field value:Int
End Type

Function CheckHeap()
	ReachabilityAudit()
	If Not HeapIntegrityValid() Or InvalidReferenceCount() <> 0 Then ..
		RuntimeError "Varied GC benchmark heap check failed"
End Function

Function Measure(label:String, times:ULong[])
	For Local index:Int = 0 Until times.Length
		Local started:ULong = MonotonicMicroseconds()
		CollectObjects()
		times[index] = MonotonicMicroseconds() - started
	Next
	CheckHeap()
End Function

Function PrintSamples(label:String, times:ULong[])
	For Local index:Int = 0 Until times.Length
		Print "GC_VARIED,case=" + label + ",sample=" + index + ",us=" + times[index]
	Next
End Function

Function BuildForward:TVariedNode(count:Int)
	Local head:TVariedNode = New TVariedNode
	Local cursor:TVariedNode = head
	For Local index:Int = 0 Until count
		cursor.value = index + 1
		If index < count - 1 Then
			cursor.next = New TVariedNode
			cursor = cursor.next
		End If
	Next
	Return head
End Function

Function ForwardSum:Int(head:TVariedNode)
	Local total:Int
	Local cursor:TVariedNode = head
	While cursor
		total :+ cursor.value
		cursor = cursor.next
	Wend
	Return total
End Function

Function BuildWide:TVariedNode(count:Int)
	Local root:TVariedNode = New TVariedNode
	Local shared:TVariedNode = New TVariedNode
	shared.value = 1000
	root.children = New TVariedNode[count]
	For Local index:Int = 0 Until count
		Local leaf:TVariedNode = New TVariedNode
		leaf.value = index + 1
		leaf.label = "leaf-" + index
		leaf.values = New Int[4]
		leaf.values[3] = index + 7
		leaf.children = [shared]
		root.children[index] = leaf
	Next
	Return root
End Function

Function WideSum:Int(root:TVariedNode)
	Local total:Int
	For Local index:Int = 0 Until root.children.Length
		Local leaf:TVariedNode = root.children[index]
		If leaf.children[0].value <> 1000 Or leaf.label <> "leaf-" + index Then ..
			RuntimeError "Varied GC benchmark wide graph failed"
		total :+ leaf.value + leaf.values[3]
	Next
	Return total
End Function

Function BuildCycle:TVariedNode(count:Int)
	Local head:TVariedNode = New TVariedNode
	Local cursor:TVariedNode = head
	For Local index:Int = 0 Until count
		cursor.value = index + 1
		cursor.label = "cycle-" + index
		If index < count - 1 Then
			cursor.next = New TVariedNode
			cursor = cursor.next
		End If
	Next
	cursor.next = head
	head.children = [cursor]
	Return head
End Function

Function CycleSum:Int(head:TVariedNode, count:Int)
	Local total:Int
	Local cursor:TVariedNode = head
	For Local index:Int = 0 Until count
		If cursor.label <> "cycle-" + index Then ..
			RuntimeError "Varied GC benchmark cycle failed"
		total :+ cursor.value
		cursor = cursor.next
	Next
	If cursor <> head Or head.children[0].next <> head Then ..
		RuntimeError "Varied GC benchmark cycle link failed"
	Return total
End Function

Function MakeGarbage(count:Int)
	Local head:TVariedNode
	For Local index:Int = 0 Until count
		Local node:TVariedNode = New TVariedNode
		node.next = head
		node.label = "garbage-" + index
		node.values = New Int[8]
		node.values[0] = index
		head = node
	Next
	If Not head Then RuntimeError "Varied GC benchmark allocation failed"
End Function

If BenchmarkMulticore() Then RuntimeError "Multi-core GC benchmark requires the managed task handshake"

' Give a USB serial monitor time to attach after flashing.
SleepMicroseconds(3000000)

Local baselineObjects:UInt = ObjectLiveCount()
Local emptyTimes:ULong[] = New ULong[Samples]
Local forwardTimes:ULong[] = New ULong[Samples]
Local wideTimes:ULong[] = New ULong[Samples]
Local cycleTimes:ULong[] = New ULong[Samples]
Local garbageTimes:ULong[] = New ULong[Samples]
Local checksum:Int

CollectObjects()
Measure("empty", emptyTimes)

Local graph:TVariedNode = BuildForward(64)
Measure("forward_chain", forwardTimes)
If ForwardSum(graph) <> 2080 Or ObjectLiveCount() < baselineObjects + 64 Then ..
	RuntimeError "Varied GC benchmark forward graph failed"
checksum :+ ForwardSum(graph)
graph = Null
CollectObjects()
If ObjectLiveCount() <> baselineObjects Then RuntimeError "Varied GC benchmark forward release failed"

graph = BuildWide(24)
Measure("wide_shared", wideTimes)
checksum :+ WideSum(graph)
graph = Null
CollectObjects()
If ObjectLiveCount() <> baselineObjects Then RuntimeError "Varied GC benchmark wide release failed"

graph = BuildCycle(20)
Measure("mixed_cycle", cycleTimes)
checksum :+ CycleSum(graph, 20)
graph = Null
CollectObjects()
If ObjectLiveCount() <> baselineObjects Then RuntimeError "Varied GC benchmark cycle release failed"

For Local index:Int = 0 Until Samples
	MakeGarbage(48)
	Local started:ULong = MonotonicMicroseconds()
	CollectObjects()
	garbageTimes[index] = MonotonicMicroseconds() - started
	If LastReclaimedObjectCount() < 48 Or ObjectLiveCount() <> baselineObjects Then ..
		RuntimeError "Varied GC benchmark garbage release failed"
Next
CheckHeap()

' Keep a live graph while allocation pressure forces automatic collections.
Local anchor:TVariedNode = BuildWide(8)
Local automaticBefore:UInt = AutomaticCollectionCount()
For Local index:Int = 0 Until 64
	MakeGarbage(48)
Next
If AutomaticCollectionCount() <= automaticBefore Or WideSum(anchor) <> 120 Then ..
	RuntimeError "Varied GC benchmark automatic collection failed"
checksum :+ WideSum(anchor)
anchor = Null
CollectObjects()
If ObjectLiveCount() <> baselineObjects Then RuntimeError "Varied GC benchmark pressure release failed"
CheckHeap()

Print "GC_VARIED,format=1,mode=single" + ..
	",arena_capacity=" + ArenaCapacity() + ",arena_high_water=" + ArenaHighWater() + ..
	",checksum=" + checksum + ",auto_collections=" + (AutomaticCollectionCount() - automaticBefore)
PrintSamples("empty", emptyTimes)
PrintSamples("forward_chain", forwardTimes)
PrintSamples("wide_shared", wideTimes)
PrintSamples("mixed_cycle", cycleTimes)
PrintSamples("reclaim_mixed", garbageTimes)
Print "GC_VARIED,checks=pass"
Print "GC_VARIED,done=1"

' Keep USB service active so the Pico can be reset for another run.
While True
	SleepMicroseconds(1000000)
Wend
