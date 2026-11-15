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
	param: Left coordinate of stored pixels within the source image.
	param: Top coordinate of stored pixels within the source image.
	param: Stored pixel width.
	param: Stored pixel height.
	param: Logical untrimmed width, or zero to use the stored width.
	param: Logical untrimmed height, or zero to use the stored height.
	param: Horizontal placement of stored pixels within the logical canvas.
	param: Vertical placement of stored pixels within the logical canvas.
	param: Horizontal drawing origin within the logical canvas.
	param: Vertical drawing origin within the logical canvas.
	returns: Immutable frame metadata, or Null when dimensions or offsets are invalid.
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

	Rem
	bbdoc: Returns the stored rectangle's left source coordinate.
	returns: Source x coordinate in pixels.
	End Rem
	Method SourceX:Int()
		Return frameSourceX
	End Method

	Rem
	bbdoc: Returns the stored rectangle's top source coordinate.
	returns: Source y coordinate in pixels.
	End Rem
	Method SourceY:Int()
		Return frameSourceY
	End Method

	Rem
	bbdoc: Returns the width of the stored pixel rectangle.
	returns: Stored width in pixels.
	End Rem
	Method StoredWidth:Int()
		Return frameStoredWidth
	End Method

	Rem
	bbdoc: Returns the height of the stored pixel rectangle.
	returns: Stored height in pixels.
	End Rem
	Method StoredHeight:Int()
		Return frameStoredHeight
	End Method

	Rem
	bbdoc: Returns the logical untrimmed canvas width.
	returns: Canvas width in pixels.
	End Rem
	Method Width:Int()
		Return frameCanvasWidth
	End Method

	Rem
	bbdoc: Returns the logical untrimmed canvas height.
	returns: Canvas height in pixels.
	End Rem
	Method Height:Int()
		Return frameCanvasHeight
	End Method

	Rem
	bbdoc: Returns the stored pixels' horizontal offset within the logical canvas.
	returns: Horizontal offset in pixels.
	End Rem
	Method OffsetX:Int()
		Return frameOffsetX
	End Method

	Rem
	bbdoc: Returns the stored pixels' vertical offset within the logical canvas.
	returns: Vertical offset in pixels.
	End Rem
	Method OffsetY:Int()
		Return frameOffsetY
	End Method

	Rem
	bbdoc: Returns the drawing origin's horizontal position within the canvas.
	returns: Handle x coordinate in pixels.
	End Rem
	Method HandleX:Int()
		Return frameHandleX
	End Method

	Rem
	bbdoc: Returns the drawing origin's vertical position within the canvas.
	returns: Handle y coordinate in pixels.
	End Rem
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
	param: Shared source image.
	param: Non-empty frame metadata array, copied by the sheet.
	returns: New sheet, or Null when a frame is invalid or outside the image.
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
	param: Source image.
	param: Cell width in pixels.
	param: Cell height in pixels.
	param: Zero-based first cell to retain.
	param: Number of cells to retain; zero selects every remaining complete cell.
	param: Empty pixels before the first cell at the left and top edges.
	param: Empty pixels between adjacent cells.
	param: Horizontal drawing origin within each cell.
	param: Vertical drawing origin within each cell.
	returns: New sheet, or Null when the grid parameters exceed the image.
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

	Rem
	bbdoc: Returns the source image shared by every frame.
	returns: Source image.
	End Rem
	Method Image:TEmbeddedImage()
		Return sourceImage
	End Method

	Rem
	bbdoc: Returns the number of frames.
	returns: Frame count.
	End Rem
	Method FrameCount:Int()
		Return frames.Length
	End Method

	Rem
	bbdoc: Returns one frame by index.
	param: Zero-based frame index.
	returns: Frame metadata, or Null when the index is invalid.
	End Rem
	Method Frame:TEmbeddedSpriteFrame(index:Int)
		If index < 0 Or index >= frames.Length Then Return Null
		Return frames[index]
	End Method

	Rem
	bbdoc: Returns one frame's logical destination bounds without drawing it.
	param: Zero-based frame index.
	param: Destination handle x coordinate.
	param: Destination handle y coordinate.
	param: Receives the logical left edge.
	param: Receives the logical top edge.
	param: Receives the logical untrimmed width.
	param: Receives the logical untrimmed height.
	returns: True for a valid frame index; otherwise False with empty bounds.
	about: Bounds cover the complete untrimmed frame canvas, including transparent
	space removed from an atlas frame. They are therefore suitable for restoring
	or invalidating both the old and new positions of a moving sprite.
	End Rem
	Method FrameBounds:Int(index:Int, x:Int, y:Int, left:Int Var, top:Int Var, ..
			width:Int Var, height:Int Var)
		Local frame:TEmbeddedSpriteFrame = Frame(index)
		If Not frame Then
			left = 0
			top = 0
			width = 0
			height = 0
			Return False
		End If
		left = x - frame.HandleX()
		top = y - frame.HandleY()
		width = frame.Width()
		height = frame.Height()
		Return True
	End Method

	Rem
	bbdoc: Adds one frame's logical canvas to a context's dirty regions without drawing it.
	param: Drawing context, or Null to use the module-level Graphics2D context.
	param: Zero-based frame index.
	param: Destination handle x coordinate.
	param: Destination handle y coordinate.
	returns: True when the frame index is valid.
	about: This is useful when an application restores a sprite's previous
	background separately from drawing its new frame.
	End Rem
	Method InvalidateFrame:Int(context:TEmbedded2DContext, index:Int, x:Int, y:Int)
		Local left:Int, top:Int, width:Int, height:Int
		If Not FrameBounds(index, x, y, left, top, width, height) Then Return False
		If context Then
			context.InvalidateRect(left, top, width, height)
		Else
			InvalidateRect(left, top, width, height)
		End If
		Return True
	End Method

	Rem
	bbdoc: Invalidates both positions involved in a sprite transition.
	param: Drawing context, or Null to use the module-level Graphics2D context.
	param: Previous frame index, or a negative value when there was no previous sprite.
	param: Previous destination handle x coordinate.
	param: Previous destination handle y coordinate.
	param: New frame index, or a negative value when the sprite is no longer visible.
	param: New destination handle x coordinate.
	param: New destination handle y coordinate.
	returns: Number of valid frame canvases submitted for invalidation.
	about: Dirty-region tracking may merge overlapping old and new bounds. This
	method changes no pixels and does not prescribe how the old background is restored.
	End Rem
	Method InvalidateTransition:Int(context:TEmbedded2DContext, oldIndex:Int, oldX:Int, oldY:Int, ..
			newIndex:Int, newX:Int, newY:Int)
		Local invalidated:Int
		If oldIndex >= 0 And InvalidateFrame(context, oldIndex, oldX, oldY) Then invalidated :+ 1
		If newIndex >= 0 And InvalidateFrame(context, newIndex, newX, newY) Then invalidated :+ 1
		Return invalidated
	End Method

	Rem
	bbdoc: Draws one frame using the supplied context or the default context.
	param: Drawing context, or Null to use the module-level Graphics2D context.
	param: Zero-based frame index.
	param: Destination handle x coordinate.
	param: Destination handle y coordinate.
	param: ImageFlipX, ImageFlipY, or combined drawing flags.
	param: Opacity from zero through 255.
	param: Optional RGB color key, or ImageColorKeyDisabled.
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
bbdoc: Reusable fixed-capacity drawing commands for one sprite sheet.
about: Command storage is allocated by Create and reused by Clear, Add, and Draw.
Submitting a batch performs no managed allocation. Commands retain their insertion
order, so the usual painter's-order layering rules apply.
End Rem
Type TEmbeddedSpriteBatch Final
	Private
	Field spriteSheet:TEmbeddedSpriteSheet
	Field sourceImage:TEmbeddedImage
	Field batchCapacity:Int
	Field commandCount:Int
	Field sourcePositionsX:Int[]
	Field sourcePositionsY:Int[]
	Field sourceWidths:Int[]
	Field sourceHeights:Int[]
	Field destinationPositionsX:Int[]
	Field destinationPositionsY:Int[]
	Field drawingFlags:Int[]
	Field drawingOpacities:Int[]
	Field drawingColorKeys:UInt[]

	Public
	Rem
	bbdoc: Creates reusable command storage for a sprite sheet.
	param: Sprite sheet drawn by every command.
	param: Positive maximum number of commands.
	returns: Empty batch, or Null when the arguments are invalid.
	End Rem
	Function Create:TEmbeddedSpriteBatch(sheet:TEmbeddedSpriteSheet, capacity:Int)
		If Not sheet Or capacity <= 0 Then Return Null
		Local batch:TEmbeddedSpriteBatch = New TEmbeddedSpriteBatch
		batch.spriteSheet = sheet
		batch.sourceImage = sheet.Image()
		batch.batchCapacity = capacity
		batch.sourcePositionsX = New Int[capacity]
		batch.sourcePositionsY = New Int[capacity]
		batch.sourceWidths = New Int[capacity]
		batch.sourceHeights = New Int[capacity]
		batch.destinationPositionsX = New Int[capacity]
		batch.destinationPositionsY = New Int[capacity]
		batch.drawingFlags = New Int[capacity]
		batch.drawingOpacities = New Int[capacity]
		batch.drawingColorKeys = New UInt[capacity]
		Return batch
	End Function

	Rem
	bbdoc: Returns the sprite sheet shared by every command.
	returns: Batch sprite sheet.
	End Rem
	Method Sheet:TEmbeddedSpriteSheet()
		Return spriteSheet
	End Method

	Rem
	bbdoc: Returns the maximum number of commands retained by this batch.
	returns: Fixed command capacity.
	End Rem
	Method Capacity:Int()
		Return batchCapacity
	End Method

	Rem
	bbdoc: Returns the number of commands currently retained.
	returns: Command count from zero through Capacity.
	End Rem
	Method Count:Int()
		Return commandCount
	End Method

	Rem
	bbdoc: Removes every command while retaining the allocated storage.
	End Rem
	Method Clear()
		commandCount = 0
	End Method

	Rem
	bbdoc: Appends one sprite drawing command.
	param: Zero-based sheet-frame index.
	param: Destination handle x coordinate.
	param: Destination handle y coordinate.
	param: ImageFlipX, ImageFlipY, or combined drawing flags.
	param: Opacity from zero through 255.
	param: Optional RGB color key, or ImageColorKeyDisabled.
	returns: True when retained; False for an invalid frame or a full batch.
	about: Tint comes from the drawing context at submission time, allowing one
	batch to be recolored without rebuilding its commands.
	End Rem
	Method Add:Int(index:Int, x:Int, y:Int, drawFlags:Int = 0, opacity:Int = 255, ..
			colorKey:UInt = ImageColorKeyDisabled)
		If commandCount >= batchCapacity Then Return False
		Local frame:TEmbeddedSpriteFrame = spriteSheet.Frame(index)
		If Not frame Then Return False
		sourcePositionsX[commandCount] = frame.SourceX()
		sourcePositionsY[commandCount] = frame.SourceY()
		sourceWidths[commandCount] = frame.StoredWidth()
		sourceHeights[commandCount] = frame.StoredHeight()
		destinationPositionsX[commandCount] = x - frame.HandleX() + frame.OffsetX()
		destinationPositionsY[commandCount] = y - frame.HandleY() + frame.OffsetY()
		drawingFlags[commandCount] = drawFlags
		drawingOpacities[commandCount] = opacity
		drawingColorKeys[commandCount] = colorKey
		commandCount :+ 1
		Return True
	End Method

	Rem
	bbdoc: Draws all retained commands in insertion order.
	param: Drawing context, or Null to use the module-level Graphics2D context.
	returns: Number of commands submitted.
	End Rem
	Method Draw:Int(context:TEmbedded2DContext)
		For Local index:Int = 0 Until commandCount
			If context Then
				context.DrawImageRegion(sourceImage, destinationPositionsX[index], ..
					destinationPositionsY[index], sourcePositionsX[index], sourcePositionsY[index], ..
					sourceWidths[index], sourceHeights[index], drawingFlags[index], ..
					drawingOpacities[index], drawingColorKeys[index])
			Else
				DrawImageRegion(sourceImage, destinationPositionsX[index], ..
					destinationPositionsY[index], sourcePositionsX[index], sourcePositionsY[index], ..
					sourceWidths[index], sourceHeights[index], drawingFlags[index], ..
					drawingOpacities[index], drawingColorKeys[index])
			End If
		Next
		Return commandCount
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
	Rem
	bbdoc: Creates an animation from explicit sheet-frame indices and durations.
	param: Sprite sheet containing every referenced frame.
	param: Frame indices in playback order, copied by the animation.
	param: Positive frame durations in milliseconds, copied by the animation.
	returns: Immutable animation, or Null when arrays or entries are invalid.
	End Rem
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
	param: Sprite sheet containing the frame range.
	param: Zero-based first sheet frame.
	param: Positive number of consecutive frames.
	param: Positive duration of each frame in milliseconds.
	returns: Immutable animation, or Null when the range is invalid.
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

	Rem
	bbdoc: Returns the shared sprite sheet.
	returns: Animation sprite sheet.
	End Rem
	Method Sheet:TEmbeddedSpriteSheet()
		Return spriteSheet
	End Method

	Rem
	bbdoc: Returns the number of animation frames.
	returns: Playback-frame count.
	End Rem
	Method FrameCount:Int()
		Return frameIndices.Length
	End Method

	Rem
	bbdoc: Returns the complete animation duration.
	returns: Total duration in milliseconds.
	End Rem
	Method Duration:Long()
		Return totalDuration
	End Method

	Rem
	bbdoc: Maps an animation-frame index to its sprite-sheet frame.
	param: Zero-based animation-frame index.
	returns: Sheet-frame index, or -1 when invalid.
	End Rem
	Method SheetFrame:Int(animationFrame:Int)
		If animationFrame < 0 Or animationFrame >= frameIndices.Length Then Return -1
		Return frameIndices[animationFrame]
	End Method

	Rem
	bbdoc: Selects a zero-based animation frame for elapsed milliseconds.
	param: Elapsed playback time in milliseconds.
	param: True to wrap at the animation duration; False to hold the final frame.
	returns: Zero-based animation-frame index.
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

	Rem
	bbdoc: Draws one animation frame through its sprite sheet.
	param: Drawing context, or Null to use the module-level Graphics2D context.
	param: Zero-based animation-frame index.
	param: Destination handle x coordinate.
	param: Destination handle y coordinate.
	param: Image drawing flags.
	param: Opacity from zero through 255.
	param: Optional RGB color key, or ImageColorKeyDisabled.
	End Rem
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
	Rem
	bbdoc: Creates independent playback state for an animation.
	param: Shared immutable animation definition.
	param: True to loop at the end.
	returns: New player, or Null when the animation is invalid.
	End Rem
	Function Create:TEmbeddedSpritePlayer(animation:TEmbeddedSpriteAnimation, loop:Int = True)
		If Not animation Then Return Null
		Local player:TEmbeddedSpritePlayer = New TEmbeddedSpritePlayer
		player.animationDefinition = animation
		player.looping = loop <> 0
		Return player
	End Function

	Rem
	bbdoc: Returns the current animation definition.
	returns: Shared animation.
	End Rem
	Method Animation:TEmbeddedSpriteAnimation()
		Return animationDefinition
	End Method

	Rem
	bbdoc: Replaces the animation and resets playback to its first frame.
	param: New shared animation; Null is ignored.
	param: True to loop at the end.
	End Rem
	Method SetAnimation(animation:TEmbeddedSpriteAnimation, loop:Int = True)
		If Not animation Then Return
		animationDefinition = animation
		looping = loop <> 0
		Reset()
	End Method

	Rem
	bbdoc: Returns to the first frame and resumes playback.
	End Rem
	Method Reset()
		elapsed = 0
		finished = False
		playing = True
	End Method

	Rem
	bbdoc: Resumes a paused player that has not finished.
	End Rem
	Method Play()
		If animationDefinition And Not finished Then playing = True
	End Method

	Rem
	bbdoc: Pauses playback without changing elapsed time.
	End Rem
	Method Pause()
		playing = False
	End Method

	Rem
	bbdoc: Reports whether Advance currently changes playback time.
	returns: True while playing.
	End Rem
	Method IsPlaying:Int()
		Return playing
	End Method

	Rem
	bbdoc: Reports whether non-looping playback reached its end.
	returns: True after the final frame duration has elapsed.
	End Rem
	Method IsFinished:Int()
		Return finished
	End Method

	Rem
	bbdoc: Returns the current animation clock.
	returns: Elapsed time in milliseconds.
	End Rem
	Method ElapsedTime:Long()
		Return elapsed
	End Method

	Rem
	bbdoc: Returns the animation frame selected by the current clock.
	returns: Zero-based animation-frame index, or -1 without an animation.
	End Rem
	Method CurrentFrame:Int()
		If Not animationDefinition Then Return -1
		Return animationDefinition.FrameAtTime(elapsed, looping)
	End Method

	Rem
	bbdoc: Advances playback by a nonnegative elapsed-time delta in milliseconds.
	param: Time delta in milliseconds; non-positive values are ignored.
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

	Rem
	bbdoc: Draws the player's current animation frame.
	param: Drawing context, or Null to use the module-level Graphics2D context.
	param: Destination handle x coordinate.
	param: Destination handle y coordinate.
	param: Image drawing flags.
	param: Opacity from zero through 255.
	param: Optional RGB color key, or ImageColorKeyDisabled.
	End Rem
	Method Draw(context:TEmbedded2DContext, x:Int, y:Int, drawFlags:Int = 0, ..
			opacity:Int = 255, colorKey:UInt = ImageColorKeyDisabled)
		If animationDefinition Then animationDefinition.Draw(context, CurrentFrame(), x, y, drawFlags, opacity, colorKey)
	End Method
End Type
?
