' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND OFL-1.1

SuperStrict

Rem
bbdoc: ANAKRON 8x12 monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Anakron.Regular8x12
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and SIL Open Font License 1.1"
ModuleInfo "Font: ANAKRON 8x12 0.3.3"
ModuleInfo "Font source: https://github.com/molarmanful/ANAKRON"

Import Embedded.Drivers.Display.Font
Incbin "anakron_regular8x12.ebf"

Private
Global cachedFont:TBitmapFont

Public

Rem
bbdoc: Returns this module's shared bitmap-font instance.
returns: The shared read-only bitmap font.
End Rem
Function Anakron8x12Font:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("anakron_regular8x12.ebf"), ..
		IncbinLen("anakron_regular8x12.ebf"))
	Return cachedFont
End Function
?

