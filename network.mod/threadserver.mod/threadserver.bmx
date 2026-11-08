' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Host an on-mesh Thread SRP and DNS-SD server.
End Rem
Module Embedded.Network.ThreadServer
?esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System
Import Embedded.Network.Thread
Import Embedded.Network.ThreadDiscovery


Private

Extern "C"
	Function _ThreadServiceServerEnable:Int(enabled:Int) = "bmx_thread_service_server_enable"
	Function _ThreadServiceServerState:Int() = "bmx_thread_service_server_state"
End Extern

Public

Rem
bbdoc: Enable or disable the on-mesh SRP and DNS-SD server.
param: True to enable the server; False to disable it.
returns: Zero on success or a negative error.
End Rem
Function ThreadServiceServerEnable:Int(enabled:Int = True)
	Return _ThreadServiceServerEnable(enabled)
End Function

Rem
bbdoc: Get the on-mesh service server state.
returns: Zero when disabled, one when running, two when stopped, or a negative error.
End Rem
Function ThreadServiceServerState:Int()
	Return _ThreadServiceServerState()
End Function

?
