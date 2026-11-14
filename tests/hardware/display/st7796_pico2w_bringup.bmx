SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size8x16
Import Embedded.Drivers.Displays.ST7796
Import Embedded.Graphics2D
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const Controller:Int = SPIController0
Const ClockPin:UInt = 18
Const TransmitPin:UInt = 19
Const ChipSelectPin:UInt = 17
Const DataCommandPin:UInt = 16
Const ResetPin:UInt = 20

If Not SPIConfigurePins(Controller, SPIUnavailablePin, TransmitPin, ClockPin) Then ..
	RuntimeError "Unable to configure write-only SPI0"

' Start below the controller's maximum rate while confirming an unknown module.
Local actualRate:UInt = SPIInit(Controller, 12000000)
If actualRate = 0 Then RuntimeError "Unable to initialize SPI0"

Local display:TST7796Display = TST7796Display.Create320x480(Controller, ..
	ChipSelectPin, DataCommandPin, ResetPin, True, True)
If Not display Then RuntimeError "Unable to create ST7796 display"
If Not display.Initialize() Then RuntimeError "Unable to initialize ST7796 display"

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Unable to allocate ST7796 framebuffer"

SetRenderTarget(frame, display)
SetFont(Spleen8x16Font())
SetClsColor(0, 0, 0)
Cls()

Local bandHeight:Int = GraphicsHeight() / 4
SetColor(255, 0, 0)
FillRect(0, 0, GraphicsWidth(), bandHeight)
SetColor(0, 255, 0)
FillRect(0, bandHeight, GraphicsWidth(), bandHeight)
SetColor(0, 0, 255)
FillRect(0, bandHeight * 2, GraphicsWidth(), bandHeight)
SetColor(255, 255, 255)
FillRect(0, bandHeight * 3, GraphicsWidth(), GraphicsHeight() - bandHeight * 3)

SetColor(0, 0, 0)
FillRoundRect(28, 180, GraphicsWidth() - 56, 120, 12)
SetColor(255, 255, 0)
DrawRect(30, 182, GraphicsWidth() - 60, 116)
DrawText("BlitzMax", 96, 214, 2)
DrawText("ST7796", 132, 254)

If Present() <= 0 Then RuntimeError "Unable to present ST7796 framebuffer"

Print "ST7796 320x480 colour bars presented at " + actualRate + " Hz"
While True
	SleepMilliseconds(1000)
Wend
