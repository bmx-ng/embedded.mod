SuperStrict
Framework BRL.StandardIO
Import Embedded.System.Time

Extern "C"
    Function GCInitialize() = "bmx_embedded_gc_multicore_initialize"
    Function GCRegister:UInt() = "bmx_embedded_gc_multicore_register"
    Function CollectObjects:UInt() = "bmx_embedded_collect_objects"
    Function LiveObjects:UInt() = "bmx_embedded_object_live_count"
    Function HeapValid:UInt() = "bmx_embedded_heap_integrity_valid"
    Function CollectionCount:UInt() = "bmx_embedded_collection_count"
    Function ObjectFailures:UInt() = "bmx_embedded_object_failure_count"
    Function LastReclaimed:UInt() = "bmx_embedded_last_reclaimed_object_count"
    Function Reachable:UInt() = "bmx_embedded_reachable_object_count"
End Extern

Type TExceptionChild
    Method Explode:Int()
        Throw "boom"
    End Method
End Type

Type TExceptionHolder
    Field child:TExceptionChild
End Type

Type TExceptionResource Implements ICloseable
    Method Close()
        storedParent = Null
        CollectObjects()
        usingDelta = Int(LiveObjects()) - Int(testBaseline)
    End Method
End Type

Global storedParent:TExceptionHolder
Global testBaseline:UInt
Global usingDelta:Int = -1
Global sharedResource:TExceptionResource = New TExceptionResource
Global diagnosticBefore:UInt
Global diagnosticAfter:UInt
Global diagnosticFailures:UInt
Global diagnosticReclaimed:UInt
Global diagnosticReachable:UInt

Function NewHolder:TExceptionHolder()
    Local parent:TExceptionHolder = New TExceptionHolder
    parent.child = New TExceptionChild
    Return parent
End Function

Function CatchProbe:Int()
    CollectObjects()
    Local baseline:UInt = LiveObjects()
    Local parent:TExceptionHolder = NewHolder()
    Try
        Local value:Int = parent.child.Explode()
    Catch problem:String
        parent = Null
        diagnosticBefore = CollectionCount()
        CollectObjects()
        diagnosticAfter = CollectionCount()
        diagnosticFailures = ObjectFailures()
        diagnosticReclaimed = LastReclaimed()
        diagnosticReachable = Reachable()
        Return Int(LiveObjects()) - Int(baseline)
    End Try
    Return -1
End Function

Function FinallyProbe:Int()
    CollectObjects()
    Local baseline:UInt = LiveObjects()
    Local parent:TExceptionHolder = NewHolder()
    Local delta:Int = -1
    Try
        Try
            Local value:Int = parent.child.Explode()
        Finally
            parent = Null
            CollectObjects()
            delta = Int(LiveObjects()) - Int(baseline)
        End Try
    Catch problem:String
    End Try
    Return delta
End Function

Function UsingProbe:Int()
    CollectObjects()
    testBaseline = LiveObjects()
    usingDelta = -1
    storedParent = NewHolder()
    Try
        Using
            Local resource:TExceptionResource = sharedResource
        Do
            Local value:Int = storedParent.child.Explode()
        End Using
    Catch problem:String
    End Try
    Return usingDelta
End Function

GCInitialize()
Local slot:UInt = GCRegister()
Local catchDelta:Int = CatchProbe()
Local finallyDelta:Int = FinallyProbe()
Local resourceDelta:Int = UsingProbe()
Local valid:UInt = HeapValid()
While True
    Print "GC_EXCEPTION_TEMP,format=1,slot=" + slot + ",catch=" + catchDelta + ",finally=" + finallyDelta + ",using=" + resourceDelta + ",valid=" + valid + ",before=" + diagnosticBefore + ",after=" + diagnosticAfter + ",failures=" + diagnosticFailures + ",reclaimed=" + diagnosticReclaimed + ",reachable=" + diagnosticReachable
    SleepMicroseconds(1000000)
Wend
