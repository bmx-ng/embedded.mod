SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Displays.ST7567A
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Graphics2D
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const Controller:Int = SPIController0
If Not SPIConfigurePins(Controller, 23, 19, 18) Then RuntimeError "SPI pins"
If Not SPIInit(Controller, 1000000) Then RuntimeError "SPI init"

Local display:TST7567ADisplay = TST7567ADisplay.Create128x64(Controller, 22, 21, 20)
If Not display Or Not display.Initialize() Then RuntimeError "ST7567A init"
Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Framebuffer allocation"
SetRenderTarget(frame, display)
SetClsColor(0, 0, 0)
Cls()
SetColor(255, 255, 255)
DrawRect(0, 0, 128, 64)
DrawLine(0, 0, 127, 63)
DrawLine(127, 0, 0, 63)
SetColor(0, 0, 0)
FillRect(18, 16, 92, 32)
SetColor(255, 255, 255)
DrawRect(18, 16, 92, 32)
SetFont(Spleen5x8Font())
DrawText("BlitzMax", 44, 22)
DrawText("ST7567A 128x64", 29, 35)
If Present() <= 0 Then RuntimeError "ST7567A present"
While True
	Print "ST7567A diagnostic presented"
	SleepMilliseconds(1000)
Wend
