' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Flash-resident sprite sheets and deterministic animation playback.
about: Sprite frames are lightweight views into one TEmbeddedImage. Animation
definitions may be shared by any number of independent players. Drawing and
playback updates allocate no memory after the objects have been created.
End Rem
Module Embedded.Graphics2D.Sprite
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.Graphics2D

Rem
bbdoc: An immutable rectangular sprite-frame view within an embedded image.
about: The stored rectangle may be positioned within a larger logical canvas,
allowing a future atlas converter to trim transparent borders without changing
where the visible pixels are drawn. The handle is measured in canvas pixels.
End Rem
Type TEmbeddedSpriteFrame Final
	Private
	Field frameSourceX:Int
	Field frameSourceY:Int
	Field frameStoredWidth:Int
	Field frameStoredHeight:Int
	Field frameCanvasWidth:Int
	Field frameCanvasHeight:Int
	Field frameOffsetX:Int
	Field frameOffsetY:Int
	Field frameHandleX:Int
	Field frameHandleY:Int

	Public
	Rem
	bbdoc: Creates frame metadata; validation against an image occurs when a sheet is created.
	End Rem
	Function Create:TEmbeddedSpriteFrame(sourceX:Int, sourceY:Int, width:Int, height:Int, ..
			canvasWidth:Int = 0, canvasHeight:Int = 0, offsetX:Int = 0, offsetY:Int = 0, ..
			handleX:Int = 0, handleY:Int = 0)
		If sourceX < 0 Or sourceY < 0 Or width <= 0 Or height <= 0 Then Return Null
		If canvasWidth = 0 Then canvasWidth = width
		If canvasHeight = 0 Then canvasHeight = height
		If canvasWidth <= 0 Or canvasHeight <= 0 Or offsetX < 0 Or offsetY < 0 Then Return Null
		If Long(offsetX) + width > canvasWidth Or Long(offsetY) + height > canvasHeight Then Return Null
		Local frame:TEmbeddedSpriteFrame = New TEmbeddedSpriteFrame
		frame.frameSourceX = sourceX
		frame.frameSourceY = sourceY
		frame.frameStoredWidth = width
		frame.frameStoredHeight = height
		frame.frameCanvasWidth = canvasWidth
		frame.frameCanvasHeight = canvasHeight
		frame.frameOffsetX = offsetX
		frame.frameOffsetY = offsetY
		frame.frameHandleX = handleX
		frame.frameHandleY = handleY
		Return frame
	End Function

	Method SourceX:Int()
		Return frameSourceX
	End Method

	Method SourceY:Int()
		Return frameSourceY
	End Method

	Method StoredWidth:Int()
		Return frameStoredWidth
	End Method

	Method StoredHeight:Int()
		Return frameStoredHeight
	End Method

	Method Width:Int()
		Return frameCanvasWidth
	End Method

	Method Height:Int()
		Return frameCanvasHeight
	End Method

	Method OffsetX:Int()
		Return frameOffsetX
	End Method

	Method OffsetY:Int()
		Return frameOffsetY
	End Method

	Method HandleX:Int()
		Return frameHandleX
	End Method

	Method HandleY:Int()
		Return frameHandleY
	End Method
End Type

Rem
bbdoc: A collection of sprite-frame views sharing one flash-resident image.
End Rem
Type TEmbeddedSpriteSheet Final
	Private
	Field sourceImage:TEmbeddedImage
	Field frames:TEmbeddedSpriteFrame[]

	Public
	Rem
	bbdoc: Creates a sheet from arbitrary validated frame rectangles.
	End Rem
	Function Create:TEmbeddedSpriteSheet(image:TEmbeddedImage, frames:TEmbeddedSpriteFrame[])
		If Not image Or Not frames Or frames.Length = 0 Then Return Null
		For Local frame:TEmbeddedSpriteFrame = EachIn frames
			If Not frame Or Long(frame.SourceX()) + frame.StoredWidth() > image.Width() Or ..
					Long(frame.SourceY()) + frame.StoredHeight() > image.Height() Then Return Null
		Next
		Local sheet:TEmbeddedSpriteSheet = New TEmbeddedSpriteSheet
		sheet.sourceImage = image
		sheet.frames = frames[..]
		Return sheet
	End Function

	Rem
	bbdoc: Splits an image into row-major fixed-size cells.
	param: Zero-based first cell to retain.
	param: Number of cells to retain; zero selects every remaining complete cell.
	param: Empty pixels before the first cell at the left and top edges.
	param: Empty pixels between adjacent cells.
	End Rem
	Function CreateGrid:TEmbeddedSpriteSheet(image:TEmbeddedImage, cellWidth:Int, cellHeight:Int, ..
			firstCell:Int = 0, cellCount:Int = 0, margin:Int = 0, spacing:Int = 0, ..
			handleX:Int = 0, handleY:Int = 0)
		If Not image Or cellWidth <= 0 Or cellHeight <= 0 Or firstCell < 0 Or ..
				cellCount < 0 Or margin < 0 Or spacing < 0 Then Return Null
		Local availableWidth:Long = Long(image.Width()) - Long(margin) * 2
		Local availableHeight:Long = Long(image.Height()) - Long(margin) * 2
		If availableWidth < cellWidth Or availableHeight < cellHeight Then Return Null
		Local horizontalStep:Long = Long(cellWidth) + spacing
		Local verticalStep:Long = Long(cellHeight) + spacing
		Local columns:Int = Int((availableWidth + spacing) / horizontalStep)
		Local rows:Int = Int((availableHeight + spacing) / verticalStep)
		If columns <= 0 Or rows <= 0 Then Return Null
		Local availableCells:Long = Long(columns) * rows
		If firstCell >= availableCells Then Return Null
		If cellCount = 0 Then cellCount = Int(availableCells - firstCell)
		If Long(firstCell) + cellCount > availableCells Then Return Null
		Local frames:TEmbeddedSpriteFrame[] = New TEmbeddedSpriteFrame[cellCount]
		For Local index:Int = 0 Until cellCount
			Local cell:Int = firstCell + index
			Local column:Int = cell Mod columns
			Local row:Int = cell / columns
			frames[index] = TEmbeddedSpriteFrame.Create(..
				margin + column * (cellWidth + spacing), ..
				margin + row * (cellHeight + spacing), cellWidth, cellHeight, ..
				cellWidth, cellHeight, 0, 0, handleX, handleY)
		Next
		Return Create(image, frames)
	End Function

	Method Image:TEmbeddedImage()
		Return sourceImage
	End Method

	Method FrameCount:Int()
		Return frames.Length
	End Method

	Method Frame:TEmbeddedSpriteFrame(index:Int)
		If index < 0 Or index >= frames.Length Then Return Null
		Return frames[index]
	End Method

	Rem
	bbdoc: Draws one frame using the supplied context or the default context.
	about: Coordinates locate the frame handle within its logical canvas.
	End Rem
	Method Draw(context:TEmbedded2DContext, index:Int, x:Int, y:Int, drawFlags:Int = 0, ..
			opacity:Int = 255, colorKey:UInt = ImageColorKeyDisabled)
		Local frame:TEmbeddedSpriteFrame = Frame(index)
		If Not frame Then Return
		Local destinationX:Int = x - frame.HandleX() + frame.OffsetX()
		Local destinationY:Int = y - frame.HandleY() + frame.OffsetY()
		If context Then
			context.DrawImageRegion(sourceImage, destinationX, destinationY, ..
				frame.SourceX(), frame.SourceY(), frame.StoredWidth(), frame.StoredHeight(), ..
				drawFlags, opacity, colorKey)
		Else
			DrawImageRegion(sourceImage, destinationX, destinationY, frame.SourceX(), ..
				frame.SourceY(), frame.StoredWidth(), frame.StoredHeight(), ..
				drawFlags, opacity, colorKey)
		End If
	End Method
End Type

Rem
bbdoc: Immutable frame order and timing shared by sprite-animation players.
End Rem
Type TEmbeddedSpriteAnimation Final
	Private
	Field spriteSheet:TEmbeddedSpriteSheet
	Field frameIndices:Int[]
	Field frameDurations:Int[]
	Field totalDuration:Long

	Public
	Function Create:TEmbeddedSpriteAnimation(sheet:TEmbeddedSpriteSheet, frameIndices:Int[], ..
			durations:Int[])
		If Not sheet Or Not frameIndices Or Not durations Or frameIndices.Length = 0 Or ..
				frameIndices.Length <> durations.Length Then Return Null
		Local total:Long
		For Local index:Int = 0 Until frameIndices.Length
			If frameIndices[index] < 0 Or frameIndices[index] >= sheet.FrameCount() Or ..
					durations[index] <= 0 Then Return Null
			total :+ durations[index]
			If total <= 0 Then Return Null
		Next
		Local animation:TEmbeddedSpriteAnimation = New TEmbeddedSpriteAnimation
		animation.spriteSheet = sheet
		animation.frameIndices = frameIndices[..]
		animation.frameDurations = durations[..]
		animation.totalDuration = total
		Return animation
	End Function

	Rem
	bbdoc: Creates consecutive animation frames with one common duration.
	End Rem
	Function CreateRange:TEmbeddedSpriteAnimation(sheet:TEmbeddedSpriteSheet, firstFrame:Int, ..
			frameCount:Int, frameDuration:Int)
		If Not sheet Or firstFrame < 0 Or frameCount <= 0 Or frameDuration <= 0 Or ..
				Long(firstFrame) + frameCount > sheet.FrameCount() Then Return Null
		Local indices:Int[] = New Int[frameCount]
		Local durations:Int[] = New Int[frameCount]
		For Local index:Int = 0 Until frameCount
			indices[index] = firstFrame + index
			durations[index] = frameDuration
		Next
		Return Create(sheet, indices, durations)
	End Function

	Method Sheet:TEmbeddedSpriteSheet()
		Return spriteSheet
	End Method

	Method FrameCount:Int()
		Return frameIndices.Length
	End Method

	Method Duration:Long()
		Return totalDuration
	End Method

	Method SheetFrame:Int(animationFrame:Int)
		If animationFrame < 0 Or animationFrame >= frameIndices.Length Then Return -1
		Return frameIndices[animationFrame]
	End Method

	Rem
	bbdoc: Selects a zero-based animation frame for elapsed milliseconds.
	about: Negative time is treated as zero. Non-looping playback holds its last frame.
	End Rem
	Method FrameAtTime:Int(elapsed:Long, loop:Int = True)
		If elapsed < 0 Then elapsed = 0
		If loop Then
			elapsed = elapsed Mod totalDuration
		Else If elapsed >= totalDuration Then
			Return frameIndices.Length - 1
		End If
		For Local index:Int = 0 Until frameDurations.Length
			If elapsed < frameDurations[index] Then Return index
			elapsed :- frameDurations[index]
		Next
		Return frameIndices.Length - 1
	End Method

	Method Draw(context:TEmbedded2DContext, animationFrame:Int, x:Int, y:Int, ..
			drawFlags:Int = 0, opacity:Int = 255, colorKey:UInt = ImageColorKeyDisabled)
		Local sheetFrame:Int = SheetFrame(animationFrame)
		If sheetFrame >= 0 Then spriteSheet.Draw(context, sheetFrame, x, y, drawFlags, opacity, colorKey)
	End Method
End Type

Rem
bbdoc: Independent mutable playback state for a shared sprite animation.
End Rem
Type TEmbeddedSpritePlayer Final
	Private
	Field animationDefinition:TEmbeddedSpriteAnimation
	Field elapsed:Long
	Field looping:Int = True
	Field playing:Int = True
	Field finished:Int

	Public
	Function Create:TEmbeddedSpritePlayer(animation:TEmbeddedSpriteAnimation, loop:Int = True)
		If Not animation Then Return Null
		Local player:TEmbeddedSpritePlayer = New TEmbeddedSpritePlayer
		player.animationDefinition = animation
		player.looping = loop <> 0
		Return player
	End Function

	Method Animation:TEmbeddedSpriteAnimation()
		Return animationDefinition
	End Method

	Method SetAnimation(animation:TEmbeddedSpriteAnimation, loop:Int = True)
		If Not animation Then Return
		animationDefinition = animation
		looping = loop <> 0
		Reset()
	End Method

	Method Reset()
		elapsed = 0
		finished = False
		playing = True
	End Method

	Method Play()
		If animationDefinition And Not finished Then playing = True
	End Method

	Method Pause()
		playing = False
	End Method

	Method IsPlaying:Int()
		Return playing
	End Method

	Method IsFinished:Int()
		Return finished
	End Method

	Method ElapsedTime:Long()
		Return elapsed
	End Method

	Method CurrentFrame:Int()
		If Not animationDefinition Then Return -1
		Return animationDefinition.FrameAtTime(elapsed, looping)
	End Method

	Rem
	bbdoc: Advances playback by a nonnegative elapsed-time delta in milliseconds.
	End Rem
	Method Advance(deltaMilliseconds:Int)
		If Not animationDefinition Or Not playing Or deltaMilliseconds <= 0 Then Return
		If looping Then
			elapsed = (elapsed + deltaMilliseconds) Mod animationDefinition.Duration()
		Else
			elapsed :+ deltaMilliseconds
			If elapsed >= animationDefinition.Duration() Then
				elapsed = animationDefinition.Duration()
				finished = True
				playing = False
			End If
		End If
	End Method

	Method Draw(context:TEmbedded2DContext, x:Int, y:Int, drawFlags:Int = 0, ..
			opacity:Int = 255, colorKey:UInt = ImageColorKeyDisabled)
		If animationDefinition Then animationDefinition.Draw(context, CurrentFrame(), x, y, drawFlags, opacity, colorKey)
	End Method
End Type
?
