' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND OFL-1.1

SuperStrict

Rem
bbdoc: Terminus 8x14 regular monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Terminus.Regular8x14
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and SIL Open Font License 1.1"
ModuleInfo "Font: Terminus 8x14 regular 4.49.1"
ModuleInfo "Font source: https://terminus-font.sourceforge.net/"

Import Embedded.Drivers.Display.Font
Incbin "terminus_regular8x14.ebf"

Private
Global cachedFont:TBitmapFont

Public
Function Terminus8x14Font:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("terminus_regular8x14.ebf"), ..
		IncbinLen("terminus_regular8x14.ebf"))
	Return cachedFont
End Function
?

