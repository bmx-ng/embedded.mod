' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Spleen font copyright (c) 2018-2026 Frederic Cambus
' SPDX-License-Identifier: Zlib AND BSD-2-Clause

SuperStrict

Rem
bbdoc: Spleen 8x16 monospaced bitmap font.
about: The complete Spleen 8x16 BDF character set is stored in firmware using
the compact EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Spleen.Size8x16
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and BSD-2-Clause"
ModuleInfo "Font: Spleen 8x16 2.2.0"
ModuleInfo "Font source: https://github.com/fcambus/spleen"

Import Embedded.Drivers.Display.Font
Incbin "spleen8x16.ebf"

Private
Global cachedFont:TBitmapFont

Public
Function Spleen8x16Font:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("spleen8x16.ebf"), ..
		IncbinLen("spleen8x16.ebf"))
	Return cachedFont
End Function
?
