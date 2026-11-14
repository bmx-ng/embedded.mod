SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size8x16
Import Embedded.Drivers.Displays.ST7735
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

Local actualRate:UInt = SPIInit(Controller, 20000000)
If actualRate = 0 Then RuntimeError "Unable to initialize SPI0"

Local display:TST7735Display = TST7735Display.Create128x160(Controller, ..
	ChipSelectPin, DataCommandPin, ResetPin, False, True)
If Not display Then RuntimeError "Unable to create ST7735 display"
If Not display.Initialize() Then RuntimeError "Unable to initialize ST7735 display"

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Unable to allocate ST7735 framebuffer"

SetRenderTarget(frame, display)
SetFont(Spleen8x16Font())
SetClsColor(0, 0, 0)
Cls()

Local bandWidth:Int = GraphicsWidth() / 4
SetColor(255, 0, 0)
FillRect(0, 0, bandWidth, GraphicsHeight())
SetColor(0, 255, 0)
FillRect(bandWidth, 0, bandWidth, GraphicsHeight())
SetColor(0, 0, 255)
FillRect(bandWidth * 2, 0, bandWidth, GraphicsHeight())
SetColor(255, 255, 255)
FillRect(bandWidth * 3, 0, GraphicsWidth() - bandWidth * 3, GraphicsHeight())

SetColor(0, 0, 0)
FillRoundRect(7, 55, GraphicsWidth() - 14, 50, 6)
SetColor(255, 255, 0)
DrawRect(8, 56, GraphicsWidth() - 16, 48)
DrawText("BlitzMax", 32, 66)
DrawText("ST7735", 36, 84)

If Present() <= 0 Then RuntimeError "Unable to present ST7735 framebuffer"

Print "ST7735 128x160 colour bars presented at " + actualRate + " Hz"
While True
	SleepMilliseconds(1000)
Wend
