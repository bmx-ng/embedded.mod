# Embedded device drivers

`Embedded.Drivers.*` contains portable drivers for devices attached to the
shared embedded hardware APIs. A controller driver belongs here when it can use
the same public API and behaviour on Pico, ESP32, ESP8266, and future embedded
targets. Board profiles remain target-owned and describe how a particular board
wires those devices.

## Displays

`Embedded.Drivers.Display` defines the common raster and presentation boundary:

- `TDisplayBuffer` owns a compact Mono1, RGB565, or RGB888 raster, or wraps a
  driver-owned external framebuffer without copying it;
- drawing is independent of the physical display controller;
- a `TDisplay` advertises its preferred format and accepts full or dirty-region
  presentation; and
- `PresentPixels` accepts an external raster pointer, providing the low-level
  flush boundary needed by graphics libraries without requiring them to own the
  controller driver.

Mono1 rows are top-to-bottom and most-significant-bit first. RGB565 is stored
little-endian, and RGB888 is stored red, green, blue. Drivers convert this
stable representation to any controller-specific page or transfer layout.

The base layer deliberately remains useful without a full UI library. Small
status applications can allocate one buffer, draw pixels, lines and rectangles,
then present it without additional frame-time allocation.

`Embedded.Graphics2D` is an optional familiar drawing facade over this layer.
It provides `Cls`, `SetColor`, `SetFont`, `DrawText`, `DrawImage`,
`DrawImageRect`, `DrawImageRegion`, `Plot`, `DrawLine`, `DrawRect`, `FillRect`,
origins, viewports, nested local views, saved drawing state, text metrics, exact
quarter-turn canvas rotation, and `Present`. The global functions use one default
context for compact applications;
`TEmbedded2DContext` exposes the same operations without global state for
libraries or applications using multiple displays. It owns no second buffer and
does not allocate while drawing.

```blitzmax
SetRenderTarget frame, display
SetFont Spleen5x8Font()
SetColor 255, 255, 255
Cls
DrawText "Hello", 2, 2
DrawLine 0, 12, 71, 12
Present
```

For displays where transfer bandwidth matters, Graphics2D can accumulate one
conservative dirty rectangle without allocating a tile list or inspecting the
framebuffer. Tracking is opt-in, so applications that always present complete
frames do no dirty-bound calculations:

```blitzmax
SetDirtyTracking True

' Draw one update. Viewports, origins, nested views and rotations are reflected
' in the physical framebuffer rectangle automatically.
FillRect 20, 12, 40, 18
DrawText "42", 24, 16
PresentDirty
```

`PresentDirty` calls the display's existing `PresentRegion` boundary and clears
the region only after a successful transfer. If nothing changed, it succeeds
without calling the driver. A failed transfer retains the rectangle for retry.
`DirtyRect` exposes the accumulated physical bounds for diagnostics,
`ResetDirty` discards them, and `InvalidateRect` or `InvalidateAll` covers
changes made outside Graphics2D. Drivers remain free to expand a request to
page, row, DMA, or controller-specific transfer boundaries.

`TDisplay.Capabilities` distinguishes partial presentation, a live scanout
framebuffer, vertical synchronization, true buffer swapping, optimized discard
presentation, accelerated solid fills, and accelerated image blits. Existing
drivers retain the original synchronous partial-presentation behavior without
needing an override. A driver which exchanges its own framebuffers can use
`TDisplayBuffer.RetargetExternal` to keep the buffer object—and therefore the
renderer bound to it—stable while changing the underlying pixel storage.

`PresentDiscard` is the explicit full-redraw fast path. It permits a driver to
leave the next render buffer with stale or undefined contents after presenting;
the application must overwrite every pixel before presenting again. Drivers
which do not advertise `DisplayCapabilityDiscardPresent` safely fall back to
ordinary coherent presentation.

`SetRotation` accepts clockwise `0`, `90`, `180`, or `270` degree orientation.
All primitives, text, and images use the rotated logical canvas; `GraphicsWidth`
and `GraphicsHeight` report its dimensions. Rotation remaps integer coordinates
without trigonometry, filtering, another framebuffer, or frame-time allocation:

```blitzmax
SetRotation 90
DrawText "Portrait", 4, 4
Present
```

Display orientation is device configuration rather than a drawing transform.
Call `display.SetOrientation(90)` before `SetRenderTarget` to make portrait the
default, so `SetRotation(0)` uses that orientation and the logical dimensions are
swapped. `SetDisplayOrientation` changes it through the active Graphics2D context
at runtime, retaining the current relative drawing rotation and resetting the
viewport. This supports sensor-driven auto-rotation without rotating the complete
framebuffer or allocating another one.

`BeginView` creates a clipped local coordinate system within the current view.
Its optional rotation is clockwise and limited to exact `0`, `90`, `180`, or
`270` degree turns. Views compose when nested, so a widget or library can draw
at `(0, 0)` without knowing its final position or orientation. `EndView`
restores the parent automatically:

```blitzmax
BeginView 20, 12, 120, 64
SetClsColor 12, 20, 32
Cls
DrawText "Status", 4, 4

BeginView 88, 8, 24, 48, 90
DrawRect 0, 0, GraphicsWidth(), GraphicsHeight()
EndView
EndView
```

`PushGraphicsState` and `PopGraphicsState` save and restore the font, colours,
origin, viewport, relative canvas rotation, and current view transform. The
stack has sixteen entries which are allocated with the context, so pushing,
popping, and drawing do not allocate. Overflow and underflow return `False`.
Device orientation is hardware configuration and deliberately is not part of
the saved drawing state.

`ViewToScreen` and `ScreenToView` convert between the current local view and
the root orientation-aware screen. They include the current origin, relative
drawing rotation, and every nested quarter-turn, while remaining independent
of the framebuffer's physical orientation. `PointInView` additionally tests
the current viewport, making it suitable for touch hit-testing while traversing
nested UI views. `GraphicsScreenWidth` and `GraphicsScreenHeight` provide the
correct root extents even when a relative drawing rotation is active:

```blitzmax
Local screenX:Int = event.x * (GraphicsScreenWidth() - 1) / 10000
Local screenY:Int = event.y * (GraphicsScreenHeight() - 1) / 10000

BeginView 20, 12, 120, 64, 90
If PointInView(screenX, screenY) Then
	Local x:Int, y:Int
	ScreenToView screenX, screenY, x, y
	' x and y are now local drawing coordinates for this view.
End If
EndView
```

The shared primitive set includes outlined and filled rectangles, circles,
ellipses, triangles, and rounded rectangles. Curves and fills use deterministic
integer rasterisation, inherit the current colour, origin, viewport, and nested
view transform, and do not allocate while drawing:

```blitzmax
SetColor 40, 170, 255
FillRoundRect 12, 12, 120, 48, 10
DrawCircle 172, 36, 22
FillTriangle 220, 58, 252, 12, 284, 58
```

Text can be measured and laid out without creating temporary strings.
`TextBoxSize` reports the wrapped dimensions, while `DrawTextBox` supports left,
centre, and right alignment, explicit newlines, word wrapping, clipping, integer
font scaling, and optional final-line ellipsis:

```blitzmax
Local textWidth:Int
Local textHeight:Int
Local lines:Int = TextBoxSize(message, 180, textWidth, textHeight)

SetColor 235, 240, 255
DrawTextBox message, 12, 12, 180, 72, TextAlignCenter, 1, True
```

Concrete display drivers live beneath `Embedded.Drivers.Displays.*`.
`Embedded.Drivers.Displays.SSD1306` is the first controller implementation. It uses
`Embedded.Hardware.I2C`, supports dirty page updates, and includes the 72x40
EastRising-compatible preset used by common 0.42-inch OLED boards.

## Touch input

`Embedded.Drivers.Touch` is the controller-neutral touch boundary. A
`TTouchDevice` supplies a fixed snapshot of contact ids and display-pixel
coordinates. Calling `StartEvents` makes the shared polling layer emit the
standard `BRL.Event` values `EVENT_TOUCHDOWN`, `EVENT_TOUCHMOVE`, and
`EVENT_TOUCHUP`.

Touch events follow the same convention as desktop BlitzMax backends:

- `event.source` is the `TTouchDevice`;
- `event.data` is the stable contact/finger id; and
- `event.x` and `event.y` are normalized to `0..10000` across the associated
  display rather than being controller-specific raw coordinates.

`TTouchDevice.SetOrientation` applies the same quarter-turn convention as
`TDisplay.SetOrientation`. A project using portrait, upside-down, or runtime
auto-rotation should set both devices to the same orientation.

The shared layer tracks contact transitions without per-poll allocation.
Concrete controller modules only read the hardware and expose the current
contact snapshot, so future Pico and ESP32 adapters can share identical event
semantics.

## Images and bitmaps

`Embedded.Drivers.Display.Image` loads the compact EBI1 format from persistent
firmware memory. An EBI1 image contains raw Mono1, RGB565, RGB888, or packed
1-, 2-, 4-, or 8-bit indexed pixels and an optional one-bit transparency mask.
Indexed palettes contain only the colours actually used and retain exact
24-bit RGB values. The header, palette indices, and every data range are
validated when `TEmbeddedImage.Create` is called. Drawing thereafter is
allocation-free: indexed pixels are expanded individually while rendering,
never into a full-size temporary bitmap. Drawing supports clipping, colour
tinting, pixel-format conversion, unscaled source regions, deterministic
nearest-neighbour scaling, horizontal and vertical flips, 0..255 opacity, and
source colour-key transparency. Existing one-bit masks and colour keys may be
used together; either can suppress a pixel. Opacity uses straight source-over
blending against the current framebuffer.

RGB565 and RGB888 images drawn to RGB565 targets use a shared native raster
path for copies, format conversion, clipping, nearest-neighbour scaling,
mirroring, tinting, and exact 0..255 opacity blending. A display adapter may
register a hardware implementation for compatible operations; unsupported
memory layouts and scale ratios, masks, and colour keys fall back automatically
without changing drawing semantics. Applications can inspect
`DisplayCapabilityAcceleratedBlit`, but use the same `DrawImage` and
`DrawImageRect` calls on accelerated and software targets.

The desktop converter in `tools/image2embedded.bmx` uses the normal BlitzMax
`image.mod` loaders. It accepts PNG, JPEG, BMP, GIF, TGA, PNM, QOI, WebP, TIFF,
and SVG inputs. Build it once with the desktop SDK, then select the smallest
format suitable for the target display:

```sh
bmk makeapp -r -o image2embedded tools/image2embedded.bmx
image2embedded icon.svg icon.ebi --format mono1 --mask auto
image2embedded splash.png splash.ebi --format rgb565 --mask auto
image2embedded sprites.png sprites.ebi --format auto --mask auto
image2embedded ui-icons.png ui-icons.ebi --format indexed4 --mask auto
```

`--threshold` controls monochrome conversion, `--alpha-threshold` controls the
one-bit transparency decision, and `--mask auto|always|none` controls whether a
mask is emitted. `auto` only adds one when the source contains transparency.
The `auto` pixel format chooses the smallest exact indexed representation for
images containing no more than 256 colours, otherwise it falls back to RGB565.
An explicit indexed format requires the source to fit its 2-, 4-, 16-, or
256-colour capacity and reports an error rather than silently quantising it.
RGB565 is little-endian and is generally the compact photographic choice;
RGB888 avoids colour quantisation. No decoder or source image library is linked
into the firmware.

Embed the converted asset and draw it through either `TEmbeddedImage` directly
or `Embedded.Graphics2D`:

```blitzmax
Incbin "icon.ebi"

Local icon:TEmbeddedImage = TEmbeddedImage.Create(IncbinPtr("icon.ebi"), ..
    IncbinLen("icon.ebi"))
SetRenderTarget frame, display
SetColor 255, 255, 255
DrawImage icon, 2, 2
DrawImageRect icon, 24, 2, 32, 32
DrawImage icon, 60, 2, ImageFlipX
DrawImageRect icon, 92, 2, 32, 32, ImageFlipY, 128
' Magenta source pixels are transparent; the key is tested before SetColor tinting.
DrawImage icon, 128, 2, 0, 255, $ff00ff
Present
```

`ImageFlipX` and `ImageFlipY` can be combined with `|`. Omitting the final
arguments preserves the original opaque draw fast path, including direct row
copies when the source and destination pixel formats match. Blended draws read
the existing destination pixel and are consequently more expensive; opacity
zero returns without touching the framebuffer.

Image pixels live in flash through `Incbin`; only the display framebuffer uses
RAM. Applications only pay for assets and the image module when they import it.

## Bitmap fonts and text

`Embedded.Drivers.Display.Font` renders compact, Unicode-addressed bitmap fonts
into any `TDisplayBuffer`. Rendering and measurement perform no allocation, and
integer pixel scaling reuses the original glyph data. Text coordinates specify
the top-left of the first line rather than a controller-specific baseline.

The bundled bitmap-font catalogue contains only fonts with clear
redistribution-friendly licences. Every face or size is an independently
imported module and carries its upstream licence as `FONT-LICENSE.txt`:

| Family | Native faces | Glyph coverage | Font licence |
| --- | --- | ---: | --- |
| ANAKRON | 8x12 | 2,006 | SIL OFL 1.1 |
| Cozette | 6x13 | 6,046 | MIT |
| Scientifica | 11-pixel regular, bold, and italic | 981-1,082 | SIL OFL 1.1 |
| Spleen | 5x8, 6x12, 8x16, 12x24, 16x32, and 32x64 | 472-1,004 | BSD 2-Clause |
| Tamzen | 5x9, 6x12, 7x13, 7x14, 8x15, 8x16, and 10x20; regular and bold | 189-190 | permissive Tamzen/Tamsyn licence |
| Terminus | 6x12 through 16x32; regular and bold except 6x12 | 1,356 | SIL OFL 1.1 |

Module names reflect family, weight, and native size. For example,
`Embedded.Drivers.Display.Fonts.Cozette.Regular6x13` exposes
`Cozette6x13Font()`, while
`Embedded.Drivers.Display.Fonts.Terminus.Bold12x24` exposes
`Terminus12x24BoldFont()`.

The complete Spleen bitmap family is grouped below
`Embedded.Drivers.Display.Fonts.Spleen`:

| Module suffix | Native cell | Glyphs | EBF1 data |
| --- | ---: | ---: | ---: |
| `Size5x8` | 5x8 | 472 | 11,360 bytes |
| `Size6x12` | 6x12 | 548 | 15,376 bytes |
| `Size8x16` | 8x16 | 1,004 | 32,160 bytes |
| `Size12x24` | 12x24 | 975 | 62,432 bytes |
| `Size16x32` | 16x32 | 1,004 | 80,352 bytes |
| `Size32x64` | 32x64 | 1,004 | 273,120 bytes |

For example, importing `Embedded.Drivers.Display.Fonts.Spleen.Size8x16`
exposes `Spleen8x16Font()`. Only that module's EBF1 data is linked;
applications which do not import a size pay no flash cost for it. Use the
native size where possible. The renderer can still apply exact integer
enlargement when useful.

The desktop tool `tools/bdf2embeddedfont.bmx` converts BDF sources to the EBF1
format used by `TBitmapFont`. It can retain hexadecimal ranges, the characters
in literal text, or every character occurring in a UTF-8 text/resource file:

```sh
bdf2embeddedfont input.bdf output.ebf --ranges 0020-007e,00a0-00ff
bdf2embeddedfont input.bdf output.ebf --chars "Temperature: 0123456789.C"
bdf2embeddedfont input.bdf output.ebf --chars-file application-text.txt
bdf2embeddedfont input.bdf output.ebf --chars "0123456789" --fallback 003f
```

Selection options may be repeated and combined. With no selection the complete
BDF is emitted. The font's default glyph is always retained. Use `--fallback`
to select a different replacement such as `003f` (`?`) when the BDF default is
blank. The older positional range-list syntax remains supported.

For a repeatable application build, put its font requirements in a manifest:

```ini
# font-subset.manifest
ranges=0030-0039,002e-002f
chars=Temperature: °C
fallback=003f
chars-file=text/en.txt
chars-file=text/sensor-labels.txt
```

Entries may be repeated. Character-file paths are resolved relative to the
manifest, making it safe to invoke the tool from another directory. Generate or
refresh the resource with:

```sh
bdf2embeddedfont input.bdf app-font.ebf --manifest font-subset.manifest --if-needed
```

`--if-needed` leaves an existing output untouched when it is at least as new as
the BDF, manifest, and every referenced character file. This makes the command
suitable for an application build step without forcing the font module to be
rebuilt every time. Fixed labels belong in `chars` or a character file; ranges
should be reserved for genuinely dynamic values such as numbers or user input.

Font modules should retain the upstream font copyright and licence beside the
generated data. The converter does not change or replace the font's licence.

## Graphics and UI libraries

The display contract is intended to support an optional higher-level renderer.
LVGL is the leading candidate for widgets, layout, animation, input devices and
touch. It should be integrated as an adapter above `TDisplay`, not embedded in
individual controller drivers. That keeps tiny applications small and lets the
same LVGL integration work with monochrome, RGB565, and later accelerated or
DMA-backed displays.

U8g2 is also useful as a focused monochrome option because it supports many
controllers and fonts. Its transport callbacks can sit on the same portable
I2C/SPI APIs. Whether to vendor selected U8g2 support or expose it as a separate
optional module should be decided independently from the core display contract.
