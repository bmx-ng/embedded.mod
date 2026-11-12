' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Spleen font copyright (c) 2018-2026 Frederic Cambus
' SPDX-License-Identifier: Zlib AND BSD-2-Clause

SuperStrict

Rem
bbdoc: Spleen 32x64 monospaced bitmap font.
about: The complete Spleen 32x64 BDF character set is stored in firmware using
the compact EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Spleen.Size32x64
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and BSD-2-Clause"
ModuleInfo "Font: Spleen 32x64 2.2.0"
ModuleInfo "Font source: https://github.com/fcambus/spleen"

Import Embedded.Drivers.Display.Font
Incbin "spleen32x64.ebf"

Private
Global cachedFont:TBitmapFont

Public
Function Spleen32x64Font:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("spleen32x64.ebf"), ..
		IncbinLen("spleen32x64.ebf"))
	Return cachedFont
End Function
?
