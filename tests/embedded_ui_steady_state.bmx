SuperStrict

' Verifies that an already-constructed UI performs no managed allocations
' while presenting, redrawing retained values, polling an idle input device,
' or dispatching pointer events supplied by a caller-owned event object.

Framework BRL.StandardIO
Import BRL.Event
Import BRL.System
Import BRL.SystemDefault
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Drivers.Touch
Import Embedded.Runtime.Memory
Import Embedded.UI
Import Embedded.UI.Interactive

Const SteadyStateCycles:Int = 128

Type TSteadyTouch Extends TTouchDevice
	Field count:Int

	Method Width:Int() Override
		Return 120
	End Method

	Method Height:Int() Override
		Return 80
	End Method

	Method PollContacts:Int() Override
		Return count
	End Method

	Method ContactId:Int(index:Int) Override
		Return 7
	End Method

	Method ContactX:Int(index:Int) Override
		Return 60
	End Method

	Method ContactY:Int(index:Int) Override
		Return 60
	End Method
End Type

Type TSteadyControl Extends TUIWidget
	Field activations:Int
	Field adjustments:Int
	Field pointerBegins:Int
	Field pointerTracks:Int
	Field pointerEnds:Int
	Field lastTrackX:Int

	Method New()
		SetFocusable(True)
		clickable = True
	End Method

	Method PreferredSize(availableWidth:Int, availableHeight:Int, width:Int Var, height:Int Var) Override
		width = 52
		height = 24
	End Method

	Method _ActivateFocused:Int() Override
		activations :+ 1
		Return True
	End Method

	Method _AdjustFocused:Int(delta:Int) Override
		adjustments :+ delta
		Return True
	End Method

	Method _BeginPointer:Int(x:Int, y:Int) Override
		pointerBegins :+ 1
		Return True
	End Method

	Method _TrackPointer:Int(x:Int, y:Int) Override
		pointerTracks :+ 1
		lastTrackX = x
		Return True
	End Method

	Method _EndPointer() Override
		pointerEnds :+ 1
	End Method
End Type

Function Check(condition:Int, message:String)
	If Not condition Then RuntimeError message
End Function

Function CheckStable(allocations:UInt, used:UInt, collections:UInt, message:String)
	Check(ArenaAllocationCount() = allocations, message)
	Check(ArenaUsed() = used, "steady-state arena use changed")
	Check(CollectionCount() = collections, "steady-state rendering triggered collection")
End Function

Local frame:TDisplayBuffer = TDisplayBuffer.Create(120, 80, DisplayPixelFormatMono1)
Local touch:TSteadyTouch = New TSteadyTouch
Check(touch.StartEvents(), "could not start steady-state touch device")
Local ui:TUIContext = TUITouchInput.CreateContextWithBuffer(frame, Null, touch, ..
	TUITheme.Dark(Spleen5x8Font()))
Check(ui <> Null, "could not create steady-state UI")
Local touchInput:TUITouchInput = TUITouchInput(ui.inputBinding)
Check(touchInput And touchInput.PointerMoveCoalescing(), ..
	"touch movement was not frame-coalesced by default")

Local page:TUIColumn = ui.Root()
page.SetPadding(2)
page.SetGap(2)
page.Label("Steady state")
Local progress:TUIProgressBar = page.ProgressBar(0, 100, 0)
Local control:TSteadyControl = New TSteadyControl
page.Add(control)
Check(ui.Render(), "initial steady-state UI did not render")
Check(ui.SetFocus(control), "steady-state control could not receive focus")

' Warm every exercised route before taking the first snapshot.
For Local warm:Int = 0 Until 4
	progress.SetValue(warm)
	Check(ui.Render(), "steady-state warm-up did not render")
	PollSystem()
Next

Local allocations:UInt = ArenaAllocationCount()
Local used:UInt = ArenaUsed()
Local collections:UInt = CollectionCount()
For Local cycle:Int = 0 Until SteadyStateCycles
	ui.Present()
Next
CheckStable(allocations, used, collections, "idle presentation allocated managed memory")

allocations = ArenaAllocationCount()
used = ArenaUsed()
collections = CollectionCount()
For Local cycle:Int = 0 Until SteadyStateCycles
	progress.SetValue(cycle Mod 101)
	Check(ui.Render(), "retained value redraw failed")
Next
CheckStable(allocations, used, collections, "retained value redraw allocated managed memory")

allocations = ArenaAllocationCount()
used = ArenaUsed()
collections = CollectionCount()
For Local cycle:Int = 0 Until SteadyStateCycles
	PollSystem()
Next
CheckStable(allocations, used, collections, "idle input polling allocated managed memory")

' Create one event before the snapshot. Reusing it models a fixed native input
' queue and proves that the UI input binding adds no allocation of its own.
Local pointerX:Int = Int(Long(control.X() + control.Width() / 2) * 10000 / (frame.Width() - 1))
Local pointerY:Int = Int(Long(control.Y() + control.Height() / 2) * 10000 / (frame.Height() - 1))
Local pointerEvent:TEvent = CreateEvent(EVENT_TOUCHDOWN, touch, 7, 0, pointerX, pointerY)
allocations = ArenaAllocationCount()
used = ArenaUsed()
collections = CollectionCount()
For Local cycle:Int = 0 Until SteadyStateCycles
	pointerEvent.id = EVENT_TOUCHDOWN
	pointerEvent.x = pointerX
	EmitEvent(pointerEvent)
	pointerEvent.id = EVENT_TOUCHMOVE
	pointerEvent.x = pointerX + 100
	EmitEvent(pointerEvent)
	pointerEvent.id = EVENT_TOUCHUP
	EmitEvent(pointerEvent)
	Check(ui.ActivateFocused(), "focused steady-state activation failed")
	Check(ui.AdjustFocused(1), "focused steady-state adjustment failed")
Next
Check(control.pointerBegins = SteadyStateCycles And ..
	control.pointerTracks = SteadyStateCycles And ..
	control.pointerEnds = SteadyStateCycles And ..
	control.activations = SteadyStateCycles * 2 And ..
	control.adjustments = SteadyStateCycles, "steady-state input dispatch count was incorrect")
CheckStable(allocations, used, collections, "steady-state input dispatch allocated managed memory")

' Multiple device reports between frames collapse to the newest visible state.
Local tracksBeforeCoalescing:Int = control.pointerTracks
pointerEvent.id = EVENT_TOUCHDOWN
pointerEvent.x = pointerX
EmitEvent(pointerEvent)
pointerEvent.id = EVENT_TOUCHMOVE
pointerEvent.x = pointerX + 100
EmitEvent(pointerEvent)
pointerEvent.x = pointerX + 200
EmitEvent(pointerEvent)
pointerEvent.x = pointerX + 300
EmitEvent(pointerEvent)
Check(control.pointerTracks = tracksBeforeCoalescing, ..
	"pointer movement was applied before the frame boundary")
ui.Present()
Check(control.pointerTracks = tracksBeforeCoalescing + 1, ..
	"pointer movements were not coalesced into one frame update")
Local expectedTrackX:Int = Int((Long(pointerX + 300) * (frame.Width() - 1) + 5000) / 10000)
Check(control.lastTrackX = expectedTrackX, ..
	"frame-coalesced pointer movement did not retain the newest coordinate")
pointerEvent.id = EVENT_TOUCHUP
EmitEvent(pointerEvent)

' Raw movement remains available for applications which explicitly need it.
touchInput.SetPointerMoveCoalescing(False)
Local tracksBeforeRaw:Int = control.pointerTracks
pointerEvent.id = EVENT_TOUCHDOWN
pointerEvent.x = pointerX
EmitEvent(pointerEvent)
pointerEvent.id = EVENT_TOUCHMOVE
pointerEvent.x = pointerX + 200
EmitEvent(pointerEvent)
Check(control.pointerTracks = tracksBeforeRaw + 1, ..
	"raw pointer movement was not dispatched immediately")
pointerEvent.id = EVENT_TOUCHUP
EmitEvent(pointerEvent)
touchInput.SetPointerMoveCoalescing(True)

ui.Close()
touch.StopEvents()
Print "embedded UI steady state: PASS"
?
