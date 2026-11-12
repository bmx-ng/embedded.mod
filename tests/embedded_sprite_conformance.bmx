SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Image
Import Embedded.Graphics2D
Import Embedded.Graphics2D.Sprite

Function PutU16(data:Byte[], offset:Int, value:Int)
	data[offset] = Byte(value)
	data[offset + 1] = Byte(value Shr 8)
End Function

Function PutU32(data:Byte[], offset:Int, value:Int)
	data[offset] = Byte(value)
	data[offset + 1] = Byte(value Shr 8)
	data[offset + 2] = Byte(value Shr 16)
	data[offset + 3] = Byte(value Shr 24)
End Function

Local passed:Int = True

' A 4x2 RGB888 sheet containing two 2x2 cells:
' red/blue in the first and green/white in the second.
Local data:Byte[] = New Byte[56]
data[0] = Asc("E"); data[1] = Asc("B"); data[2] = Asc("I"); data[3] = Asc("1")
PutU16(data, 4, 1)
PutU16(data, 8, 4); PutU16(data, 10, 2)
PutU16(data, 12, DisplayPixelFormatRGB888)
PutU32(data, 16, 12); PutU32(data, 20, 32)
For Local y:Int = 0 Until 2
	For Local x:Int = 0 Until 4
		Local offset:Int = 32 + y * 12 + x * 3
		Select x
			Case 0, 1
				If y = 0 Then data[offset] = $ff Else data[offset + 2] = $ff
			Case 2, 3
				If y = 0 Then
					data[offset + 1] = $ff
				Else
					data[offset] = $ff; data[offset + 1] = $ff; data[offset + 2] = $ff
				End If
		End Select
	Next
Next

Local image:TEmbeddedImage = TEmbeddedImage.Create(Varptr data[0], data.Length)
Local sheet:TEmbeddedSpriteSheet = TEmbeddedSpriteSheet.CreateGrid(image, 2, 2, 0, 0, 0, 0, 1, 1)
passed :& sheet <> Null And sheet.FrameCount() = 2
passed :& sheet.Frame(0).SourceX() = 0 And sheet.Frame(1).SourceX() = 2
passed :& sheet.Frame(0).Width() = 2 And sheet.Frame(0).Height() = 2
passed :& TEmbeddedSpriteSheet.CreateGrid(image, 3, 2, 2) = Null

Local target:TDisplayBuffer = TDisplayBuffer.Create(4, 3, DisplayPixelFormatRGB888)
Local context:TEmbedded2DContext = TEmbedded2DContext.Create(target)
sheet.Draw(context, 1, 2, 1)
passed :& target.Pixel(1, 0) = $00ff00 And target.Pixel(2, 0) = $00ff00
passed :& target.Pixel(1, 1) = $ffffff And target.Pixel(2, 1) = $ffffff
passed :& target.Pixel(0, 0) = 0 And target.Pixel(3, 0) = 0

' Arbitrary trimmed frame metadata preserves its logical placement and handle.
Local trimmed:TEmbeddedSpriteFrame = TEmbeddedSpriteFrame.Create(3, 1, 1, 1, 3, 3, 1, 1, 1, 1)
Local trimmedSheet:TEmbeddedSpriteSheet = TEmbeddedSpriteSheet.Create(image, [trimmed])
target.Clear()
trimmedSheet.Draw(context, 0, 2, 1)
passed :& target.Pixel(2, 1) = $ffffff
passed :& target.Pixel(1, 1) = 0 And target.Pixel(3, 1) = 0
passed :& TEmbeddedSpriteSheet.Create(image, ..
	[TEmbeddedSpriteFrame.Create(4, 0, 1, 1)]) = Null

Local animation:TEmbeddedSpriteAnimation = TEmbeddedSpriteAnimation.Create(sheet, [0, 1], [100, 200])
passed :& animation <> Null And animation.FrameCount() = 2 And animation.Duration() = 300
passed :& animation.FrameAtTime(-1) = 0 And animation.FrameAtTime(99) = 0
passed :& animation.FrameAtTime(100) = 1 And animation.FrameAtTime(299) = 1
passed :& animation.FrameAtTime(300) = 0 And animation.FrameAtTime(300, False) = 1
passed :& TEmbeddedSpriteAnimation.Create(sheet, [0, 2], [100, 100]) = Null
passed :& TEmbeddedSpriteAnimation.Create(sheet, [0], [0]) = Null

Local ranged:TEmbeddedSpriteAnimation = TEmbeddedSpriteAnimation.CreateRange(sheet, 0, 2, 50)
passed :& ranged <> Null And ranged.Duration() = 100 And ranged.FrameAtTime(50) = 1

' Players share immutable definitions but keep independent clocks.
Local looping:TEmbeddedSpritePlayer = TEmbeddedSpritePlayer.Create(animation)
Local once:TEmbeddedSpritePlayer = TEmbeddedSpritePlayer.Create(animation, False)
looping.Advance(100)
once.Advance(350)
passed :& looping.CurrentFrame() = 1 And looping.IsPlaying() And Not looping.IsFinished()
passed :& once.CurrentFrame() = 1 And Not once.IsPlaying() And once.IsFinished()
passed :& once.ElapsedTime() = 300
once.Reset()
once.Pause()
once.Advance(100)
passed :& once.CurrentFrame() = 0 And Not once.IsPlaying()
once.Play()
once.Advance(100)
passed :& once.CurrentFrame() = 1

target.Clear()
looping.Draw(context, 2, 1, ImageFlipX)
passed :& target.Pixel(1, 0) = $00ff00 And target.Pixel(2, 1) = $ffffff

' A Null context deliberately selects the familiar module-level Graphics2D context.
target.Clear()
SetRenderTarget target
sheet.Draw(Null, 0, 1, 1)
passed :& target.Pixel(0, 0) = $ff0000 And target.Pixel(1, 1) = $0000ff

If passed Then
	Print "Embedded sprite conformance test passed"
Else
	Print "Embedded sprite conformance test failed"
End If
