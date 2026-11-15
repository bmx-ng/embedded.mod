' BlitzMax wrapper copyright (c) 2026 Bruce A Henderson and contributors
' Font copyright and licence: see FONT-LICENSE.txt
' SPDX-License-Identifier: Zlib AND OFL-1.1

SuperStrict

Rem
bbdoc: Terminus 14x28 bold monospaced bitmap font.
about: The upstream bitmap character set is stored in firmware using the compact
EBF1 representation. See FONT-LICENSE.txt in this module.
End Rem
Module Embedded.Drivers.Display.Fonts.Terminus.Bold14x28
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng and SIL Open Font License 1.1"
ModuleInfo "Font: Terminus 14x28 bold 4.49.1"
ModuleInfo "Font source: https://terminus-font.sourceforge.net/"

Import Embedded.Drivers.Display.Font
Incbin "terminus_bold14x28.ebf"

Private
Global cachedFont:TBitmapFont

Public

Rem
bbdoc: Returns this module's shared bitmap-font instance.
returns: The shared read-only bitmap font.
End Rem
Function Terminus14x28BoldFont:TBitmapFont()
	If Not cachedFont Then cachedFont = TBitmapFont.Create(IncbinPtr("terminus_bold14x28.ebf"), ..
		IncbinLen("terminus_bold14x28.ebf"))
	Return cachedFont
End Function
?

