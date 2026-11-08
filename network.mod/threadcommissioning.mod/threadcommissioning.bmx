' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: On-mesh Thread Commissioner and Joiner commissioning.
End Rem
Module Embedded.Network.ThreadCommissioning
?nrf52 or esp32

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.System
Import Embedded.Network.Thread

Rem
bbdoc: The Commissioner is disabled.
End Rem
Const ThreadCommissionerDisabled:Int = 0
Rem
bbdoc: The Commissioner is petitioning to become active.
End Rem
Const ThreadCommissionerPetition:Int = 1
Rem
bbdoc: The Commissioner is active.
End Rem
Const ThreadCommissionerActive:Int = 2
Rem
bbdoc: No Joiner operation is active.
End Rem
Const ThreadJoinerIdle:Int = -61
Rem
bbdoc: Joiner commissioning is still in progress.
End Rem
Const ThreadJoinerPending:Int = 1


Private

Extern "C"
	Function _ThreadFactoryEui64:Int(value:Byte Ptr, capacity:Int) = "bmx_thread_factory_eui64"
	Function _ThreadCommissionerStart:Int() = "bmx_thread_commissioner_start"
	Function _ThreadCommissionerState:Int() = "bmx_thread_commissioner_state"
	Function _ThreadCommissionerAddJoiner:Int(eui64:Byte Ptr, pskd:Byte Ptr, timeout:UInt) = "bmx_thread_commissioner_add_joiner"
	Function _ThreadCommissionerStop:Int() = "bmx_thread_commissioner_stop"
	Function _ThreadJoinerStart:Int(pskd:Byte Ptr) = "bmx_thread_joiner_start"
	Function _ThreadJoinerStatus:Int() = "bmx_thread_joiner_status"
	Function _ThreadJoinerStop:Int() = "bmx_thread_joiner_stop"
End Extern

Public

Rem
bbdoc: Read this device’s factory EUI-64.
returns: Sixteen hexadecimal digits, or an empty string on error.
End Rem
Function ThreadFactoryEui64:String()
	Local bytes:Byte[17]
	If _ThreadFactoryEui64(bytes, bytes.length) <> 16 Then
		Return ""
	End If

	Return String.FromUTF8Bytes(bytes, 16)
End Function

Rem
bbdoc: Petition to become the on-mesh Commissioner.
returns: Zero on success or a negative error.
about: The node must already be attached. Poll ThreadCommissionerState for ThreadCommissionerActive.
End Rem
Function ThreadCommissionerStart:Int()
	Return _ThreadCommissionerStart()
End Function

Rem
bbdoc: Get the Commissioner state.
returns: A ThreadCommissioner* constant or a negative error.
End Rem
Function ThreadCommissionerState:Int()
	Return _ThreadCommissionerState()
End Function

Rem
bbdoc: Authorize a Joiner using its EUI-64 and PSKd.
param: Joiner factory EUI-64 as 16 hex digits, or empty to allow any device.
param: The Joiner passphrase, 6–32 permitted uppercase letters or digits.
param: How long the Joiner remains authorized, in seconds.
returns: Zero on success or a negative error.
about: An empty EUI-64 permits any Joiner with this PSKd during the timeout. Prefer an exact EUI-64 and a unique PSKd.
End Rem
Function ThreadCommissionerAddJoiner:Int(eui64:String, pskd:String, timeoutSecs:UInt = 120)
	If Not eui64 Or Not pskd Or timeoutSecs = 0 Then
		Return -22
	End If

	Local euiBytes:Byte Ptr = eui64.ToUTF8String()
	Local pskdBytes:Byte Ptr = pskd.ToUTF8String()
	Local result:Int = _ThreadCommissionerAddJoiner(euiBytes, pskdBytes, timeoutSecs)
	MemFree(euiBytes)
	MemFree(pskdBytes)
	Return result
End Function

Rem
bbdoc: End the Commissioner session.
returns: Zero on success or a negative error.
End Rem
Function ThreadCommissionerStop:Int()
	Return _ThreadCommissionerStop()
End Function

Rem
bbdoc: Begin asynchronous Joiner commissioning.
param: The Joiner passphrase, 6–32 permitted uppercase letters or digits.
returns: Zero if started or a negative error.
about: Poll ThreadJoinerStatus from the application task; then call ThreadWaitForAttached.
End Rem
Function ThreadJoinerStart:Int(pskd:String)
	If Not pskd Then
		Return -22
	End If

	Local bytes:Byte Ptr = pskd.ToUTF8String()
	Local result:Int = _ThreadJoinerStart(bytes)
	MemFree(bytes)
	Return result
End Function

Rem
bbdoc: Get Joiner commissioning progress.
returns: ThreadJoinerPending while joining, zero when credentials have started Thread, or a negative error.
End Rem
Function ThreadJoinerStatus:Int()
	Return _ThreadJoinerStatus()
End Function

Rem
bbdoc: Cancel the current Joiner attempt.
returns: Zero on success or a negative error.
End Rem
Function ThreadJoinerStop:Int()
	Return _ThreadJoinerStop()
End Function

?
