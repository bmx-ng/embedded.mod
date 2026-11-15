' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.StandardIO
Import Embedded.Drivers.Display
Import Embedded.Drivers.Display.Fonts.Spleen.Size5x8
Import Embedded.Graphics2D
Import Embedded.System.Time
Import Embedded.UI

Const UIFrameBenchmarkSamples:Int = 7
Const UIFrameBenchmarkWarmups:Int = 2
Const UIFrameBenchmarkCaseCount:Int = 6
Const UIFrameBenchmarkFormat:Int = 1

?pico
Const UIFrameBenchmarkPlatform:String = "pico"
?esp32
Const UIFrameBenchmarkPlatform:String = "esp32"
?esp8266
Const UIFrameBenchmarkPlatform:String = "esp8266"
?nrf52
Const UIFrameBenchmarkPlatform:String = "nrf52"
?

Function UIFrameBenchmarkHousekeeping()
	Delay 10
End Function

Type TUIFrameBenchmark
	Field display:TDisplay
	Field frame:TDisplayBuffer
	Field ui:TUIContext
	Field graphics:TEmbedded2DContext
	Field loadGauge:TUIArcGauge
	Field history:TUISparkline
	Field progress:TUIProgressBar
	Field linkState:TUIStatusIndicator
	Field sensorState:TUIStatusIndicator
	Field storageState:TUIStatusIndicator
	Field tickIndex:Int
	Field pixelFormatName:String

	Function Create:TUIFrameBenchmark(display:TDisplay, frame:TDisplayBuffer)
		If Not display Or Not frame Then Return Null
		If frame.Width() <> display.Width() Or frame.Height() <> display.Height() Then Return Null

		Local benchmark:TUIFrameBenchmark = New TUIFrameBenchmark
		benchmark.display = display
		benchmark.frame = frame
		Select frame.Format()
			Case DisplayPixelFormatMono1
				benchmark.pixelFormatName = "mono1"
			Case DisplayPixelFormatRGB565
				benchmark.pixelFormatName = "rgb565"
			Case DisplayPixelFormatRGB888
				benchmark.pixelFormatName = "rgb888"
			Default
				benchmark.pixelFormatName = "unknown"
		End Select

		Local theme:TUITheme = TUITheme.Dark(Spleen5x8Font())
		theme.SetFont(Spleen5x8Font(), 3)
		theme.screen.background = $0b1119
		theme.progress.background = $26323d
		theme.progress.border = $71818e
		theme.progressFill.background = $20b8ea
		theme.controlActive.background = $20b8ea
		theme.controlActive.foreground = $eaffff

		benchmark.ui = TUIContext.CreateDisplayOnlyWithBuffer(frame, display, theme)
		If Not benchmark.ui Then Return Null
		benchmark.graphics = benchmark.ui.Graphics()
		benchmark.BuildScene()
		If Not benchmark.ui.Present() Then Return Null
		Return benchmark
	End Function

	Method BuildScene()
		Local page:TUIColumn = ui.Root()
		page.SetPaddingEdges(28, 18, 28, 18)
		page.SetGap(10)

		Local title:TUILabel = page.Label("Graphics2D UI frame benchmark")
		title.Style().fontScale = 4
		title.Style().foreground = $5ccfff

		Local stateRow:TUIRow = page.Row()
		stateRow.SetGap(16)
		linkState = stateRow.StatusIndicator("Network", True)
		sensorState = stateRow.StatusIndicator("Sensor", True)
		storageState = stateRow.StatusIndicator("Storage", True)

		Local content:TUIRow = page.Row()
		content.SetGrow(1)
		content.SetGap(20)

		Local gaugePanel:TUIColumn = content.Column()
		gaugePanel.SetGrow(1)
		gaugePanel.SetGap(3)
		Local gaugeTitle:TUILabel = gaugePanel.Label("SYSTEM LOAD")
		gaugeTitle.Style().foreground = $ffd84a
		loadGauge = gaugePanel.ArcGauge(0, 100, 48)
		loadGauge.SetGrow(1)
		loadGauge.SetLabel("Current")
		loadGauge.SetUnit("%")
		loadGauge.SetArcWidth(8)
		loadGauge.SetTickCount(10)

		Local historyPanel:TUIColumn = content.Column()
		historyPanel.SetGrow(2)
		historyPanel.SetGap(8)
		Local historyTitle:TUILabel = historyPanel.Label("RECENT SAMPLES")
		historyTitle.Style().foreground = $ffd84a
		history = historyPanel.Sparkline(64)
		history.SetRange(0, 100)
		history.SetGrow(1)
		For Local seed:Int = 0 Until 32
			history.AddValue(30 + (seed Mod 14) * 4)
		Next
		progress = historyPanel.ProgressBar(0, 100, 48)
		progress.SetHeight(34)

		Local metricsPanel:TUIColumn = content.Column()
		metricsPanel.SetGrow(1)
		metricsPanel.SetGap(10)
		Local metricsTitle:TUILabel = metricsPanel.Label("FRAME WORK")
		metricsTitle.Style().foreground = $ffd84a
		Local note:TUILabel = metricsPanel.Label("Retained layout~nDirty regions~nPhysical present")
		note.SetWordWrap(True)
		note.SetGrow(1)

		Local footer:TUILabel = page.Label("Deterministic display-only dashboard workload")
		footer.Style().foreground = $9bd5ff
	End Method

	Method ApplyCase(caseId:Int)
		tickIndex = tickIndex + 1
		Select caseId
			Case 0
				linkState.SetActive(Not linkState.Active())
			Case 1
				Local value:Int = 15 + (tickIndex * 17) Mod 80
				loadGauge.SetValue(value)
				progress.SetValue(100 - value)
				history.AddValue(value)
				linkState.SetActive(Not linkState.Active())
				sensorState.SetActive(Not sensorState.Active())
				storageState.SetActive(Not storageState.Active())
			Case 2
				ui.InvalidateAll()
			Case 3
				loadGauge.SetValue(15 + (tickIndex * 17) Mod 80)
			Case 4
				history.AddValue(15 + (tickIndex * 17) Mod 80)
			Case 5
				progress.SetValue(15 + (tickIndex * 17) Mod 80)
		End Select
	End Method

	Method DirtyPixels:Long()
		Local pixels:Long
		For Local index:Int = 0 Until graphics.DirtyRegionCount()
			Local x:Int, y:Int, width:Int, height:Int
			If graphics.DirtyRegion(index, x, y, width, height) Then
				pixels :+ Long(width) * height
			End If
		Next
		Return pixels
	End Method

	Method ExecuteFrame(caseId:Int, prepareUs:ULong Var, renderUs:ULong Var, ..
			presentUs:ULong Var, dirtyRegions:Int Var, dirtyPixels:Long Var)
		Local started:ULong = MonotonicMicroseconds()
		ApplyCase(caseId)
		prepareUs = MonotonicMicroseconds() - started

		started = MonotonicMicroseconds()
		If Not ui.Render() Then RuntimeError "UI frame benchmark rendered no invalid region"
		renderUs = MonotonicMicroseconds() - started
		dirtyRegions = graphics.DirtyRegionCount()
		dirtyPixels = DirtyPixels()

		started = MonotonicMicroseconds()
		If graphics.PresentDirty(display) <= 0 Then RuntimeError "UI frame benchmark present failed"
		presentUs = MonotonicMicroseconds() - started
	End Method

	Method RunSuite()
		Print "G2D_BENCH,format=" + UIFrameBenchmarkFormat + ",kind=meta,phase=ui_frame" + ..
			",platform=" + UIFrameBenchmarkPlatform + ",width=" + frame.Width() + ..
			",height=" + frame.Height() + ",pixel_format=" + pixelFormatName + ..
			",samples=" + UIFrameBenchmarkSamples + ",capabilities=" + display.Capabilities()
		For Local caseId:Int = 0 Until UIFrameBenchmarkCaseCount
			RunCase(caseId)
		Next
	End Method

	Method RunCase(caseId:Int)
		For Local warmup:Int = 0 Until UIFrameBenchmarkWarmups
			Local prepareUs:ULong, renderUs:ULong, presentUs:ULong
			Local dirtyRegions:Int, dirtyPixels:Long
			ExecuteFrame(caseId, prepareUs, renderUs, presentUs, dirtyRegions, dirtyPixels)
			UIFrameBenchmarkHousekeeping()
		Next

		Local prepareTotal:ULong, renderTotal:ULong, presentTotal:ULong, frameTotal:ULong
		Local prepareBest:ULong = $ffffffffffffffff:ULong
		Local renderBest:ULong = $ffffffffffffffff:ULong
		Local presentBest:ULong = $ffffffffffffffff:ULong
		Local frameBest:ULong = $ffffffffffffffff:ULong
		Local regionTotal:Long, pixelTotal:Long

		For Local sample:Int = 0 Until UIFrameBenchmarkSamples
			Local prepareUs:ULong, renderUs:ULong, presentUs:ULong
			Local dirtyRegions:Int, dirtyPixels:Long
			ExecuteFrame(caseId, prepareUs, renderUs, presentUs, dirtyRegions, dirtyPixels)
			Local frameUs:ULong = prepareUs + renderUs + presentUs
			prepareTotal :+ prepareUs
			renderTotal :+ renderUs
			presentTotal :+ presentUs
			frameTotal :+ frameUs
			regionTotal :+ dirtyRegions
			pixelTotal :+ dirtyPixels
			If prepareUs < prepareBest Then prepareBest = prepareUs
			If renderUs < renderBest Then renderBest = renderUs
			If presentUs < presentBest Then presentBest = presentUs
			If frameUs < frameBest Then frameBest = frameUs
			PrintSample("ui_prepare", CaseName(caseId), sample, prepareUs, dirtyRegions, dirtyPixels)
			PrintSample("ui_render", CaseName(caseId), sample, renderUs, dirtyRegions, dirtyPixels)
			PrintSample("ui_present", CaseName(caseId), sample, presentUs, dirtyRegions, dirtyPixels)
			PrintSample("ui_frame", CaseName(caseId), sample, frameUs, dirtyRegions, dirtyPixels)
			UIFrameBenchmarkHousekeeping()
		Next

		Local meanRegions:Long = regionTotal / UIFrameBenchmarkSamples
		Local meanPixels:Long = pixelTotal / UIFrameBenchmarkSamples
		PrintSummary("ui_prepare", CaseName(caseId), prepareBest, ..
			prepareTotal / UIFrameBenchmarkSamples, meanRegions, meanPixels)
		PrintSummary("ui_render", CaseName(caseId), renderBest, ..
			renderTotal / UIFrameBenchmarkSamples, meanRegions, meanPixels)
		PrintSummary("ui_present", CaseName(caseId), presentBest, ..
			presentTotal / UIFrameBenchmarkSamples, meanRegions, meanPixels)
		PrintSummary("ui_frame", CaseName(caseId), frameBest, ..
			frameTotal / UIFrameBenchmarkSamples, meanRegions, meanPixels)
		UIFrameBenchmarkHousekeeping()
	End Method

	Method PrintSample(phase:String, caseName:String, sample:Int, elapsed:ULong, ..
			dirtyRegions:Int, dirtyPixels:Long)
		Print "G2D_BENCH,format=" + UIFrameBenchmarkFormat + ",kind=sample,phase=" + phase + ..
			",platform=" + UIFrameBenchmarkPlatform + ",width=" + frame.Width() + ..
			",height=" + frame.Height() + ",pixel_format=" + pixelFormatName + ..
			",case=" + caseName + ",sample=" + sample + ",iterations=1" + ..
			",nominal_pixels=" + dirtyPixels + ",dirty_regions=" + dirtyRegions + ..
			",dirty_pixels=" + dirtyPixels + ",us=" + elapsed
	End Method

	Method PrintSummary(phase:String, caseName:String, best:ULong, mean:ULong, ..
			dirtyRegions:Long, dirtyPixels:Long)
		Print "G2D_BENCH,format=" + UIFrameBenchmarkFormat + ",kind=summary,phase=" + phase + ..
			",platform=" + UIFrameBenchmarkPlatform + ",width=" + frame.Width() + ..
			",height=" + frame.Height() + ",pixel_format=" + pixelFormatName + ..
			",case=" + caseName + ",iterations=1,nominal_pixels=" + dirtyPixels + ..
			",dirty_regions=" + dirtyRegions + ",dirty_pixels=" + dirtyPixels + ..
			",best_us=" + best + ",mean_us=" + mean
	End Method

	Method CaseName:String(caseId:Int)
		Select caseId
			Case 0 Return "single_status"
			Case 1 Return "dashboard_tick"
			Case 2 Return "full_redraw"
			Case 3 Return "arc_gauge"
			Case 4 Return "sparkline"
			Case 5 Return "progress_bar"
		End Select
		Return "unknown"
	End Method
End Type
