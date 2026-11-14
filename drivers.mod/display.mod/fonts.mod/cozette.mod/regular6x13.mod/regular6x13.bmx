' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND MIT

SuperStrict

Rem
bbdoc: Cozette 6x13 monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Cozette.Regular6x13
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and MIT"
ModuleInfo "Font: Cozette 6x13 1.30.0"
ModuleInfo "Font source: https://github.com/the-moonwitch/Cozette"

Import Embedded.Drivers.Display.Font
Incbin "cozette_regular6x13.ebf"

Private
Global cachedFont:TBitmapFont

Public

Rem
bbdoc: Returns this module's shared bitmap-font instance.
returns: The shared read-only bitmap font.
End Rem
Function Cozette6x13Font:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("cozette_regular6x13.ebf"), ..
		IncbinLen("cozette_regular6x13.ebf"))
	Return cachedFont
End Function
?

