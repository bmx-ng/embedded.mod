' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND OFL-1.1

SuperStrict

Rem
bbdoc: Scientifica 11 italic monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Scientifica.Italic
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and SIL Open Font License 1.1"
ModuleInfo "Font: Scientifica 11 italic 2.3"
ModuleInfo "Font source: https://github.com/oppiliappan/scientifica"

Import Embedded.Drivers.Display.Font
Incbin "scientifica_italic.ebf"

Private
Global cachedFont:TBitmapFont

Public
Function ScientificaItalicFont:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("scientifica_italic.ebf"), ..
		IncbinLen("scientifica_italic.ebf"))
	Return cachedFont
End Function
?

