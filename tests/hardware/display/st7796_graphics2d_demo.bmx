SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
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

Const StageX:Int = 20
Const StageY:Int = 132
Const StageWidth:Int = 280
Const StageHeight:Int = 220
Const StageColor:UInt = $071321
Const BounceLeft:Int = StageX + 28
Const BounceRight:Int = StageX + StageWidth - 28
Const BounceTop:Int = StageY + 28
Const BounceBottom:Int = StageY + StageHeight - 28
Const TriangleX:Int = StageX + StageWidth - 65
Const TriangleY:Int = StageY + 22
Const TriangleWidth:Int = 37
Const TriangleHeight:Int = 37
Const BadgeX:Int = StageX + 24
Const BadgeY:Int = StageY + StageHeight - 48
Const BadgeWidth:Int = 92
Const BadgeHeight:Int = 28

If Not SPIConfigurePins(Controller, SPIUnavailablePin, TransmitPin, ClockPin) Then ..
	RuntimeError "Unable to configure write-only SPI0"
Local actualRate:UInt = SPIInit(Controller, 12000000)
If actualRate = 0 Then RuntimeError "Unable to initialize SPI0"

Local display:TST7796Display = TST7796Display.Create320x480(Controller, ..
	ChipSelectPin, DataCommandPin, ResetPin, True, True)
If Not display Or Not display.Initialize() Then RuntimeError "Unable to initialize ST7796"

Local frame:TDisplayBuffer = display.CreateBuffer()
If Not frame Then RuntimeError "Unable to allocate ST7796 framebuffer"

SetRenderTarget(frame, display)
SetClsColorValue($02060d)
Cls()

SetColorValue($12c8df)
FillRoundRect(12, 12, 296, 74, 12)
SetColorValue($001018)
SetFont(Spleen8x16Font())
DrawText("Graphics2D", 80, 30, 2)
SetFont(Spleen5x8Font())
DrawText("PICO 2  |  ST7796  |  dirty presentation", 53, 70)

SetColorValue($294561)
FillRoundRect(StageX, StageY, StageWidth, StageHeight, 12)
SetColorValue(StageColor)
FillRoundRect(StageX + 3, StageY + 3, StageWidth - 6, StageHeight - 6, 9)

' The solid field allows the old ball footprint to be restored directly. Small
' foreground decorations are redrawn after the ball so it passes behind them.
SetColorValue($10243a)
DrawRoundRect(StageX + 10, StageY + 10, StageWidth - 20, StageHeight - 20, 8)
DrawForeground()

SetColorValue($17283e)
FillRoundRect(20, 390, 280, 58, 10)
SetColorValue($9db2cc)
SetFont(Spleen8x16Font())
DrawText("Only the animation card is sent", 40, 411)

If Present() <= 0 Then RuntimeError "Unable to present initial frame"
SetDirtyTracking(True)

Local ballX:Int = StageX + 48
Local ballY:Int = StageY + 48
Local velocityX:Int = 3
Local velocityY:Int = 2
Local frameCount:Int
Local reportStart:ULong = MonotonicMilliseconds()

While True
	' Restore only the old ball footprint, then draw its new footprint. Dirty
	' tracking presents the two small rectangles rather than the entire card.
	Local oldBallX:Int = ballX
	Local oldBallY:Int = ballY
	SetColorValue(StageColor)
	FillRect(ballX - 15, ballY - 15, 31, 31)
	ballX :+ velocityX
	ballY :+ velocityY
	If ballX <= BounceLeft Or ballX >= BounceRight Then velocityX = -velocityX
	If ballY <= BounceTop Or ballY >= BounceBottom Then velocityY = -velocityY

	SetColorValue($ffce38)
	FillCircle(ballX, ballY, 13)
	SetColorValue($ffffff)
	FillCircle(ballX - 4, ballY - 4, 3)

	' Restore only the foreground pixels beneath the union of the old and new
	' ball footprints. The draw calls remain constant-cost and clipping prevents
	' complete foreground objects from becoming extra dirty rectangles.
	Local restoreX:Int = oldBallX - 15
	Local restoreY:Int = oldBallY - 15
	Local restoreX1:Int = oldBallX + 16
	Local restoreY1:Int = oldBallY + 16
	If ballX - 15 < restoreX Then restoreX = ballX - 15
	If ballY - 15 < restoreY Then restoreY = ballY - 15
	If ballX + 16 > restoreX1 Then restoreX1 = ballX + 16
	If ballY + 16 > restoreY1 Then restoreY1 = ballY + 16
	If BeginView(restoreX, restoreY, restoreX1 - restoreX, restoreY1 - restoreY) Then
		DrawForeground(-restoreX, -restoreY)
		EndView()
	End If

	If PresentDirty() <= 0 Then RuntimeError "Unable to present animation regions"

	frameCount :+ 1
	Local now:ULong = MonotonicMilliseconds()
	If now - reportStart >= 1000 Then
		Print "ST7796 Graphics2D: " + frameCount + " fps"
		frameCount = 0
		reportStart = now
	End If

	SleepMilliseconds(16)
Wend

Function DrawForeground(offsetX:Int = 0, offsetY:Int = 0)
	DrawTriangleForeground(offsetX, offsetY)
	DrawBadgeForeground(offsetX, offsetY)
End Function

Function DrawTriangleForeground(offsetX:Int = 0, offsetY:Int = 0)
	SetColorValue($ef476f)
	FillTriangle(TriangleX + offsetX, TriangleY + offsetY, ..
		TriangleX + TriangleWidth - 1 + offsetX, TriangleY + 18 + offsetY, ..
		TriangleX + offsetX, TriangleY + TriangleHeight - 1 + offsetY)
End Function

Function DrawBadgeForeground(offsetX:Int = 0, offsetY:Int = 0)
	SetColorValue($52d273)
	FillRoundRect(BadgeX + offsetX, BadgeY + offsetY, BadgeWidth, BadgeHeight, 6)
	SetColorValue($06110a)
	SetFont(Spleen8x16Font())
	DrawText("PICO 2", StageX + 42 + offsetX, StageY + StageHeight - 42 + offsetY)
End Function
