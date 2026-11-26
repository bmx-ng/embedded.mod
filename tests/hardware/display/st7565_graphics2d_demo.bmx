SuperStrict

Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Drivers.Displays.ST7565
Import Embedded.Graphics2D
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const Controller:Int = SPIController0
If Not SPIConfigurePins(Controller, 23, 19, 18) Then RuntimeError "SPI pins"
If Not SPIInit(Controller, 4000000) Then RuntimeError "SPI init"

Local display:TST7565Display = TST7565Display.Create128x64(Controller, 22, 21, 20)
If Not display Or Not display.Initialize() Then RuntimeError "ST7565 init"
Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Framebuffer allocation"
SetRenderTarget(frame, display)
SetClsColor(0, 0, 0)
Cls()
SetFont(Spleen5x8Font())
SetColor(255, 255, 255)
DrawText("Graphics2D | ST7565", 14, 2)
DrawRoundRect(1, 12, 126, 51, 4)
If Present() <= 0 Then RuntimeError "Initial presentation"
SetDirtyTracking(True)

Local ballX:Int = 18
Local ballY:Int = 20
Local velocityX:Int = 2
Local velocityY:Int = 1
While True
	If BeginView(4, 15, 120, 45) Then
		Cls()
		SetColor(255, 255, 255)
		FillCircle(ballX, ballY, 5)
		SetColor(0, 0, 0)
		FillCircle(ballX - 1, ballY - 1, 2)
		SetColor(255, 255, 255)
		DrawText("C6", 99, 33)
		EndView()
	End If
	If PresentDirty() <= 0 Then RuntimeError "Dirty presentation"
	ballX :+ velocityX
	ballY :+ velocityY
	If ballX <= 6 Or ballX >= 113 Then velocityX = -velocityX
	If ballY <= 6 Or ballY >= 38 Then velocityY = -velocityY
	SleepMilliseconds(16)
Wend
