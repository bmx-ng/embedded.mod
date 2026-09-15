SuperStrict

Import BRL.StandardIO
Import Embedded.Text.Unicode

Const UMLAUT_UPPER:String = "ÄÖÜABC"
Const UMLAUT_LOWER:String = "äöüabc"
Const CYRILLIC_UPPER:String = "БУДИНОК"
Const CYRILLIC_LOWER:String = "будинок"

Local passed:Int = UMLAUT_UPPER.ToLower() = UMLAUT_LOWER
passed :& UMLAUT_LOWER.ToUpper() = UMLAUT_UPPER
passed :& CYRILLIC_UPPER.ToLower() = CYRILLIC_LOWER
passed :& CYRILLIC_LOWER.ToUpper() = CYRILLIC_UPPER
passed :& UMLAUT_UPPER.Equals(UMLAUT_LOWER, False)
passed :& CYRILLIC_UPPER.HashCode(False) = CYRILLIC_LOWER.HashCode(False)

If passed Then
	Print "Embedded Unicode conformance test passed"
Else
	Print "Embedded Unicode conformance test failed"
End If
