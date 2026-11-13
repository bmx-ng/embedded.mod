SuperStrict

Framework BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.UI
Import Embedded.UI.Controls

Function Check(value:Int, message:String)
	If Not value Then RuntimeError message
End Function

Local frame:TDisplayBuffer = TDisplayBuffer.Create(360, 200, DisplayPixelFormatMono1)
Local ui:TUIContext = TUIContext.CreateWithBuffer(frame, Null, ..
	TUITheme.Dark(Spleen5x8Font()))
Check(ui <> Null, "could not create dashboard layout UI")
Local page:TUIColumn = ui.Root()
page.SetPadding(4)
page.SetGap(4)

Local header:TUIHeader = page.Header("Dashboard", True)
Local headerAction:TUIButton = header.Action("Info")
Check(header.Title() = "Dashboard" And header.BackButton().Visible() And ..
	headerAction <> Null, "header controls were not retained")

Local grid:TUIGrid = page.Grid(3)
grid.SetGap(4)
grid.SetRowHeight(40)
grid.SetHeight(84)
Local first:TUICard = grid.Card("First")
Local wide:TUICard = grid.Card("Wide")
wide.SetGridSpan(2)
Local full:TUICard = grid.Card("Full")
full.SetGridSpan(3)
Check(first.Title() = "First" And first.ClipsChildren() And wide.GridSpan() = 2, ..
	"card metadata or clipping was not retained")

Local navigation:TUINavigationBar = page.NavigationBar()
Local home:TUIButton = navigation.Action("Home")
Local settings:TUIButton = navigation.Action("Settings")
Check(ui.Render(), "dashboard composition did not render")
Check(first.Y() = wide.Y() And wide.X() > first.X() And wide.Width() > first.Width(), ..
	"grid column span was not applied")
Check(full.Y() > first.Y() And full.X() = first.X() And full.Width() = grid.Width(), ..
	"full-width grid card was not wrapped correctly")
Check(Abs(home.Width() - settings.Width()) <= 1, "navigation actions were not equal width")

ui.Close()
Print "embedded UI dashboard layout: PASS"
