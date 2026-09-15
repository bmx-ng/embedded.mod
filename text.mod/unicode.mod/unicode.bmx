' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional Unicode-aware String case conversion and case folding for embedded targets.
about: Importing this module enables the shared Unicode case tables. Applications
which do not import it retain the smaller ASCII-only String implementation.
End Rem
Module Embedded.Text.Unicode
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Extern "C"
	Function EnableUnicodeStringCase() = "bmx_embedded_unicode_enable"
End Extern

EnableUnicodeStringCase()
?
