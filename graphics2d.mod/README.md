# Embedded.Graphics2D

`Embedded.Graphics2D` is a compact, stateful 2D drawing API for embedded
displays. Its module-level functions deliberately resemble Max2D, while
`TEmbedded2DContext` provides the same operations without global state for
libraries, multiple displays, and independently testable renderers.

Graphics2D draws into an existing `TDisplayBuffer`. It does not own another
framebuffer, start a render thread, or allocate while drawing. The same code can
target monochrome, RGB565, or RGB888 display buffers and can use partial updates
or platform acceleration when the display driver provides them.

## First frame

The board or controller module creates and configures the concrete `TDisplay`.
Once a display is available, its preferred framebuffer and the familiar
module-level API are enough to draw a frame:

```blitzmax
SuperStrict

Import Embedded.Drivers.Display.Fonts.Spleen.Size8x16
Import Embedded.Graphics2D

' The selected board/display driver supplies this object.
Function DrawWelcome(display:TDisplay)
    Local frame:TDisplayBuffer = display.CreateBuffer()
    If Not frame Then RuntimeError "Unable to create the display buffer"

    SetRenderTarget(frame, display)
    SetFont(Spleen8x16Font())

    SetClsColor(8, 14, 24)
    Cls()

    SetColor(40, 180, 255)
    DrawText("Hello, embedded world", 8, 8)
    DrawLine(8, 28, GraphicsWidth() - 9, 28)

    Present()
End Function
```

`GraphicsWidth()` and `GraphicsHeight()` are the current logical drawing
dimensions. They reflect display orientation, drawing rotation, and the current
nested view.

The framebuffer is retained after an ordinary `Present()`: drawing another
shape changes the existing image rather than beginning an implicit new frame.
Call `Cls()` when the next frame should start from the configured clear colour.

## Contexts and global drawing

The module-level functions use one default context. They are convenient for a
small application with one display:

```blitzmax
SetRenderTarget(frame, display)
SetColor(255, 255, 255)
DrawRect(4, 4, 60, 24)
Present()
```

Use an explicit context in a library, when drawing to more than one display or
buffer, or when drawing state must remain isolated:

```blitzmax
Local graphics:TEmbedded2DContext = TEmbedded2DContext.Create(frame, display)
graphics.SetColor(255, 200, 32)
graphics.FillCircle(40, 32, 12)
graphics.Present()
```

The global and context APIs provide the same drawing model. Sprite methods
accept an explicit context; passing `Null` selects the default context.

## Drawing state and primitives

`SetColor()` selects the current 24-bit RGB drawing colour. Components are
clamped to `0..255`. `SetColorValue()` accepts a packed `$RRGGBB` value.
`SetClsColor()` and `SetClsColorValue()` independently configure the colour
used by `Cls()`.

The primitive set comprises:

- `Plot`
- `DrawLine`
- `DrawRect` and `FillRect`
- `DrawRoundRect` and `FillRoundRect`
- `DrawCircle` and `FillCircle`
- `DrawEllipse` and `FillEllipse`
- `DrawTriangle` and `FillTriangle`

All primitives use integer rasterisation. They inherit the current colour,
origin, viewport, view transform, and display rotation:

```blitzmax
SetColor(35, 150, 245)
FillRoundRect(12, 12, 120, 48, 10)

SetColor(255, 220, 60)
DrawCircle(172, 36, 22)
FillTriangle(220, 58, 252, 12, 284, 58)
```

Coordinates are integer pixel coordinates. Rectangle widths and heights are
pixel counts; a rectangle at `(10, 10)` with width `20` covers x coordinates
`10..29`.

### Origin and viewport

`SetOrigin()` adds a translation to subsequent drawing coordinates.
`SetViewport()` clips every primitive, text operation, and image draw to a
rectangle in the current view. `ResetViewport()` restores the complete current
view:

```blitzmax
SetViewport(20, 12, 100, 60)
SetOrigin(20, 12)

' Local coordinate (0, 0) is screen coordinate (20, 12).
FillRect(0, 0, 120, 80) ' Clipped to the viewport.

SetOrigin(0, 0)
ResetViewport()
```

### Saving state

`PushGraphicsState()` saves the font, colours, origin, viewport, drawing
rotation, and current view transform. `PopGraphicsState()` restores them:

```blitzmax
If PushGraphicsState() Then
    SetColor(255, 80, 80)
    SetOrigin(40, 20)
    DrawRect(0, 0, 80, 40)
    PopGraphicsState()
End If
```

The state stack has a fixed maximum of 16 entries. Push and pop return `False`
on overflow or underflow; neither operation allocates.

## Text and bitmap fonts

Graphics2D uses compact EBF1 bitmap fonts from
`Embedded.Drivers.Display.Font`. Importing one concrete font module links only
that font's data into the firmware:

```blitzmax
Import Embedded.Drivers.Display.Fonts.Cozette.Regular6x13

SetFont(Cozette6x13Font())
SetColor(235, 240, 255)
DrawText("Temperature", 8, 8)
```

The bundled catalogue currently includes Anakron, Cozette, Scientifica,
Spleen, Tamzen, and Terminus. Families and sizes are separate modules so an
application pays flash space only for the fonts it imports.

`DrawText()` supports exact integer scaling. Native font sizes generally give
the best appearance; scaling a bitmap font enlarges its source pixels rather
than inventing outline detail:

```blitzmax
DrawText("Native", 8, 8)
DrawText("2x", 8, 28, 2)
```

Use `TextWidth()` and `FontHeight()` for a single line. `TextBoxSize()` measures
word-wrapped text without creating temporary strings, and `DrawTextBox()` draws
wrapped text inside a clipped rectangle:

```blitzmax
Local measuredWidth:Int
Local measuredHeight:Int
Local lines:Int = TextBoxSize(message, 180, measuredWidth, measuredHeight)

DrawTextBox(message, 12, 12, 180, 72, TextAlignCenter, 1, True)
```

Alignment can be `TextAlignLeft`, `TextAlignCenter`, or `TextAlignRight`. The
final argument enables an ellipsis when all the text will not fit vertically.
Explicit newlines are retained.

### Converting another bitmap font

The desktop `tools/bdf2embeddedfont.bmx` utility converts BDF files to EBF1:

```sh
bmk makeapp -r -o bdf2embeddedfont tools/bdf2embeddedfont.bmx
bdf2embeddedfont input.bdf output.ebf --ranges 0020-007e,00a0-00ff
```

`--chars`, `--chars-file`, and manifests can retain only glyphs used by an
application. This can reduce flash use substantially when the complete source
font has broad Unicode coverage. `--fallback` selects the retained glyph used
for missing characters.

## Images

`TEmbeddedImage` reads the firmware-oriented EBI1 format. EBI1 supports Mono1,
RGB565, RGB888, packed indexed colour, optional row compression, and an optional
one-bit transparency mask. The source image decoder and its dependencies remain
desktop-side; firmware contains only the converted pixels and the small drawing
runtime.

Build the converter with a desktop BlitzMax SDK:

```sh
bmk makeapp -r -o image2embedded tools/image2embedded.bmx
image2embedded icon.svg icon.ebi --format auto --mask auto
image2embedded photo.jpg photo.ebi --format rgb565 --mask none
image2embedded panel.png panel.ebi --format indexed4 --compression rle
```

Embed and open the result once, then draw it without frame-time allocation:

```blitzmax
Import Embedded.Drivers.Display.Image
Import Embedded.Graphics2D

Incbin "icon.ebi"

Local icon:TEmbeddedImage = TEmbeddedImage.Create(IncbinPtr("icon.ebi"), ..
    IncbinLen("icon.ebi"))

' White preserves the source colours; other colours tint the image.
SetColor(255, 255, 255)
DrawImage(icon, 8, 8)
DrawImageRect(icon, 48, 8, 32, 32)
DrawImage(icon, 88, 8, ImageFlipX)
DrawImageRect(icon, 128, 8, 32, 32, ImageFlipY, 128)
```

`ImageFlipX` and `ImageFlipY` may be combined with `|`. Opacity is `0..255`.
The optional final argument is a source colour key, tested before tinting.
`DrawImageRegion()` draws an unscaled rectangular portion of an image and is
also the basis of sprite-sheet rendering.

Images are nearest-neighbour scaled. Opaque, unscaled RGB565 paths are normally
the least expensive; blending, tinting, arbitrary scale ratios, masks, and
colour keys require more work. Compatible RGB565 operations automatically use
native or display-driver acceleration when it is available.

## Sprite sheets and animation

`Embedded.Graphics2D.Sprite` defines frames as lightweight views into one
`TEmbeddedImage`. A conventional fixed grid requires only the cell size:

```blitzmax
Import Embedded.Graphics2D.Sprite

Incbin "runner.ebi"

Local pixels:TEmbeddedImage = TEmbeddedImage.Create(IncbinPtr("runner.ebi"), ..
    IncbinLen("runner.ebi"))
Local sheet:TEmbeddedSpriteSheet = TEmbeddedSpriteSheet.CreateGrid(pixels, 16, 16)
Local run:TEmbeddedSpriteAnimation = TEmbeddedSpriteAnimation.CreateRange( ..
    sheet, 0, 6, 80)
Local player:TEmbeddedSpritePlayer = TEmbeddedSpritePlayer.Create(run)

' deltaMilliseconds comes from the application's clock.
player.Advance(deltaMilliseconds)
player.Draw(Null, 64, 32)
```

Animation definitions are immutable and may be shared by many players. Each
player retains only its own clock and playback state. Existing players advance
and draw without allocating.

For separate source frames, the desktop `tools/spriteatlas.bmx` utility uses
`BRL.RectPacker` to produce one atlas image and BlitzMax frame metadata:

```sh
bmk makeapp -r -o spriteatlas tools/spriteatlas.bmx
spriteatlas assets/runner --symbol Runner --page-size 256 --padding 1 \
    --animation run=run0:80,run1:80,run2:80 \
    idle=art/idle.png run0=art/run0.png run1=art/run1.png run2=art/run2.png

image2embedded assets/runner.png assets/runner.ebi \
    --format auto --mask auto --alpha-threshold 1
```

The generated metadata preserves trimmed-frame offsets and logical canvas
sizes, preventing an animation from jumping when transparent borders differ.
Include it after declaring its image dependency:

```blitzmax
Import Embedded.Graphics2D.Sprite
Incbin "assets/runner.ebi"
Include "assets/runner.bmx"

Local sheet:TEmbeddedSpriteSheet = RunnerSpriteSheet()
Local run:TEmbeddedSpriteAnimation = RunnerRunAnimation()
```

## Views and coordinate conversion

`BeginView()` creates a clipped local coordinate system inside the current
view. Views may be nested and may use exact clockwise rotations of 0, 90, 180,
or 270 degrees:

```blitzmax
If BeginView(20, 12, 120, 64) Then
    SetClsColor(12, 20, 32)
    Cls()
    DrawText("Status", 4, 4)

    If BeginView(88, 8, 24, 48, 90) Then
        DrawRect(0, 0, GraphicsWidth(), GraphicsHeight())
        EndView()
    End If

    EndView()
End If
```

Every successful `BeginView()` must have a corresponding `EndView()`.
Beginning a view uses one entry from the same fixed state stack as
`PushGraphicsState()`.

`ViewToScreen()` and `ScreenToView()` convert between the current local view and
the root, orientation-aware screen. `PointInView()` checks the current viewport
and is suitable for hit-testing:

```blitzmax
If PointInView(screenX, screenY) Then
    Local localX:Int
    Local localY:Int
    ScreenToView(screenX, screenY, localX, localY)
End If
```

`GraphicsScreenWidth()` and `GraphicsScreenHeight()` report root screen extents
even while a rotated nested view is active.

## Display orientation and drawing rotation

Display orientation describes how the device is installed. Configure it on the
display before binding the render target, or use `SetDisplayOrientation()` at
runtime. Drawing rotation is relative to that configured orientation:

```blitzmax
display.SetOrientation(90)  ' Portrait is this device's normal orientation.
SetRenderTarget(frame, display)

SetRotation(0)              ' Draw in configured portrait orientation.
SetRotation(180)            ' Draw upside-down relative to portrait.
```

`SetRotation()` accepts only exact quarter turns. `Rotation()` returns the
relative drawing rotation, while `EffectiveRotation()` combines it with device
orientation. Rotation remaps integer coordinates; it needs no trigonometry,
filtering, temporary framebuffer, or frame-time allocation.

If a touch device is present, configure it with the same display orientation so
its coordinates remain aligned.

## Presenting frames

Graphics2D offers three explicit presentation models.

### Coherent full presentation

`Present()` submits the complete framebuffer. Its contents remain valid, so the
next update may change only selected pixels before presenting again. This is the
safest default.

### Dirty-region presentation

Enable tracking once and use `PresentDirty()` for incremental updates:

```blitzmax
SetDirtyTracking(True)

' Redraw both the old and new areas when moving retained content.
SetColor(8, 14, 24)
FillRect(oldX, oldY, spriteWidth, spriteHeight)

SetColor(255, 255, 255)
sheet.Draw(Null, frameIndex, newX, newY)

PresentDirty()
```

Drawing operations automatically add their clipped physical bounds. Changes
made directly to the framebuffer must be declared with `InvalidateRect()` or
`InvalidateAll()`.

The tracker stores at most eight rectangles. Overlapping and adjacent regions
are merged. If the bounded list is exceeded, or dirty coverage becomes large,
it deterministically falls back to a full-screen update. A successful
`PresentDirty()` clears the tracker; a failed transfer retains it for retry.

Dirty presentation reduces transferred pixels, not necessarily drawing work.
Redraw only changed content where practical, while ensuring that every old
pixel which must disappear is also repainted.

### Discard presentation

`PresentDiscard()` permits a capable display driver to return a stale or
undefined render buffer after presentation. It is useful for a full redraw into
swappable or driver-owned buffers:

```blitzmax
Cls()
DrawCompleteScene()
PresentDiscard()
```

After discard presentation, the application must redraw every pixel before the
next presentation. Drivers without an optimized discard path safely fall back
to ordinary presentation.

Single buffering remains the normal baseline. Double buffering, live scanout,
vertical synchronization, and true buffer swapping are display-driver
capabilities rather than requirements imposed by Graphics2D.

## Resource and performance guidance

- Prefer a display's native/preferred buffer format.
- Use a font at its native size where possible; integer scaling is useful but
  draws proportionally more pixels.
- Import only the font modules and assets the application needs.
- Subset broad fonts when the application's character set is known.
- Use Mono1 for monochrome displays, exact indexed images for limited-colour
  artwork, and RGB565 for compact colour imagery.
- Use opaque unscaled images when presentation quality permits; blending and
  scaling cost more.
- Create images, sprite definitions, players, contexts, and framebuffers during
  setup rather than inside the frame loop.
- Use dirty presentation for small retained updates and coherent or discard
  full frames for animation which changes most of the display.
- Keep nested views/state depth below the fixed 16-entry limit.
- Check the Boolean or display-status result of bounded and presentation
  operations when recovery matters.

Drawing, text layout, dirty tracking, state changes, views, sprite advancement,
and rendering are designed to allocate no managed memory in steady state.
Asset pixels embedded with `Incbin` live in firmware; framebuffer memory remains
the principal RAM cost.

## Scope

Graphics2D is an embedded raster API, not a reduced desktop GPU API. It
deliberately favours deterministic integer work, bounded storage, exact
quarter-turn transforms, bitmap fonts, and explicit presentation over arbitrary
affine transforms, outline-font rasterisation, shaders, or hidden frame queues.

Applications needing retained layouts and widgets can build on this layer via
[`Embedded.UI`](../ui.mod/README.md). Applications needing only a few shapes,
text, images, or sprites can use Graphics2D directly without linking the UI.

The executable conformance coverage is in:

- [`embedded_graphics2d_conformance.bmx`](../tests/embedded_graphics2d_conformance.bmx)
- [`embedded_display_image_conformance.bmx`](../tests/embedded_display_image_conformance.bmx)
- [`embedded_display_font_conformance.bmx`](../tests/embedded_display_font_conformance.bmx)
- [`embedded_sprite_conformance.bmx`](../tests/embedded_sprite_conformance.bmx)

