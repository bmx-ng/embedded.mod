' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Spleen font copyright (c) 2018-2026 Frederic Cambus
' SPDX-License-Identifier: Zlib AND BSD-2-Clause

SuperStrict

Rem
bbdoc: Spleen 5x8 monospaced bitmap font.
about: The complete Spleen 5x8 BDF character set is stored in firmware using
the compact EBF1 representation. Spleen is distributed under the BSD 2-Clause
license; see FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Spleen.Size5x8
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and BSD-2-Clause"
ModuleInfo "Font: Spleen 5x8 2.2.0"
ModuleInfo "Font source: https://github.com/fcambus/spleen"

Import Embedded.Drivers.Display.Font

Incbin "spleen5x8.ebf"

Private
Global cachedFont:TBitmapFont

Public

Rem
bbdoc: Returns the shared Spleen 5x8 font instance.
End Rem
Function Spleen5x8Font:TBitmapFont()
	If Not cachedFont Then
		cachedFont = TBitmapFont.Create(IncbinPtr("spleen5x8.ebf"), ..
			IncbinLen("spleen5x8.ebf"))
	End If
	Return cachedFont
End Function
?
