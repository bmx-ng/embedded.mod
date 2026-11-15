# Embedded.UI

`Embedded.UI` is a small retained user-interface layer for embedded displays.
It provides rows, columns and stacks, styled controls, focus navigation,
semantic events, scrolling, selectable lists, tabs and popup overlays, dialogs
and queued notifications. Optional control construction lives in
`Embedded.UI.Controls`, while touch handling lives in
`Embedded.UI.Interactive`. Rendering uses
`Embedded.Graphics2D`, so the same widget code can sit over mono or colour
display drivers.

## Basic structure

Create a context from a display, then add widgets to its root column:

```blitzmax
SuperStrict

Import BRL.Event
Import Embedded.UI
Import Embedded.UI.Interactive

Local ui:TUIContext = TUITouchInput.CreateContext(display, touch)
Local page:TUIColumn = ui.Root()

page.SetPadding(12)
page.SetGap(8)
page.Label("Settings")

Local enabled:TUICheckBox = page.CheckBox("Enabled")
Local save:TUIButton = page.Button("Save")

While True
    PollSystem()
    ui.Present()
Wend
```

The application retains its widget references and updates them directly.
`Present()` lays out invalid widgets, draws their dirty regions, advances any
active touch-scroll momentum when touch is configured, and presents the changed
display area.

### Display-only dashboards

A touch screen is optional. Sensor panels and other read-only dashboards can
use the same cards, labels, images, gauges, progress bars, status indicators
and sparklines without installing a touch device:

```blitzmax
Local ui:TUIContext = TUIContext.CreateDisplayOnly(display, theme)
Local page:TUIColumn = ui.Root()

Local temperature:TUIArcGauge = page.ArcGauge(-20, 60, 21)
Local history:TUISparkline = page.Sparkline(60)

While True
    temperature.SetValue(ReadTemperature())
    history.AddValue(temperature.Value())
    ui.Present()
Wend
```

A display-only context does not register for touch events, perform hit-testing,
or traverse the widget tree for touch-scroll momentum. Programmatic updates and
page changes still work, as do explicit focus operations if physical buttons,
an encoder or another application input source needs them.

Only import `Embedded.UI.Interactive` when touch is required. It owns the touch
driver dependency, global event hook, contact adapter and pointer/drag state
machine, and automatically imports `Embedded.UI.Controls`; these are absent
from a firmware image which imports only `Embedded.UI`.
`TUITouchInput.Attach()` can also add touch to an existing
context, while `CreateContext()` and `CreateContextWithBuffer()` provide
one-step construction.

## Layout and controls

Containers create their children with `Row()`, `Column()`, `Stack()`,
`ScrollView()` and `List()`. Common controls include labels, buttons,
checkboxes, switches, sliders and progress bars. Requested sizes, grow factors,
alignment, margins, padding and gaps determine layout without allocating a new
tree for every frame.

Passive presentation widgets such as labels, cards, images, gauges, progress
bars, indicators and sparklines need only `Embedded.UI`. Import
`Embedded.UI.Controls` for buttons, lists, tabs, selection/value controls,
popup menus and dialogs. This is useful for a non-touch device driven by GPIO
buttons or an encoder: it includes the controls without including a touch
driver or pointer state. Importing `Embedded.UI.Interactive` installs both the
standard controls and touch support automatically.

Controls support touch and explicit focus navigation. A non-touch input adapter
can use `FocusNext()`, `FocusPrevious()`, `ActivateFocused()` and
`AdjustFocused()` on the context. An application can map those operations to
GPIO buttons, an encoder, keypad or keyboard events. Focus changes emit
`EVENT_UIFOCUSCHANGED`; disabling or hiding a focused control safely releases
focus.

The theme controls the focus outline colour, width and inset. Set
`theme.focusWidth = 0` to hide every outline while preserving focus semantics,
or call `widget.SetFocusIndicatorVisible(False)` to hide it for one widget
without removing that widget from focus traversal.

Raw touch events are consumed only to update widget interaction state. Buttons
emit `EVENT_UIACTION`; checkboxes, switches and sliders emit
`EVENT_UIVALUECHANGED`. The event source identifies the widget and `event.data`
contains the new integer value where applicable. Controls also offer typed
callbacks. Programmatic value changes update the display without pretending
that the user performed the change.

## Scrolling and selection

`TUIScrollView` clips a natural-height vertical child layout into its assigned
viewport. It supports touch dragging, an optional position indicator,
programmatic scrolling and automatic visibility of focused descendants:

```blitzmax
Local scroll:TUIScrollView = page.ScrollView()
scroll.SetGrow(1)
scroll.SetScrollIndicatorVisible(True)

scroll.Label("First row")
scroll.Label("Second row")
```

Touch scrolling uses direct finger tracking by default. Applications running on
a display with sufficient presentation throughput can opt into integer,
time-based momentum with `SetMomentumEnabled(True)`. A released flick then
continues moving and decelerates predictably, stopping at either boundary. Use
`StopMomentum()` to stop a movement already in progress.

`TUIList` adds selectable `TUIListItem` children:

```blitzmax
Local list:TUIList = page.List()
list.SetGrow(1)
list.Item("Wi-Fi")
list.Item("Bluetooth")
list.Item("Display")
list.SetSelectedIndex(0)
```

User selection emits `EVENT_UISELECTIONCHANGED` with the list as its source and
the selected index in `event.data`. `OnSelectionChanged()` installs a direct
callback. Programmatic `SetSelectedIndex()` changes selection without pretending
that the user activated it. `MoveSelection()` clamps at the first and last item,
keeps the selected item focused, and scrolls it into view.

## Tabs, menus and combo boxes

`TUITabView` retains each page and only lays out and draws the selected one:

```blitzmax
Local tabs:TUITabView = page.TabView()
tabs.SetGrow(1)

Local general:TUITabPage = tabs.Page("General")
general.Label("General settings")

Local network:TUITabPage = tabs.Page("Network")
network.Label("Network settings")
```

Touching or explicitly activating a tab emits `EVENT_UISELECTIONCHANGED` with
the tab view as its source. `SetSelectedIndex()` switches pages
programmatically without emitting a user action.

## Page navigation

`TUIPageStack` provides application-style navigation while retaining every
page and its widget state:

```blitzmax
Local navigation:TUIPageStack = page.PageStack()
navigation.SetGrow(1)

Local home:TUIPage = navigation.Page("Home")
Local open:TUIButton = home.Button("Open settings")

Local settings:TUIPage = navigation.Page("Settings")
Local back:TUIButton = settings.Button("Back")

navigation.Push(settings)
```

The first page becomes the root automatically. `Push()` adds another page,
`Pop()` returns to its predecessor, and `Replace()` changes the current page
without changing the stack depth. Pages are hidden rather than destroyed, so
values, scroll positions and other retained state survive navigation. Popping
also restores the widget that was focused on the previous page. History has a
fixed `UIPageStackMaximum` capacity and Push/Pop do not allocate.

`TUIContext.Back()` first dismisses an open menu or dialog, then pops the
deepest visible page stack. It returns false at the root so an application can
handle an otherwise unconsumed system Back action. Navigation invokes the
optional `OnPageChanged()` callback and emits `EVENT_UIPAGECHANGED`; the event
data contains the new stack depth.

## Cards, grids and optional page chrome

Dashboard structure is composable rather than mandatory. `TUICard` is a
styled vertical container, while `TUIGrid` places ordinary widgets into equal
cells. A grid can use a fixed number of columns or derive a responsive count
from `SetMinimumColumnWidth()`. A child may occupy more than one column with
`SetGridSpan()`:

```blitzmax
Local header:TUIHeader = page.Header("Device dashboard")
header.Action("Settings", OpenSettings)

Local grid:TUIGrid = page.Grid(3)
grid.SetGap(10)
grid.SetRowHeight(96)

Local status:TUICard = grid.Card("System")
status.StatusIndicator("Online", True)

Local activity:TUICard = grid.Card("Activity")
activity.SetGridSpan(2)
activity.ProgressBar(0, 100, 68)

Local navigation:TUINavigationBar = page.NavigationBar()
navigation.Action("Home")
navigation.Action("Settings", OpenSettings)
```

`TUIHeader` provides an optional Back button, a growing title and trailing
action buttons. Its built-in Back action calls `TUIContext.Back()`. A
`TUINavigationBar` gives each action equal width. Headers, navigation bars,
cards and grids are independent widgets: applications may use any combination,
style them through the theme or omit them entirely. They do not require a page
stack and remain usable in tabs, dialogs and ordinary container trees.

A combo box owns a persistent popup and reports user selections through the
same selection event:

```blitzmax
Local mode:TUIComboBox = page.ComboBox()
mode.AddItem("Automatic")
mode.AddItem("Station")
mode.AddItem("Access point")
mode.SetSelectedIndex(0)
```

Applications can also construct a reusable popup menu. It is attached to the
context rather than the page layout:

```blitzmax
Local menu:TUIPopupMenu = ui.PopupMenu()
menu.Item("Rename")
menu.Item("Delete")
ui.ShowOverlay(menu, x, y, width)
```

Only one overlay is active in a context. Focus traversal remains inside it;
selection or `DismissOverlay()` restores the previous focus. A touch outside
the overlay dismisses it by default and is consumed, so it cannot accidentally
activate the control underneath. Use
`ShowOverlay(menu, x, y, width, UILayoutAuto, False)` for a modal overlay which
ignores outside touches.

## Choice, value and dialog widgets

Radio groups make the entire option label touchable and report the selected
index through `EVENT_UISELECTIONCHANGED`:

```blitzmax
Local quality:TUIRadioGroup = page.RadioGroup()
quality.Option("Economy")
quality.Option("Balanced")
quality.Option("Best")
quality.SetSelectedIndex(1)
```

A segmented control presents a small set of peer choices in one compact row.
Use it for modes or views rather than a large or changing collection:

```blitzmax
Local view:TUISegmentedControl = page.SegmentedControl()
view.AddItem("List")
view.AddItem("Grid")
view.AddItem("Chart")
```

`TUIStepper` provides precise bounded adjustment where a slider would be
ambiguous. Its fourth factory argument is the increment:

```blitzmax
Local copies:TUIStepper = page.Stepper(1, 9, 3, 1)
```

Decimal steppers use fixed-point units internally, keeping interaction
predictable while exposing `DecimalValue()` to application code:

```blitzmax
Local gain:TUIStepper = page.DecimalStepper(0.5, 5.0, 2.5, 0.5, 1)
```

The final argument selects the displayed decimal places. `ValueText()` returns
the same fixed-width representation shown by the control.

User changes emit `EVENT_UIVALUECHANGED` for a stepper and
`EVENT_UISELECTIONCHANGED` for radio groups and segmented controls. Their
`OnChange()` or `OnSelectionChanged()` callbacks offer the equivalent direct
notification. Programmatic setters do not emit user events.

Dialogs use the overlay layer and remain modal until an action is selected:

```blitzmax
Local dialog:TUIDialog = ui.Dialog("Apply settings?", "Changes take effect immediately.")
dialog.Action("Cancel", 0)
dialog.Action("Apply", 1)
dialog.OnResult(DialogClosed)
dialog.Show(320)
```

The chosen result is available through `Result()`, is passed to `OnResult()`,
and is emitted as `EVENT_UIACTION` with the dialog as the event source. Dialog
focus remains trapped inside the overlay and returns to the previous widget on
close.

Labels can opt into width-aware word wrapping with `SetWordWrap(True)`.
Dialog messages enable this automatically and their height is calculated from
the width passed to `Show()`.

## Toast notifications

Toasts are non-modal messages drawn above both normal content and overlays.
They never take focus and do not intercept touch input:

```blitzmax
ui.Toast("Settings saved", 2500, UIToastSuccess)
ui.Toast("Signal is weak", 3500, UIToastWarning)
```

Kinds are `UIToastInfo`, `UIToastSuccess`, `UIToastWarning` and
`UIToastError`. The duration is in milliseconds; use zero for a persistent
notification which must be closed explicitly:

```blitzmax
Local offline:TUIToast = ui.Toast("Offline mode is active", 0, UIToastWarning)
' Later:
offline.Close()
```

Up to three toasts are visible by default. New bottom-anchored messages push
older messages upward; top-anchored messages push them downward. The stack
closes its gaps whenever a notification expires or is dismissed. Configure it
with `SetToastVisibleLimit()`, `SetToastGap()` and `SetToastMargin()`. A visible
limit of one provides strictly sequential FIFO presentation.

`SetToastPlacement()` selects the context default from nine anchors ranging
from `UIToastTopLeft` to `UIToastBottomRight`. The optional fourth `Toast()`
argument or `TUIToast.SetPlacement()` can override it for one message.

Messages beyond the visible limit are retained in FIFO order, up to
`UIToastQueueMaximum` pending messages. `Toast()` returns `Null` when that
bound is reached. `DismissToast()` closes the newest visible toast and advances
the queue, while `DismissToast(toast)` can dismiss a specific visible toast or
cancel a queued message. `ClearToasts()` removes every visible and pending
notification. Messages wrap automatically to the available display width.

## Dashboards and widget images

Dashboard widgets share the existing retained layout and dirty-region model:

```blitzmax
Local link:TUIStatusIndicator = page.StatusIndicator("Network", True)

Local temperature:TUIArcGauge = page.ArcGauge(-20, 80, 23)
temperature.SetLabel("Temperature")
temperature.SetUnit(" C")

Local history:TUISparkline = page.Sparkline(60)
history.SetRange(0, 100)
history.AddValue(42)

Local setPoint:TUIRotaryDial = page.RotaryDial(0, 100, 50)
setPoint.SetStep(5)
```

`TUIStatusIndicator` is a compact labelled state lamp. `TUIArcGauge` draws a
read-only 270-degree meter with optional ticks, units and value text.
`TUISparkline` owns a fixed-capacity rolling sample buffer: once full, adding a
sample replaces the oldest one without allocating. It can use an explicit
range or calculate one from the retained samples.

`TUIRotaryDial` is interactive. Horizontal dragging is the default: drag right
to increase and left to decrease. Use
`SetDragDirection(UIDialDragVertical)` to instead drag upward to increase and
downward to decrease. Both modes avoid the discontinuity that angle-following
knobs have near their end stops. User changes use `EVENT_UIVALUECHANGED` and
`OnChange()`. Focused dials also respond to `AdjustFocused()`.

Images are optional presentation rather than part of widget behaviour.
`TUIButton.SetStateImages()` accepts normal, pressed and disabled artwork, so
an image-backed button retains the same touch, focus and action semantics as a
themed button. Status indicators accept inactive and active images. Arc gauges
and rotary dials accept an optional face image, then draw their live value over
it. Without images all four controls render from primitives and remain suitable
for monochrome displays.

## Themes and rendering cost

`TUITheme.Dark()` supplies a complete default theme and can use any imported
bitmap font. Individual widget styles may override font scale, colours, border,
corner radius and padding. `SetButtonMinimumHeight()` keeps button touch targets
independent of bitmap-font dimensions. `SetSelectionMinimumHeight()` does the
same for combo boxes and their selectable dropdown rows. An explicit widget
height still wins.

The implementation's scope, bounded-runtime rules and acceptance criteria are
recorded in [DESIGN.md](DESIGN.md).

Scrolling invalidates the scroll viewport because its children move. Keep list
viewports and item decoration proportionate to the display and update rate.
Momentum itself uses only integer arithmetic and does not allocate per frame.
