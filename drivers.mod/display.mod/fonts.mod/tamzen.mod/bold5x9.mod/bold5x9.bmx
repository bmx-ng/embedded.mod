' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND LicenseRef-Tamzen

SuperStrict

Rem
bbdoc: Tamzen 5x9 bold monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Tamzen.Bold5x9
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and permissive Tamzen font license"
ModuleInfo "Font: Tamzen 5x9 bold current"
ModuleInfo "Font source: https://github.com/sunaku/tamzen-font"

Import Embedded.Drivers.Display.Font
Incbin "tamzen_bold5x9.ebf"

Private
Global cachedFont:TBitmapFont

Public

Rem
bbdoc: Returns this module's shared bitmap-font instance.
returns: The shared read-only bitmap font.
End Rem
Function Tamzen5x9BoldFont:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("tamzen_bold5x9.ebf"), ..
		IncbinLen("tamzen_bold5x9.ebf"))
	Return cachedFont
End Function
?

