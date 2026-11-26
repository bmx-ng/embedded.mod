SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Displays.CH1116
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Graphics2D
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const Controller:Int = SPIController0
' GPIO23 is an unused SPI receive input on this ESP32 adapter.
If Not SPIConfigurePins(Controller, 23, 19, 18) Then RuntimeError "SPI pins"
If Not SPIInit(Controller, 1000000) Then RuntimeError "SPI init"

Local display:TCH1116Display = TCH1116Display.Create128x64(Controller, 22, 21, 20)
If Not display Or Not display.Initialize() Then RuntimeError "CH1116 init"
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
DrawText("CH1116 128x64", 31, 35)
If Present() <= 0 Then RuntimeError "CH1116 present"
While True
	Print "CH1116 all pixels"
	display.SetAllPixels(True)
	SleepMilliseconds(3000)
	display.SetAllPixels(False)
	Print "CH1116 graphics"
	SleepMilliseconds(5000)
Wend
