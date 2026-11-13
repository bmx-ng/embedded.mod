# Embedded.UI design constraints

`Embedded.UI` is a compact retained interface toolkit for device panels,
dashboards, settings screens and similar embedded applications. It is not
intended to reproduce a desktop widget toolkit or all of LVGL.

## Runtime rules

- Work performed per frame or input event must be bounded.
- Widget-tree depth must not multiply native stack use in navigation, focus or
  other control paths. Prefer iterative traversal for operations which may
  inspect an application-defined hierarchy.
- Rendering and input polling should not allocate managed objects during a
  steady-state frame. Retained changes may allocate when an application adds
  widgets or replaces content.
- Queues and retained histories have explicit limits. Reaching a limit must
  fail predictably rather than silently growing without bound.
- Font metrics describe content, not ergonomics. Touch-target dimensions are
  independent theme or widget settings.
- Touch is an optional `Embedded.UI.Interactive` adapter. `Embedded.UI` must not
  import the touch abstraction, install an input event hook, or retain pointer
  and drag state. A display-only context must not occupy an input slot, receive
  touch events, perform input hit-testing, or scan for gesture momentum.
- Dirty rendering must produce the same visible result as a complete redraw.
  Page changes may invalidate the complete output when every pixel can change.
- Platform acceleration and multiple framebuffers are optional adapters. UI
  behaviour must remain correct with a single software framebuffer.

## Public surface

The stable core consists of:

- retained widgets and styles;
- row, column, stack, grid and scrolling layout;
- focus input, with touch supplied by the optional interactive adapter;
- labels, buttons, selection and value controls;
- pages, tabs, overlays, dialogs and notifications;
- image-backed presentation and bitmap fonts.

Higher-level cards, headers and navigation bars are compositions of the same
core widgets. They must remain optional and configurable rather than imposing
one dashboard design.

## Validation

Changes should preserve these acceptance checks:

1. Repeated push, replace, pop and Back operations restore the expected page
   and focus without increasing stack or retained history.
2. Drag input tracks the newest contact position without replaying a stale
   event backlog.
3. Dirty, single-buffered and multi-buffered presentation agree visually.
4. Layout remains bounded on representative small, medium and large displays.
5. Controls intended for touch can set minimum target dimensions independently
   of font choice.
6. Pico and ESP32 use the same public UI behaviour; platform-specific code is
   restricted to display, touch and acceleration adapters.

New widget families should wait until these checks are stable on both current
embedded targets.
