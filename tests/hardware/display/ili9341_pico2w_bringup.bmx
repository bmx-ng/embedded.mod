SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size8x16
Import Embedded.Drivers.Displays.ILI9341
Import Embedded.Graphics2D
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const Controller:Int = SPIController0
Const ReceivePin:UInt = 16
Const TransmitPin:UInt = 19
Const ClockPin:UInt = 18
Const ChipSelectPin:UInt = 17
Const DataCommandPin:UInt = 15
Const ResetPin:UInt = 20

If Not SPIConfigurePins(Controller, ReceivePin, TransmitPin, ClockPin) Then ..
	RuntimeError "Unable to configure SPI0"
Local actualRate:UInt = SPIInit(Controller, 12000000)
If actualRate = 0 Then RuntimeError "Unable to initialize SPI0"

Local display:TILI9341Display = TILI9341Display.Create(Controller, ..
	ChipSelectPin, DataCommandPin, ResetPin, True, False, DisplayOrientation0)
If Not display Or Not display.Initialize() Then RuntimeError "Unable to initialize ILI9341"

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Unable to allocate ILI9341 framebuffer"

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
FillRoundRect(20, 110, GraphicsWidth() - 40, 100, 10)
SetColor(255, 255, 0)
DrawRect(22, 112, GraphicsWidth() - 44, 96)
DrawText("BlitzMax", 56, 134, 2)
DrawText("ILI9341", 92, 178)

If Present() <= 0 Then RuntimeError "Unable to present ILI9341 framebuffer"
Print "ILI9341 240x320 colour bars presented at " + actualRate + " Hz"
While True
	SleepMilliseconds(1000)
Wend
