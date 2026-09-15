SuperStrict

Import BRL.StandardIO
Import Embedded.Hardware.Watchdog

Local maximum:UInt = WatchdogMaximumDelayMilliseconds()
Local passed:Int = maximum > 0 And Not WatchdogEnable(0)
If maximum < $ffffffff Then passed :& Not WatchdogEnable(maximum + 1)
passed :& Not WatchdogIsEnabled()
passed :& WatchdogEnable(250)
passed :& WatchdogIsEnabled()
passed :& WatchdogFeed()
passed :& WatchdogDisable()
passed :& Not WatchdogIsEnabled() And Not WatchdogFeed()

If passed Then
	Print "Embedded watchdog conformance test passed"
Else
	Print "Embedded watchdog conformance test failed"
End If
