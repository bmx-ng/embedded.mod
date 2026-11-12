' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND LicenseRef-Tamzen

SuperStrict

Rem
bbdoc: Tamzen 10x20 bold monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Tamzen.Bold10x20
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and permissive Tamzen font license"
ModuleInfo "Font: Tamzen 10x20 bold current"
ModuleInfo "Font source: https://github.com/sunaku/tamzen-font"

Import Embedded.Drivers.Display.Font
Incbin "tamzen_bold10x20.ebf"

Private
Global cachedFont:TBitmapFont

Public
Function Tamzen10x20BoldFont:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("tamzen_bold10x20.ebf"), ..
		IncbinLen("tamzen_bold10x20.ebf"))
	Return cachedFont
End Function
?

