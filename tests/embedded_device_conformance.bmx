SuperStrict

Import BRL.StandardIO
Import Embedded.System.Device

Local identifier:String = UniqueDeviceID()
Local identifierBytes:Byte[] = UniqueDeviceIDBytes()
Local reason:Int = DeviceResetReason()
Local passed:Int = identifier.length = identifierBytes.length * 2 And identifier.length > 0
passed :& reason >= DeviceResetReasonUnknown And reason <= DeviceResetReasonCPULockup
passed :& DeviceResetReasonName(reason).length > 0

For Local character:Int = EachIn identifier
	passed :& (character >= Asc("0") And character <= Asc("9")) Or ..
		(character >= Asc("A") And character <= Asc("F"))
Next

If passed Then
	Print "Embedded device conformance test passed"
Else
	Print "Embedded device conformance test failed"
End If
