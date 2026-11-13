# Embedded.UI

`Embedded.UI` is a small retained user-interface layer for embedded displays.
It provides rows, columns and stacks, styled controls, focus navigation, touch
handling, semantic events, scrolling, selectable lists, tabs and popup
overlays. Rendering uses `Embedded.Graphics2D`, so the same widget code can sit
over mono or colour display drivers.

## Basic structure

Create a context from a display, then add widgets to its root column:

```blitzmax
SuperStrict

Import BRL.Event
Import Embedded.UI

Local ui:TUIContext = TUIContext.Create(display, touch)
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
active scroll momentum, and presents the changed display area.

## Layout and controls

Containers create their children with `Row()`, `Column()`, `Stack()`,
`ScrollView()` and `List()`. Common controls include labels, buttons,
checkboxes, switches, sliders and progress bars. Requested sizes, grow factors,
alignment, margins, padding and gaps determine layout without allocating a new
tree for every frame.

Controls support touch and explicit focus navigation. A non-touch input adapter
can use `FocusNext()`, `FocusPrevious()`, `ActivateFocused()` and
`AdjustFocused()` on the context. An application can map those operations to
GPIO buttons, an encoder, keypad or keyboard events. Focus changes emit
`EVENT_UIFOCUSCHANGED`; disabling or hiding a focused control safely releases
focus.

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

## Themes and rendering cost

`TUITheme.Dark()` supplies a complete default theme and can use any imported
bitmap font. Individual widget styles may override font scale, colours, border,
corner radius and padding.

Scrolling invalidates the scroll viewport because its children move. Keep list
viewports and item decoration proportionate to the display and update rate.
Momentum itself uses only integer arithmetic and does not allocate per frame.
