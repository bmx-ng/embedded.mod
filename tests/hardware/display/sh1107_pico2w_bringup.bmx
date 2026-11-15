SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Drivers.Display.Fonts.Spleen.Size8x16
Import Embedded.Drivers.Displays.SH1107
Import Embedded.Graphics2D
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const Controller:Int = SPIController0
Const ClockPin:UInt = 18
Const TransmitPin:UInt = 19
Const ReceivePin:UInt = SPIUnavailablePin
Const ChipSelectPin:UInt = 17
Const DataCommandPin:UInt = 16

If Not SPIConfigurePins(Controller, ReceivePin, TransmitPin, ClockPin) Then ..
	RuntimeError "Unable to configure write-only SPI0"
Local actualRate:UInt = SPIInit(Controller, 8000000)
If actualRate = 0 Then RuntimeError "Unable to initialize SPI0"

Local display:TSH1107Display = TSH1107Display.Create128x128(Controller, ..
	ChipSelectPin, DataCommandPin)
If Not display Or Not display.Initialize() Then RuntimeError "Unable to initialize SH1107"

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Unable to allocate SH1107 framebuffer"

SetRenderTarget(frame, display)
SetClsColor(0, 0, 0)
Cls()

SetColor(255, 255, 255)
DrawRect(0, 0, GraphicsWidth(), GraphicsHeight())
DrawRect(3, 3, GraphicsWidth() - 6, GraphicsHeight() - 6)
DrawLine(4, 4, GraphicsWidth() - 5, GraphicsHeight() - 5)
DrawLine(GraphicsWidth() - 5, 4, 4, GraphicsHeight() - 5)

SetColor(0, 0, 0)
FillRoundRect(13, 35, 102, 58, 7)
SetColor(255, 255, 255)
DrawRoundRect(13, 35, 102, 58, 7)
SetFont(Spleen8x16Font())
DrawText("BlitzMax", 32, 45)
SetFont(Spleen5x8Font())
DrawText("SH1107 128x128", 27, 69)
DrawText("SPI0 " + (actualRate / 1000000) + " MHz", 39, 80)

FillRect(8, 105, 8, 8)
FillRect(24, 105, 8, 8)
FillRect(40, 105, 8, 8)
FillRect(56, 105, 8, 8)
FillRect(72, 105, 8, 8)
FillRect(88, 105, 8, 8)
FillRect(104, 105, 8, 8)

If Present() <= 0 Then RuntimeError "Unable to present SH1107 framebuffer"

Print "SH1107 128x128 diagnostic presented at " + actualRate + " Hz"
While True
	SleepMilliseconds(1000)
Wend
