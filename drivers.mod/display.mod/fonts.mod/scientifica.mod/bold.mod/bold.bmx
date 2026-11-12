' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND OFL-1.1

SuperStrict

Rem
bbdoc: Scientifica 11 bold monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Scientifica.Bold
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and SIL Open Font License 1.1"
ModuleInfo "Font: Scientifica 11 bold 2.3"
ModuleInfo "Font source: https://github.com/oppiliappan/scientifica"

Import Embedded.Drivers.Display.Font
Incbin "scientifica_bold.ebf"

Private
Global cachedFont:TBitmapFont

Public
Function ScientificaBoldFont:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("scientifica_bold.ebf"), ..
		IncbinLen("scientifica_bold.ebf"))
	Return cachedFont
End Function
?

