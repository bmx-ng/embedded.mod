SuperStrict

Framework BRL.StandardIO
Import Embedded.Runtime.Memory
Import "embedded_runtime_conformance.c"

Extern "C"
	Function TestOOMBegin:Int() = "bmx_embedded_test_oom_begin"
	Function TestOOMEnd() = "bmx_embedded_test_oom_end"
	Function TestObjectToString:String(value:Object) = "bmx_embedded_test_object_to_string"
End Extern

Type TDescribedObject
	Method ToString:String() Override
		Return "descriptor-ToString-hook"
	End Method
End Type

Type TConstructorBase
	Field label:String
	Field values:Int[]

	Method New(mode:Int)
		label = "base-" + mode
		values = [mode, mode + 1]
		If mode = 1 Then Throw "base-constructor-failed"
	End Method
End Type

Type TConstructorDerived Extends TConstructorBase
	Field derivedLabel:String

	Method New(mode:Int)
		Super.New(mode)
		derivedLabel = "derived-" + mode
		If mode = 2 Then Throw "derived-constructor-failed"
	End Method
End Type

Type TOOMConstructor
	Field values:Int[]

	Method New()
		If Not TestOOMBegin() Then Throw "constructor-oom-setup-failed"
		values = New Int[64]
	End Method
End Type

Local rootFramesBefore:UInt = RootFrameCount()
Local rootSlotsBefore:UInt = RootSlotCount()
Local objectsBefore:UInt = ObjectLiveCount()
Local arraysBefore:UInt = ArrayLiveCount()
Local stringsBefore:UInt = StringLiveCount()
Local throwsBefore:UInt = ExceptionThrowCount()
Local catchesBefore:UInt = ExceptionCatchCount()
Local checksPassed:Int = True

Local described:TDescribedObject = New TDescribedObject
checksPassed :& TestObjectToString(described) = "descriptor-ToString-hook"
described = Null

Local failedBase:TConstructorDerived
Try
	failedBase = New TConstructorDerived(1)
Catch message:String
	checksPassed :& message = "base-constructor-failed"
End Try
checksPassed :& Not failedBase

Local failedDerived:TConstructorDerived
Try
	failedDerived = New TConstructorDerived(2)
Catch message:String
	checksPassed :& message = "derived-constructor-failed"
End Try
checksPassed :& Not failedDerived

Local failedOOM:TOOMConstructor
Try
	failedOOM = New TOOMConstructor
Catch message:String
	checksPassed :& message = "BlitzMax Array allocation failed"
End Try
TestOOMEnd()
checksPassed :& Not failedOOM

CollectObjects()
CollectObjects()
ReachabilityAudit()
checksPassed :& ObjectLiveCount() = objectsBefore And ArrayLiveCount() = arraysBefore And ..
	StringLiveCount() = stringsBefore And RootFrameCount() = rootFramesBefore And ..
	RootSlotCount() = rootSlotsBefore And ExceptionDepth() = 0 And ..
	ExceptionThrowCount() = throwsBefore + 3 And ExceptionCatchCount() = catchesBefore + 3 And ..
	ExceptionUnhandledCount() = 0 And FinalizerPendingCount() = 0 And ..
	InvalidReferenceCount() = 0 And HeapIntegrityValid()

Local recovered:TConstructorDerived = New TConstructorDerived(3)
checksPassed :& recovered.label = "base-3" And recovered.values.Length = 2 And ..
	recovered.values[1] = 4 And recovered.derivedLabel = "derived-3"

If checksPassed Then
	Print "Embedded runtime conformance test passed"
Else
	RuntimeError "Embedded runtime conformance test failed"
End If
