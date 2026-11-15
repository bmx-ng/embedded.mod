SuperStrict

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

Const StageX:Int = 6
Const StageY:Int = 30
Const StageWidth:Int = 116
Const StageHeight:Int = 84

If Not SPIConfigurePins(Controller, ReceivePin, TransmitPin, ClockPin) Then ..
	RuntimeError "Unable to configure write-only SPI0"
If SPIInit(Controller, 8000000) = 0 Then RuntimeError "Unable to initialize SPI0"

Local display:TSH1107Display = TSH1107Display.Create128x128(Controller, ..
	ChipSelectPin, DataCommandPin)
If Not display Or Not display.Initialize() Then RuntimeError "Unable to initialize SH1107"

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Unable to allocate SH1107 framebuffer"

SetRenderTarget(frame, display)
SetClsColor(0, 0, 0)
Cls()

SetColor(255, 255, 255)
FillRoundRect(3, 3, 122, 23, 5)
SetColor(0, 0, 0)
SetFont(Spleen8x16Font())
DrawText("Graphics2D", 24, 6)

SetColor(255, 255, 255)
DrawRoundRect(StageX, StageY, StageWidth, StageHeight, 6)
SetFont(Spleen5x8Font())
DrawText("SH1107 | dirty pages", 13, 118)
If Present() <= 0 Then RuntimeError "Unable to present initial SH1107 frame"

SetDirtyTracking(True)

Local ballX:Int = 18
Local ballY:Int = 20
Local velocityX:Int = 2
Local velocityY:Int = 1

While True
	If BeginView(StageX + 2, StageY + 2, StageWidth - 4, StageHeight - 4) Then
		SetClsColor(0, 0, 0)
		Cls()

		SetColor(255, 255, 255)
		For Local gridX:Int = 8 Until GraphicsWidth() Step 16
			For Local gridY:Int = 8 Until GraphicsHeight() Step 16
				Plot(gridX, gridY)
			Next
		Next

		FillCircle(ballX, ballY, 6)
		SetColor(0, 0, 0)
		FillCircle(ballX - 2, ballY - 2, 2)

		SetColor(255, 255, 255)
		FillTriangle(GraphicsWidth() - 27, 9, GraphicsWidth() - 10, 18, ..
			GraphicsWidth() - 27, 27)
		DrawRoundRect(9, GraphicsHeight() - 20, 37, 13, 3)
		SetFont(Spleen5x8Font())
		DrawText("PICO 2", 13, GraphicsHeight() - 17)
		EndView()
	End If

	If PresentDirty() <= 0 Then RuntimeError "Unable to present SH1107 animation region"

	ballX :+ velocityX
	ballY :+ velocityY
	If ballX <= 7 Or ballX >= StageWidth - 15 Then velocityX = -velocityX
	If ballY <= 7 Or ballY >= StageHeight - 15 Then velocityY = -velocityY

	SleepMilliseconds(16)
Wend
