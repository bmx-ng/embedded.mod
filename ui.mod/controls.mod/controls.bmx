' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Optional standard control constructors for Embedded.UI.
about: Import this module when an interface creates buttons, lists, selection
controls, sliders, dials, dialogs or tabs. Display-only dashboards which use
only passive presentation widgets can omit it, allowing the linker to discard
the concrete control family.
End Rem
Module Embedded.UI.Controls
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import Embedded.UI

InstallStandardUIControls()
?
