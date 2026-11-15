' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Spleen font copyright (c) 2018-2026 Frederic Cambus
' SPDX-License-Identifier: Zlib AND BSD-2-Clause

SuperStrict

Rem
bbdoc: Spleen 12x24 monospaced bitmap font.
about: The complete Spleen 12x24 BDF character set is stored in firmware using
the compact EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Spleen.Size12x24
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and BSD-2-Clause"
ModuleInfo "Font: Spleen 12x24 2.2.0"
ModuleInfo "Font source: https://github.com/fcambus/spleen"

Import Embedded.Drivers.Display.Font
Incbin "spleen12x24.ebf"

Private
Global cachedFont:TBitmapFont

Public

Rem
bbdoc: Returns this module's shared bitmap-font instance.
returns: The shared read-only bitmap font.
End Rem
Function Spleen12x24Font:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("spleen12x24.ebf"), ..
		IncbinLen("spleen12x24.ebf"))
	Return cachedFont
End Function
?
