' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND LicenseRef-Tamzen

SuperStrict

Rem
bbdoc: Tamzen 7x13 regular monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Tamzen.Regular7x13
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and permissive Tamzen font license"
ModuleInfo "Font: Tamzen 7x13 regular current"
ModuleInfo "Font source: https://github.com/sunaku/tamzen-font"

Import Embedded.Drivers.Display.Font
Incbin "tamzen_regular7x13.ebf"

Private
Global cachedFont:TBitmapFont

Public

Rem
bbdoc: Returns this module's shared bitmap-font instance.
returns: The shared read-only bitmap font.
End Rem
Function Tamzen7x13Font:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("tamzen_regular7x13.ebf"), ..
		IncbinLen("tamzen_regular7x13.ebf"))
	Return cachedFont
End Function
?

