# Embedded.UI

`Embedded.UI` is a small retained user-interface toolkit built directly on
`Embedded.Graphics2D`. It is intended for predictable device interfaces rather
than as a complete replacement for a desktop GUI toolkit or LVGL.

The initial vertical slice provides:

- a parent-owned widget tree;
- row, column, and overlapping stack containers;
- fixed, automatic, fill, and weighted-grow sizing;
- margins, padding, gaps, and cross-axis alignment;
- a reusable dark theme with normal, active, pressed, and disabled states;
- labels, buttons, checkboxes, switches, sliders, and progress bars;
- touch hit-testing, capture, and continuous slider tracking;
- `EVENT_UIACTION`, `EVENT_UIVALUECHANGED`, and optional typed callbacks;
- explicit focus, traversal, activation, adjustment, and themed focus indication;
- automatic layout and dirty-region presentation.

Methods use the ordinary parenthesised BlitzMax form:

```blitzmax
Local ui:TUIContext = TUIContext.Create(display, touch, TUITheme.Dark(font))
Local page:TUIColumn = ui.Root()
page.SetPadding(16)
page.SetGap(10)

Local title:TUILabel = page.Label("Network")
Local connect:TUIButton = page.Button("Connect")
connect.OnClick(ConnectToNetwork)

Local alerts:TUICheckBox = page.CheckBox("Alerts", True)
alerts.OnChange(AlertsChanged)

Local brightness:TUISlider = page.Slider(0, 100, 50)
brightness.OnChange(BrightnessChanged)
Local progress:TUIProgressBar = page.ProgressBar(0, 100, 50)

ui.Present()
```

Raw touch events are consumed only to update widget interaction state. An
activated button emits a semantic `EVENT_UIACTION` whose source is the button,
allowing applications to use the standard `BRL.Event` loop instead of a
callback when preferred. Checkboxes, switches, and sliders emit
`EVENT_UIVALUECHANGED`; the event source identifies the widget and `data`
contains its new integer value. Programmatic `SetValue()` and `SetChecked()`
calls update the display without pretending that the user changed the value.

## Focus and device navigation

Interactive controls participate in focus traversal. Touching one gives it
focus, but navigation is deliberately independent of any particular input
hardware:

```blitzmax
ui.FocusNext()
ui.FocusPrevious()
ui.ActivateFocused()
ui.AdjustFocused(1)
```

An application can map those operations to GPIO buttons, an encoder, keypad,
or keyboard events. `AdjustFocused()` changes a focused slider using the
application-selected step. Focus changes emit `EVENT_UIFOCUSCHANGED`, and
`FocusedWidget()` exposes the current control. Disabling or hiding a focused
control safely releases focus.
