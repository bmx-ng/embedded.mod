# Embedded device drivers

`Embedded.Drivers.*` contains portable drivers for devices attached to the
shared embedded hardware APIs. A controller driver belongs here when it can use
the same public API and behaviour on Pico, ESP32, nRF52, ESP8266, and future
embedded targets where the hardware and resources permit it. Board profiles
remain target-owned and describe how a particular board wires those devices.

This guide covers the portable driver boundary, supported display controllers,
touch input, and the asset conversion pipeline. For drawing primitives, views,
rotation, presentation strategies, and sprites, see the
[Graphics2D guide](../graphics2d.mod/README.md). For retained layouts, controls,
dashboards, navigation, and touch interaction, see the
[Embedded.UI guide](../ui.mod/README.md).

## Start here

Choose the smallest layer that meets the application's needs:

| Need | Import |
| --- | --- |
| Own a framebuffer and present it to a controller | `Embedded.Drivers.Display` plus one `Embedded.Drivers.Displays.*` module |
| Draw shapes, text, images, and sprites | `Embedded.Graphics2D` |
| Build dashboards or interactive controls | `Embedded.UI`, with `Embedded.UI.Interactive` when input is required |
| Receive portable touch events | `Embedded.Drivers.Touch` plus a target-specific touch controller |

A typical display application performs four steps:

1. configure the portable I2C or SPI controller and its pins;
2. create and initialize the matching display driver;
3. create a framebuffer and bind it to Graphics2D; and
4. draw and present either the complete frame or its dirty regions.

The application chooses pins and bus speed. A controller name alone does not
identify a complete module: panels using the same controller can differ in
visible dimensions, RAM offsets, component order, inversion, and safe transfer
rate. Begin conservatively and record verified settings in a board profile or
application configuration.

## Driver catalogue

| Module | Bus | Native raster | Included configuration |
| --- | --- | --- | --- |
| `Embedded.Drivers.Displays.SSD1306` | I2C | Mono1, up to 128x64 | Configurable window and 72x40 OLED preset |
| `Embedded.Drivers.Displays.SH1107` | SPI | Mono1, up to 128x128 | Configurable window and 128x128 preset |
| `Embedded.Drivers.Displays.ST7735` | SPI | RGB565 | Configurable window and 128x160 preset |
| `Embedded.Drivers.Displays.ST7789` | SPI | RGB565 | Configurable window and 240x320 preset |
| `Embedded.Drivers.Displays.ST7796` | SPI | RGB565 | Configurable window and 320x480 preset |
| `Embedded.Drivers.Displays.ILI9341` | SPI | RGB565 | 240x320 panel |

All concrete drivers implement `TDisplay`, so Graphics2D and UI code remains
independent of the controller. Controller modules are linked only when imported.

## Display architecture

`Embedded.Drivers.Display` defines the stable raster and presentation boundary:

- `TDisplayBuffer` owns a Mono1, RGB565, or RGB888 raster, or wraps a
  driver-owned external framebuffer without copying it;
- `TDisplay` reports dimensions, preferred format, orientation, capabilities,
  and full or partial presentation operations;
- `PresentPixels` accepts an external raster pointer for renderers which do not
  own the controller driver; and
- `PresentRegions` submits multiple dirty rectangles while allowing a driver
  to preserve an atomic framebuffer transition.

Mono1 rows run top-to-bottom and are most-significant-bit first. RGB565 is
little-endian; RGB888 is red, green, blue. Controller drivers convert this
stable representation to their wire format.

The base layer is useful without Graphics2D: a small status application can own
one buffer, modify its pixels directly, and present it. Higher layers do not
allocate a second framebuffer. Display capabilities distinguish partial
presentation, live scanout buffers, vertical synchronization, true buffer
swapping, discard presentation, accelerated fills, and accelerated blits.

Orientation belongs to the display configuration. `SetOrientation` defines
which physical edge is logical rotation zero; Graphics2D can then apply a
separate relative drawing rotation. Set the same orientation on the touch
device so displayed and reported coordinates agree.

## Display controller drivers

### SSD1306 I2C monochrome displays

`Embedded.Drivers.Displays.SSD1306` uses `Embedded.Hardware.I2C`, presents only
the affected display pages, and supports configurable visible dimensions and
RAM offsets. `Create72x40()` supplies the offsets and analogue settings used by
common EastRising-compatible 0.42-inch OLED modules. The general `Create()`
constructor supports panels up to 128x64.

Initialize and select the I2C controller before creating the driver. The
application remains responsible for SDA/SCL pin routing, bus speed, and the
panel's seven-bit address.

### ST7735 SPI colour displays

`Embedded.Drivers.Displays.ST7735` drives ST7735-compatible colour TFT panels
through the portable SPI and GPIO APIs. It accepts the shared little-endian
RGB565 framebuffer, sends controller pixels most-significant byte first, and
supports complete or dirty-region presentation without allocating a second
framebuffer. The application owns SPI setup so the same display can share a bus
with other peripherals.

For example, a write-only SPI0 connection on a Pico 2 W can use GP18 for SCK,
GP19 for MOSI, GP17 for chip-select, GP16 for data/command, and GP20 for reset:

| Display signal | Pico 2 W pin in this example |
| --- | --- |
| SCK/CLK | GP18 |
| MOSI/SDA | GP19 |
| CS | GP17 |
| D/C or A0 | GP16 |
| RESET/RES | GP20 |
| MISO | Not connected for display-only use |

Power, ground, and backlight wiring depend on the complete display module and
are not controller GPIO signals.

```blitzmax
Import Embedded.Drivers.Displays.ST7735
Import Embedded.Hardware.SPI
Import Embedded.Graphics2D

Const Controller:Int = SPIController0

' No MISO wire is required by this write-only display.
If Not SPIConfigurePins(Controller, SPIUnavailablePin, 19, 18) Then ..
    RuntimeError "Unable to configure SPI0"
If SPIInit(Controller, 20000000) = 0 Then ..
    RuntimeError "Unable to initialize SPI0"

Local display:TST7735Display = TST7735Display.Create128x160(Controller, ..
    17, 16, 20, False, True)
If Not display Or Not display.Initialize() Then ..
    RuntimeError "Unable to initialize ST7735"

Local frame:TDisplayBuffer = display.CreateBuffer()
SetRenderTarget(frame, display)
SetClsColor 8, 16, 28
Cls
SetColor 255, 210, 40
FillRect 8, 8, 48, 24
Present
```

The final two Boolean arguments select BGR component order and display
inversion. ST7735 modules with the same visible dimensions are sold with
different panel wiring, so these are panel properties rather than assumptions
made by Graphics2D. The example selects RGB ordering and inverted drive, as
required by the tested generic 128x160 module. A module showing cyan instead of
red needs the other component order; a module showing photographic-negative
colours needs the other inversion setting.

`TST7735Display.Create()` also accepts arbitrary visible width and height,
column and row RAM offsets, component order, inversion, and initial orientation.
This covers smaller ST7735 panels whose visible raster occupies an offset
window in the controller's 132x162 RAM. The common `Create128x160()` helper uses
zero offsets.

Chip-select, data/command, and reset are configured as output GPIOs by
`Initialize()`. Backlight control is deliberately separate: connect a
current-limited module backlight to 3.3 V for always-on use, or control an
appropriate backlight input/transistor through GPIO or PWM.

### ST7789 SPI colour displays

`Embedded.Drivers.Displays.ST7789` supports ST7789-compatible colour panels
through the same RGB565 and dirty-region contracts. `Create240x320()` describes
the controller's native portrait raster; setting display orientation to 90 or
270 degrees exposes a logical 320x240 landscape surface to Graphics2D.

The tested generic eight-pin module uses RGB component order and inverted
display drive:

```blitzmax
Import Embedded.Drivers.Displays.ST7789
Import Embedded.Hardware.SPI

Const Controller:Int = SPIController0
If Not SPIConfigurePins(Controller, SPIUnavailablePin, 19, 18) Then ..
    RuntimeError "Unable to configure SPI0"
If SPIInit(Controller, 12000000) = 0 Then ..
    RuntimeError "Unable to initialize SPI0"

Local display:TST7789Display = TST7789Display.Create240x320(Controller, ..
    17, 16, 20, False, True)
If Not display Or Not display.Initialize() Then ..
    RuntimeError "Unable to initialize ST7789"
```

The SPI controller and every GPIO remain application choices. `Create()` also
accepts smaller visible rasters and controller-RAM offsets for ST7789 modules
whose panels expose only part of the 240x320 address space. A full-size RGB565
framebuffer occupies 153,600 bytes.

The Pico 2 W landscape example configures orientation 90, producing a logical
320x240 Graphics2D view over the native portrait framebuffer. Its bouncing-ball
animation presents only the old and new sprite rectangles and sustains 49
frames per second on the tested module at 12 MHz SPI.

### ST7796 SPI colour displays

`Embedded.Drivers.Displays.ST7796` provides the same portable RGB565 and
dirty-region contract for ST7796-compatible 320x480 panels. The SPI controller,
clock and data pins, and all three control pins remain application choices; the
Pico 2 W bring-up test merely uses SPI0 SCK GP18, MOSI GP19, CS GP17, D/C GP16,
and reset GP20 as one known arrangement.

```blitzmax
Import Embedded.Drivers.Displays.ST7796
Import Embedded.Hardware.SPI

Const Controller:Int = SPIController0
If Not SPIConfigurePins(Controller, SPIUnavailablePin, 19, 18) Then ..
    RuntimeError "Unable to configure SPI0"
If SPIInit(Controller, 12000000) = 0 Then ..
    RuntimeError "Unable to initialize SPI0"

Local display:TST7796Display = TST7796Display.Create320x480(Controller, ..
    17, 16, 20, True, True)
If Not display Or Not display.Initialize() Then ..
    RuntimeError "Unable to initialize ST7796"
```

A complete RGB565 framebuffer occupies 307,200 bytes. This is practical on a
Pico 2 for simple applications, but leaves substantially less managed heap than
the 128x160 ST7735. Applications should avoid unnecessary frame-sized images
and use dirty-region presentation where possible. The driver itself allocates
only a small transfer buffer in addition to the application framebuffer.
The final two Boolean values in the example select BGR component order and
inverted display drive, as required by the tested generic eight-pin module;
other ST7796 panels may require different values.

The Pico 2 W hardware examples include a full-panel colour-bar diagnostic and
a Graphics2D animation. The animation keeps a complete framebuffer but presents
only the previous and current sprite rectangles, clipping foreground
recomposition to that same area. The tested Pico 2 W and generic eight-pin
panel sustain approximately 46-48 frames per second at 12 MHz with that method.
SPI limits are properties of the complete controller board, wiring, and panel
combination rather than the ST7796 controller alone, so initial bring-up should
use a conservative rate and secure, short connections.

### ILI9341 SPI colour displays

`Embedded.Drivers.Displays.ILI9341` drives the common 240x320 RGB565 panel.
Its constructor accepts the initialized SPI controller, chip-select,
data/command and reset GPIOs, component order, inversion, and initial
orientation. As with the ST drivers, the application owns SPI pin routing and
clock selection, and no MISO connection is required for display-only use.

The same portable driver has been validated on Pico and ESP32-S3. Modules which
also carry an XPT2046 touch controller or SD-card slot expose those as separate
SPI devices with their own chip-select lines; importing the display driver does
not claim or configure them.

### SH1107 SPI monochrome displays

`Embedded.Drivers.Displays.SH1107` presents Mono1 buffers to SH1107-compatible
panels. `Create128x128()` covers the common full-size OLED, while `Create()`
accepts smaller visible windows and controller-RAM offsets. Reset is optional
when the module does not expose it. Dirty updates are expanded to the
controller's eight-pixel page boundaries.

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

Touch controller adapters whose SDK or bus integration is target-specific live
in the target repository. For example, `ESP32.Drivers.Touch.GT1151` implements
this contract for supported ESP32 RGB display boards.

## Assets and conversion tools

Display assets are converted on the desktop and embedded as compact,
validated data. Firmware does not link PNG, JPEG, SVG, BDF, or other desktop
decoders.

| Tool | Input | Output | Runtime module |
| --- | --- | --- | --- |
| `tools/image2embedded.bmx` | Images supported by `image.mod` | EBI1 image | `Embedded.Drivers.Display.Image` |
| `tools/spriteatlas.bmx` | Named image frames | Atlas PNG and BlitzMax metadata | `Embedded.Graphics2D.Sprite` |
| `tools/bdf2embeddedfont.bmx` | BDF bitmap font | EBF1 font | `Embedded.Drivers.Display.Font` |

### Images and bitmaps

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
image2embedded panel.png panel.ebi --format indexed4 --compression rle
```

`--threshold` controls monochrome conversion, `--alpha-threshold` controls the
one-bit transparency decision, and `--mask auto|always|none` controls whether a
mask is emitted. `auto` only adds one when the source contains transparency.
The `auto` pixel format chooses the smallest exact indexed representation for
images containing no more than 256 colours, otherwise it falls back to RGB565.
An explicit indexed format requires the source to fit its 2-, 4-, 16-, or
256-colour capacity and reports an error rather than silently quantising it.
`--compression auto|none|rle` controls indexed row compression. The default
`auto` writes RLE only when its row table and runs are smaller than the packed
pixels. Each compressed row has an independent validated offset, and every run
stores a length from 1 through 256 plus one palette index. Clipping, scaling,
and mirroring traverse those runs directly without an expanded row buffer.
RLE is deliberately unavailable for Mono1, RGB565, and RGB888: their packed or
native representation remains more predictable for arbitrary photographic
data.
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

### Sprite sheets and animation

`Embedded.Graphics2D.Sprite` treats frames as lightweight views into one
`TEmbeddedImage`. A regular grid is enough for conventional sprite strips:

```blitzmax
Import Embedded.Graphics2D.Sprite

Incbin "runner.ebi"

Local pixels:TEmbeddedImage = TEmbeddedImage.Create(IncbinPtr("runner.ebi"), ..
    IncbinLen("runner.ebi"))
Local sheet:TEmbeddedSpriteSheet = TEmbeddedSpriteSheet.CreateGrid(pixels, 16, 16)
Local run:TEmbeddedSpriteAnimation = TEmbeddedSpriteAnimation.CreateRange(sheet, 0, 6, 80)
Local player:TEmbeddedSpritePlayer = TEmbeddedSpritePlayer.Create(run)

' Supply elapsed milliseconds from the application clock each update.
player.Advance(deltaMilliseconds)
player.Draw(Null, 64, 32)
```

Passing `Null` uses the module-level `Embedded.Graphics2D` context; libraries
with their own context can pass it explicitly. Coordinates identify a frame's
handle, matching the familiar image convention. Grid sheets support a first
cell, cell count, outer margin, inter-cell spacing, and a common handle.

Arbitrary sheets use `TEmbeddedSpriteFrame` rectangles. Each rectangle may
retain an offset within a larger logical canvas, so an offline atlas builder can
remove transparent borders without making an animation jump. Animation
definitions contain immutable frame order and positive per-frame durations.
Players contain only their independent clock, loop/one-shot state, and playback
flags; many actors can therefore share the same sheet and animation. Advancing
and drawing an existing player allocate no memory.

Sprite pixels retain every EBI1 facility: exact indexed palettes, optional row
RLE, transparency masks, colour keys, tinting, opacity, clipping and mirroring.
Rectangle packing belongs in the desktop conversion tool rather than firmware;
the embedded runtime only consumes the resulting frame rectangles.

The desktop `tools/spriteatlas.bmx` utility uses `BRL.RectPacker` to build one
deterministic atlas page from separately named source images. For example:

```sh
spriteatlas assets/runner --symbol Runner --page-size 256 --padding 1 \
    --animation run=run0:80,run1:80,run2:80 \
    idle=art/idle.png run0=art/run0.png run1=art/run1.png run2=art/run2.png

image2embedded assets/runner.png assets/runner.ebi \
    --format auto --mask auto --alpha-threshold 1
```

The first command writes `runner.png` and `runner.bmx`. The PNG is an
inspectable intermediate; the ordinary image converter remains the only EBI1
writer and therefore retains its exact palette, mask, and compression rules.
Use the alpha-threshold printed by `spriteatlas` in the second command so
trimming and the final one-bit visibility mask agree.

The generated metadata is included by the application. Its dependencies and
embedded data are declared explicitly so `bmk` can discover them before the
embedded compiler pass:

```blitzmax
Import Embedded.Graphics2D.Sprite
Incbin "assets/runner.ebi"
Include "assets/runner.bmx"

Local sheet:TEmbeddedSpriteSheet = RunnerSpriteSheet()
Local run:TEmbeddedSpriteAnimation = RunnerRunAnimation()
Local player:TEmbeddedSpritePlayer = TEmbeddedSpritePlayer.Create(run)
```

Frame constants such as `RunnerFrameIdle` are emitted in command-line order.
The packer never rotates frames. Transparent borders are trimmed by default,
but their offsets and original canvas dimensions are retained, preventing
visible animation jitter. Fully transparent frames use a masked 1x1 placeholder.
`--trim false` preserves every source pixel. An atlas that cannot fit the one
configured page fails rather than silently dropping a frame; increase
`--page-size` or divide unrelated assets into separate atlases.

### Bitmap fonts and text

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

## Related guides

- [Embedded.Graphics2D](../graphics2d.mod/README.md) documents the complete
  drawing API, fonts, images, sprites, views, rotation, dirty presentation, and
  performance guidance.
- [Embedded.UI](../ui.mod/README.md) documents display-only dashboards,
  retained layout, controls, navigation, notifications, themes, and optional
  interaction.
- The [embedded module overview](../README.md) explains the portable-versus-
  target-specific boundary and links to the hardware buses used by drivers.

External libraries such as LVGL or U8g2 can still be adapted above `TDisplay`
and the portable I2C/SPI APIs. They are optional alternatives, not required by
the built-in Graphics2D and UI layers.
