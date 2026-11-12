# Embedded.UI

`Embedded.UI` is a small retained user-interface layer for embedded displays.
It provides rows, columns and stacks, styled controls, focus navigation, touch
handling, semantic events, scrolling and selectable lists. Rendering uses
`Embedded.Graphics2D`, so the same widget code can sit over mono or colour
display drivers.

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

## Themes and rendering cost

`TUITheme.Dark()` supplies a complete default theme and can use any imported
bitmap font. Individual widget styles may override font scale, colours, border,
corner radius and padding.

Scrolling invalidates the scroll viewport because its children move. Keep list
viewports and item decoration proportionate to the display and update rate.
Momentum itself uses only integer arithmetic and does not allocate per frame.
