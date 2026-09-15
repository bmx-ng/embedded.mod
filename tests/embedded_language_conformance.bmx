SuperStrict

Framework BRL.StandardIO
Import Embedded.Runtime.Memory

Interface ITaggedValue
	Method Tag:Int()
End Interface

Interface IOperationFactory
	Method Choose:Int(value:Int)(enabled:Int)
End Interface

Global finalizedValues:Int
Global finallyCount:Int

Function Increment:Int(value:Int)
	Return value + 1
End Function

Type TOperationBase
	Method Choose:Int(value:Int)(enabled:Int)
		If enabled Then Return Increment
		Return Null
	End Method
End Type

Type TOperationDerived Extends TOperationBase Implements IOperationFactory
	Method Choose:Int(value:Int)(enabled:Int) Override
		Return Super.Choose(enabled)
	End Method
End Type

Type TMessageBase
	Method SendMessage:Object(message:Object, source:Object) Override
		Return message
	End Method
End Type

Type TMessageDerived Extends TMessageBase
	Method SendMessage:Object(message:Object, source:Object) Override
		If source Then Return source
		Return Super.SendMessage(message, source)
	End Method
End Type

Type TMessageDefault
End Type

Type TGenericMessageReceiver<T>
	Method SendMessage:Object(message:Object, source:Object) Override
		Return message
	End Method
End Type

Type TEmbeddedValue
	Field label:String
	Field numbers:Int[]

	Method New(label:String, number:Int)
		Self.label = label
		numbers = [number, number + 1]
	End Method

	Method Score:Int()
		Return numbers[0] + numbers[1]
	End Method

	Method ToString:String() Override
		Return label
	End Method

	Method Compare:Int(other:Object) Override
		Return numbers[0] - TEmbeddedValue(other).numbers[0]
	End Method

	Method HashCode:UInt() Override
		Return UInt(numbers[0] * 17)
	End Method

	Method Equals:Int(other:Object) Override
		Return Self = other
	End Method

	Method Delete()
		finalizedValues :+ 1
	End Method
End Type

Type TTaggedValue Extends TEmbeddedValue Implements ITaggedValue
	Field linked:TEmbeddedValue

	Method New(label:String, number:Int, linked:TEmbeddedValue = Null)
		Super.New(label, number)
		Self.linked = linked
	End Method

	Method Tag:Int()
		Return Score() + 100
	End Method

	Method ToString:String() Override
		Return Super.ToString()
	End Method

	Method Compare:Int(other:Object) Override
		Return Super.Compare(other)
	End Method

	Method HashCode:UInt() Override
		Return Super.HashCode()
	End Method

	Method Equals:Int(other:Object) Override
		Return Super.Equals(other)
	End Method
End Type

Type TEmbeddedBox<T>
	Field value:T

	Method New(value:T)
		Self.value = value
	End Method

	Method Get:T()
		Return value
	End Method

	Method ToString:String() Override
		Return "embedded-box"
	End Method
End Type

Function AllocatePressure(count:Int)
	Local transient:TEmbeddedValue
	For Local index:Int = 0 Until count
		transient = New TEmbeddedValue("temporary-" + index, index)
	Next
	CollectObjects()
End Function

Function RaiseTagged(value:TTaggedValue)
	Throw value
End Function

Local checksPassed:Int = True
Local base:TEmbeddedValue = New TEmbeddedValue("base", 10)
Local tagged:TTaggedValue = New TTaggedValue("tagged", 20, base)
Local asObject:Object = tagged
Local asTagged:ITaggedValue = tagged
Local boxed:TEmbeddedBox<TTaggedValue> = New TEmbeddedBox<TTaggedValue>(tagged)
Local boxedObject:Object = boxed

checksPassed :& base.Score() = 21 And tagged.Score() = 41 And asTagged.Tag() = 141
checksPassed :& asObject.ToString() = "tagged" And String(asObject) = "tagged"
checksPassed :& asObject.Compare(tagged) = 0 And asObject.HashCode() = 340
checksPassed :& asObject.Equals(tagged) And Not asObject.Equals(base)
checksPassed :& boxed.Get() = tagged
checksPassed :& boxedObject.ToString() = "embedded-box"

Local operationConcrete:TOperationDerived = New TOperationDerived
Local operationBase:TOperationBase = operationConcrete
Local operationFactory:IOperationFactory = operationConcrete
Local operation:Int(value:Int) = operationBase.Choose(True)
checksPassed :& operation(40) = 41 And operationFactory.Choose(True)(41) = 42

Local messageReceiver:Object = New TMessageDerived
Local defaultReceiver:Object = New TMessageDefault
Local genericMessageReceiver:Object = New TGenericMessageReceiver<Int>
checksPassed :& messageReceiver.SendMessage(base, Null) = base
checksPassed :& messageReceiver.SendMessage(base, tagged) = tagged
checksPassed :& defaultReceiver.SendMessage(base, tagged) = Null
checksPassed :& genericMessageReceiver.SendMessage(tagged, Null) = tagged

Local values:TEmbeddedValue[] = [base, tagged]
Local extended:TEmbeddedValue[] = values + [New TEmbeddedValue("tail", 30)]
Local sliced:TEmbeddedValue[] = extended[1..3]
checksPassed :& extended.length = 3 And sliced.length = 2
checksPassed :& sliced[0] = tagged And sliced[1].Score() = 61

Local dynamicText:String = tagged.label + ":" + tagged.numbers[1]
checksPassed :& dynamicText = "tagged:21" And dynamicText.ToUpper() = "TAGGED:21"

Try
	RaiseTagged(tagged)
Catch caught:TTaggedValue
	checksPassed :& caught = tagged And caught.linked = base And caught.Tag() = 141
Catch other:TEmbeddedValue
	checksPassed = False
End Try

Try
	Throw dynamicText
Catch caughtText:String
	checksPassed :& caughtText = "tagged:21"
End Try

Try
	Throw tagged.numbers
Catch caughtNumbers:Int[]
	checksPassed :& caughtNumbers.length = 2 And caughtNumbers[0] = 20
End Try

Try
	Try
		RaiseTagged(tagged)
	Finally
		finallyCount :+ 1
		AllocatePressure(700)
	End Try
Catch caught:TEmbeddedValue
	checksPassed :& caught = tagged And caught.label = "tagged"
End Try

Local orphan:TEmbeddedValue = New TEmbeddedValue("orphan", 99)
orphan = Null
CollectObjects()
CollectObjects()
ReachabilityAudit()

checksPassed :& finallyCount = 1 And finalizedValues > 0
checksPassed :& HeapIntegrityValid() And InvalidReferenceCount() = 0
checksPassed :& ExceptionDepth() = 0 And ExceptionUnhandledCount() = 0

If checksPassed Then
	Print "Shared embedded language conformance passed"
Else
	RuntimeError "Shared embedded language conformance failed"
End If
