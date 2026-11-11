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
format used by `TBitmapFont`. An optional hexadecimal range list can retain only
the code points an application needs:

```sh
bdf2embeddedfont input.bdf output.ebf 0020-007e,00a0-00ff
```

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
