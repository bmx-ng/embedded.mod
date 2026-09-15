SuperStrict

Import BRL.StandardIO
Import Embedded.Random

Local generator:TRandom = CreateRandom("Embedded")
Local bytes:Byte[32]
Local passed:Int = generator And generator.GetName() = "Embedded" And ..
	Not generator.CanSaveState() And Not generator.SaveState() And ..
	EmbeddedFillRandom(Null, 0) And Not EmbeddedFillRandom(Null, 1) And ..
	EmbeddedFillRandom(bytes, bytes.length)

Local anyNonzero:Int
For Local value:Byte = EachIn bytes
	If value Then anyNonzero = True
Next
passed :& anyNonzero

For Local index:Int = 0 Until 256
	Local floatValue:Float = generator.RndFloat()
	Local doubleValue:Double = generator.RndDouble()
	Local intValue:Int = generator.RandomInt(-19, 23)
	Local reverseInt:Int = generator.RandomInt(23, -19)
	Local longValue:Long = generator.RandomLong(-5000000000:Long, 7000000000:Long)
	Local uintValue:UInt = generator.RandomUInt(4000000000:UInt, 4000000100:UInt)
	Local ulongValue:ULong = generator.RandomULong(9000000000000000000:ULong, 9000000000000000100:ULong)
	passed :& floatValue >= 0.0 And floatValue < 1.0 And ..
		doubleValue >= 0.0 And doubleValue < 1.0 And ..
		intValue >= -19 And intValue <= 23 And ..
		reverseInt >= -19 And reverseInt <= 23 And ..
		longValue >= -5000000000:Long And longValue <= 7000000000:Long And ..
		uintValue >= 4000000000:UInt And uintValue <= 4000000100:UInt And ..
		ulongValue >= 9000000000000000000:ULong And ulongValue <= 9000000000000000100:ULong
Next

If passed Then
	Print "Embedded random conformance test passed"
Else
	Print "Embedded random conformance test failed"
End If
