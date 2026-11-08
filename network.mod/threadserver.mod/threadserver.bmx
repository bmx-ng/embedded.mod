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

' SRP server state: 0 disabled, 1 running, 2 stopped (OpenThread values).
Function ThreadServiceServerEnable:Int(enabled:Int = True)
	Return _ThreadServiceServerEnable(enabled)
End Function

Function ThreadServiceServerState:Int()
	Return _ThreadServiceServerState()
End Function

?
