SuperStrict

' Responsive geometry regression for passive, display-only firmware.

Framework BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.UI

Function Check(value:Int, message:String)
	If Not value Then RuntimeError message
End Function

Function Within:Int(widget:TUIWidget, x:Int, y:Int, width:Int, height:Int)
	Return widget.X() >= x And widget.Y() >= y And ..
		widget.X() + widget.Width() <= x + width And ..
		widget.Y() + widget.Height() <= y + height
End Function

Function HasClippingAncestor:Int(widget:TUIWidget)
	Local parent:TUIContainer = widget.Parent()
	While parent
		If parent.ClipsChildren() Then Return True
		parent = parent.Parent()
	Wend
	Return False
End Function

Function ValidateTree(root:TUIWidget, frameWidth:Int, frameHeight:Int, name:String)
	' Keep the validation iterative so this regression does not itself consume stack
	' in proportion to retained-tree depth.
	Local pending:TUIWidget[64]
	Local count:Int = 1
	pending[0] = root
	While count > 0
		count :- 1
		Local widget:TUIWidget = pending[count]
		Check(widget.Width() >= 0 And widget.Height() >= 0, ..
			name + ": negative widget geometry")
		If widget.Visible() And Not Within(widget, 0, 0, frameWidth, frameHeight) Then
			Check(HasClippingAncestor(widget), ..
				name + ": visible geometry escaped the frame without clipping")
		End If
		For Local index:Int = 0 Until widget.ChildCount()
			Check(count < pending.Length, name + ": retained tree exceeded validation capacity")
			pending[count] = widget.Child(index)
			count :+ 1
		Next
	Wend
End Function

Function RunLayout(width:Int, height:Int, expectedColumns:Int, name:String)
	Local frame:TDisplayBuffer = TDisplayBuffer.Create(width, height, DisplayPixelFormatMono1)
	Local ui:TUIContext = TUIContext.CreateDisplayOnlyWithBuffer(frame, Null, ..
		TUITheme.Dark(Spleen5x8Font()))
	Check(ui <> Null, name + ": could not create display-only UI")

	Local page:TUIColumn = ui.Root()
	page.SetPadding(4)
	Local grid:TUIGrid = page.Grid()
	grid.SetGrow(1)
	grid.SetGap(4)
	grid.SetMinimumColumnWidth(140)

	Local rows:Int = (6 + expectedColumns - 1) / expectedColumns
	grid.SetRowHeight(Max((height - 8 - (rows - 1) * 4) / rows, 1))
	Local cards:TUICard[6]
	Local progress:TUIProgressBar[6]
	For Local index:Int = 0 Until cards.Length
		cards[index] = grid.Card("Tile " + (index + 1))
		progress[index] = cards[index].ProgressBar(0, 100, index * 15)
	Next

	Check(ui.Render(), name + ": initial render failed")
	Check(page.X() = 0 And page.Y() = 0 And page.Width() = width And page.Height() = height, ..
		name + ": root did not match the framebuffer")
	For Local card:TUICard = EachIn cards
		Check(Within(card, grid.X(), grid.Y(), grid.Width(), grid.Height()), ..
			name + ": grid card escaped its bounds")
	Next

	' The same six tiles must adapt from one, to two, to five columns.
	For Local index:Int = 0 Until cards.Length
		Local column:Int = index Mod expectedColumns
		Local row:Int = index / expectedColumns
		If column = 0 Then
			Check(cards[index].X() = cards[0].X(), name + ": row did not restart at column zero")
		Else
			Check(cards[index].Y() = cards[index - 1].Y() And ..
				cards[index].X() > cards[index - 1].X(), ..
				name + ": adaptive columns were not placed on one row")
		End If
		If row > 0 Then
			Check(cards[index].Y() > cards[index Mod expectedColumns].Y(), ..
				name + ": adaptive grid row did not advance")
		End If
	Next
	ValidateTree(page, width, height, name)

	For Local index:Int = 0 Until progress.Length
		progress[index].SetValue(100 - index * 10)
	Next
	' Compact cards deliberately clip their content almost completely. Mutate the
	' visible card as well so this remains a redraw test rather than requiring a
	' fully clipped child to create a drawable dirty region.
	cards[0].SetBackgroundVisible(False)
	Check(ui.Render(), name + ": dirty redraw failed")
	ValidateTree(page, width, height, name + " redraw")
	ui.Close()
End Function

RunLayout(128, 64, 1, "compact")
RunLayout(320, 240, 2, "panel")
RunLayout(800, 480, 5, "large")
Print "embedded UI layout matrix: PASS"
