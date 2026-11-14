SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Drivers.Display.Fonts.Spleen.Size8x16
Import Embedded.Drivers.Displays.ST7735
Import Embedded.Graphics2D
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const Controller:Int = SPIController0
?pico
Const ClockPin:UInt = 18
Const TransmitPin:UInt = 19
Const ReceivePin:UInt = SPIUnavailablePin
Const ChipSelectPin:UInt = 17
Const DataCommandPin:UInt = 16
Const ResetPin:UInt = 20
?nrf52
' Tenstar Robot ProMicro nRF52840 / nice!nano v2 header route.
' SCK D3/P0.20, MOSI D2/P0.17, CS D4/P0.22,
' D/C D6/P1.00, RESET D8/P1.04. MISO D14/P1.11 is not wired.
Const ClockPin:UInt = 20
Const TransmitPin:UInt = 17
Const ReceivePin:UInt = 43
Const ChipSelectPin:UInt = 22
Const DataCommandPin:UInt = 32
Const ResetPin:UInt = 36
?

Const StageX:Int = 6
Const StageY:Int = 31
Const StageWidth:Int = 116
Const StageHeight:Int = 103
Const StageColor:UInt = $08101c

If Not SPIConfigurePins(Controller, ReceivePin, TransmitPin, ClockPin) Then ..
	RuntimeError "Unable to configure write-only SPI0"
?nrf52
Local requestedRate:UInt = 8000000
?Not nrf52
Local requestedRate:UInt = 20000000
?
Local actualRate:UInt = SPIInit(Controller, requestedRate)
If actualRate = 0 Then RuntimeError "Unable to initialize SPI0"

Local display:TST7735Display = TST7735Display.Create128x160(Controller, ..
	ChipSelectPin, DataCommandPin, ResetPin, False, True)
If Not display Or Not display.Initialize() Then RuntimeError "Unable to initialize ST7735"

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Unable to allocate ST7735 framebuffer"

SetRenderTarget(frame, display)
SetClsColorValue($02050a)
Cls()

' Static chrome remains untouched while only the animation stage is presented.
SetColorValue($16c7e8)
FillRoundRect(4, 3, 120, 23, 6)
SetColorValue($001018)
SetFont(Spleen8x16Font())
DrawText("Graphics2D", 24, 6)

SetColorValue($334a68)
FillRoundRect(StageX, StageY, StageWidth, StageHeight, 8)
SetColorValue(StageColor)
FillRoundRect(StageX + 2, StageY + 2, StageWidth - 4, StageHeight - 4, 6)

SetFont(Spleen5x8Font())
SetColorValue($9db2cc)
?nrf52
DrawText("SPI0 8 MHz | dirty region", 4, 148)
?Not nrf52
DrawText("SPI0 20 MHz  |  dirty region", 4, 148)
?
If Present() <= 0 Then RuntimeError "Unable to present initial frame"

SetDirtyTracking(True)

Local ballX:Int = 24
Local ballY:Int = 58
Local velocityX:Int = 2
Local velocityY:Int = 1
Local frameCount:Int
Local reportStart:ULong = MonotonicMilliseconds()

While True
	' Repaint one bounded view. The header and footer are not redrawn or sent.
	If BeginView(StageX + 2, StageY + 2, StageWidth - 4, StageHeight - 4) Then
		SetClsColorValue(StageColor)
		Cls()

		SetColorValue($13243a)
		For Local gridX:Int = 8 Until GraphicsWidth() Step 16
			DrawLine(gridX, 0, gridX, GraphicsHeight() - 1)
		Next
		For Local gridY:Int = 8 Until GraphicsHeight() Step 16
			DrawLine(0, gridY, GraphicsWidth() - 1, gridY)
		Next

		SetColorValue($ffcf32)
		FillCircle(ballX, ballY, 7)
		SetColorValue($ffffff)
		DrawCircle(ballX - 2, ballY - 2, 2)
		Plot(ballX - 2, ballY - 2)

		SetColorValue($ef476f)
		FillTriangle(GraphicsWidth() - 30, 12, GraphicsWidth() - 12, 21, ..
			GraphicsWidth() - 30, 30)
		SetColorValue($52d273)
		FillRoundRect(10, GraphicsHeight() - 24, 42, 14, 4)
		SetColorValue($06110a)
		SetFont(Spleen5x8Font())
		?nrf52
		DrawText("NRF52", 18, GraphicsHeight() - 21)
		?Not nrf52
		DrawText("PICO 2", 16, GraphicsHeight() - 21)
		?
		EndView()
	End If

	If PresentDirty() <= 0 Then RuntimeError "Unable to present animation region"

	ballX :+ velocityX
	ballY :+ velocityY
	If ballX <= 8 Or ballX >= StageWidth - 13 Then velocityX = -velocityX
	If ballY <= 8 Or ballY >= StageHeight - 13 Then velocityY = -velocityY

	frameCount :+ 1
	Local now:ULong = MonotonicMilliseconds()
	If now - reportStart >= 1000 Then
		Print "ST7735 Graphics2D: " + frameCount + " fps"
		frameCount = 0
		reportStart = now
	End If

	SleepMilliseconds(16)
Wend
