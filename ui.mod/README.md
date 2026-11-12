# Embedded.UI

`Embedded.UI` is a small retained user-interface toolkit built directly on
`Embedded.Graphics2D`. It is intended for predictable device interfaces rather
than as a complete replacement for a desktop GUI toolkit or LVGL.

The initial vertical slice provides:

- a parent-owned widget tree;
- row, column, and overlapping stack containers;
- fixed, automatic, fill, and weighted-grow sizing;
- margins, padding, gaps, and cross-axis alignment;
- a reusable dark theme with normal, pressed, and disabled button states;
- labels and buttons;
- touch hit-testing and button capture;
- `EVENT_UIACTION` plus an optional `OnClick()` callback;
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

ui.Present()
```

Raw touch events are consumed only to update widget interaction state. An
activated button emits a semantic `EVENT_UIACTION` whose source is the button,
allowing applications to use the standard `BRL.Event` loop instead of a
callback when preferred.
