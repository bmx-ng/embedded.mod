# Embedded device drivers

`Embedded.Drivers.*` contains portable drivers for devices attached to the
shared embedded hardware APIs. A controller driver belongs here when it can use
the same public API and behaviour on Pico, ESP32, ESP8266, and future embedded
targets. Board profiles remain target-owned and describe how a particular board
wires those devices.

## Displays

`Embedded.Drivers.Display` defines the common raster and presentation boundary:

- `TDisplayBuffer` owns a compact Mono1, RGB565, or RGB888 raster;
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
It provides `Cls`, `SetColor`, `SetFont`, `DrawText`, `Plot`, `DrawLine`,
`DrawRect`, `FillRect`, origins, viewports, text metrics, and `Present`. The
global functions use one default context for compact applications;
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

Concrete display drivers live beneath `Embedded.Drivers.Displays.*`.
`Embedded.Drivers.Displays.SSD1306` is the first controller implementation. It uses
`Embedded.Hardware.I2C`, supports dirty page updates, and includes the 72x40
EastRising-compatible preset used by common 0.42-inch OLED boards.

## Bitmap fonts and text

`Embedded.Drivers.Display.Font` renders compact, Unicode-addressed bitmap fonts
into any `TDisplayBuffer`. Rendering and measurement perform no allocation, and
integer pixel scaling reuses the original glyph data. Text coordinates specify
the top-left of the first line rather than a controller-specific baseline.

`Embedded.Drivers.Display.Fonts.Spleen5x8` provides the complete 472-glyph
Spleen 5x8 font under its BSD 2-Clause licence. Importing the module links its
11,360-byte font image; applications which do not import it pay no font cost.

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
