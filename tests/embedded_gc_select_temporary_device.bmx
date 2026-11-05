SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time

Type TSelectChild
    Field value:Int
End Type

Type TSelectHolder
    Field child:TSelectChild
End Type

Function MakeHolder:TSelectHolder(value:Int)
    Local holder:TSelectHolder = New TSelectHolder
    holder.child = New TSelectChild
    holder.child.value = value
    Return holder
End Function

Function Choose:Int(selector:TSelectHolder, first:TSelectHolder, second:TSelectHolder)
    Local total:Int
    Select selector.child.value
        Case first.child.value, second.child.value
            While total < 2
                total :+ 1
            Wend
        Case 9
            While total < 3
                total :+ 1
            Wend
        Default
            total = 4
    End Select
    Return total
End Function

Local first:Int = Choose(MakeHolder(1), MakeHolder(1), MakeHolder(2))
Local second:Int = Choose(MakeHolder(1), MakeHolder(2), MakeHolder(1))
Local fallback:Int = Choose(MakeHolder(5), MakeHolder(1), MakeHolder(2))
While True
    Print "GC_SELECT,format=1,first=" + first + ",second=" + second + ",default=" + fallback
    SleepMicroseconds(1000000)
Wend
