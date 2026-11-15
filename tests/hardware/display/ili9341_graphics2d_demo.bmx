SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Drivers.Display.Fonts.Spleen.Size8x16
Import Embedded.Drivers.Displays.ILI9341
Import Embedded.Graphics2D
Import Embedded.Hardware.SPI
Import Embedded.System.Time

Const Controller:Int = SPIController0
?pico
Const ReceivePin:UInt = 16
Const TransmitPin:UInt = 19
Const ClockPin:UInt = 18
Const ChipSelectPin:UInt = 17
Const DataCommandPin:UInt = 15
Const ResetPin:UInt = 20
?esp32
Const ReceivePin:UInt = 14
Const TransmitPin:UInt = 13
Const ClockPin:UInt = 12
Const ChipSelectPin:UInt = 15
Const DataCommandPin:UInt = 16
Const ResetPin:UInt = 17
?

Const StageX:Int = 14
Const StageY:Int = 67
Const StageWidth:Int = 292
Const StageHeight:Int = 132
Const StageColor:UInt = $071321
Const BounceLeft:Int = StageX + 25
Const BounceRight:Int = StageX + StageWidth - 25
Const BounceTop:Int = StageY + 25
Const BounceBottom:Int = StageY + StageHeight - 25

If Not SPIConfigurePins(Controller, ReceivePin, TransmitPin, ClockPin) Then ..
	RuntimeError "Unable to configure SPI0"
Local actualRate:UInt = SPIInit(Controller, 12000000)
If actualRate = 0 Then RuntimeError "Unable to initialize SPI0"

Local display:TILI9341Display = TILI9341Display.Create(Controller, ..
	ChipSelectPin, DataCommandPin, ResetPin, True, False, DisplayOrientation90)
If Not display Or Not display.Initialize() Then RuntimeError "Unable to initialize ILI9341"

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Unable to allocate ILI9341 framebuffer"

SetRenderTarget(frame, display)
SetClsColorValue($02060d)
Cls()

SetColorValue($12c8df)
FillRoundRect(8, 8, 304, 45, 9)
SetColorValue($001018)
SetFont(Spleen8x16Font())
DrawText("ILI9341 LANDSCAPE", 56, 22)

SetColorValue($294561)
FillRoundRect(StageX, StageY, StageWidth, StageHeight, 10)
SetColorValue(StageColor)
FillRoundRect(StageX + 3, StageY + 3, StageWidth - 6, StageHeight - 6, 7)

SetColorValue($17283e)
FillRoundRect(14, 211, 292, 21, 6)
SetColorValue($9db2cc)
SetFont(Spleen5x8Font())
DrawText("320x240 logical view | clipped dirty animation", 48, 218)

If Present() <= 0 Then RuntimeError "Unable to present initial frame"
SetDirtyTracking(True)

Local ballX:Int = StageX + 45
Local ballY:Int = StageY + 38
Local velocityX:Int = 3
Local velocityY:Int = 2
Local frameCount:Int
Local reportStart:ULong = MonotonicMilliseconds()

While True
	SetColorValue(StageColor)
	FillRect(ballX - 14, ballY - 14, 29, 29)

	ballX :+ velocityX
	ballY :+ velocityY
	If ballX <= BounceLeft Or ballX >= BounceRight Then velocityX = -velocityX
	If ballY <= BounceTop Or ballY >= BounceBottom Then velocityY = -velocityY

	SetColorValue($ffff00)
	FillCircle(ballX, ballY, 12)
	SetColorValue($ffffff)
	FillCircle(ballX - 4, ballY - 4, 3)
	If PresentDirty() <= 0 Then RuntimeError "Unable to present animation regions"

	frameCount :+ 1
	Local now:ULong = MonotonicMilliseconds()
	If now - reportStart >= 1000 Then
		Print "ILI9341 landscape Graphics2D: " + frameCount + " fps"
		frameCount = 0
		reportStart = now
	End If
	SleepMilliseconds(16)
Wend
