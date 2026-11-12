' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND LicenseRef-Tamzen

SuperStrict

Rem
bbdoc: Tamzen 6x12 bold monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Tamzen.Bold6x12
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and permissive Tamzen font license"
ModuleInfo "Font: Tamzen 6x12 bold current"
ModuleInfo "Font source: https://github.com/sunaku/tamzen-font"

Import Embedded.Drivers.Display.Font
Incbin "tamzen_bold6x12.ebf"

Private
Global cachedFont:TBitmapFont

Public
Function Tamzen6x12BoldFont:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("tamzen_bold6x12.ebf"), ..
		IncbinLen("tamzen_bold6x12.ebf"))
	Return cachedFont
End Function
?

