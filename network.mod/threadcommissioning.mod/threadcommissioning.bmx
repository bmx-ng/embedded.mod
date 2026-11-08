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

Const ThreadCommissionerDisabled:Int = 0
Const ThreadCommissionerPetition:Int = 1
Const ThreadCommissionerActive:Int = 2
Const ThreadJoinerIdle:Int = -61
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

' Factory EUI-64 used to authorize this device on a Commissioner.
Function ThreadFactoryEui64:String()
	Local bytes:Byte[17]
	If _ThreadFactoryEui64(bytes, bytes.length) <> 16 Then Return ""
	Return String.FromUTF8Bytes(bytes, 16)
End Function

Function ThreadCommissionerStart:Int()
	Return _ThreadCommissionerStart()
End Function

Function ThreadCommissionerState:Int()
	Return _ThreadCommissionerState()
End Function

' Supply the joiner's factory EUI-64 as 16 hex digits; an empty string permits any joiner.
Function ThreadCommissionerAddJoiner:Int(eui64:String, pskd:String, timeoutSecs:UInt = 120)
	If Not eui64 Or Not pskd Or timeoutSecs = 0 Then Return -22
	Local euiBytes:Byte Ptr = eui64.ToUTF8String()
	Local pskdBytes:Byte Ptr = pskd.ToUTF8String()
	Local result:Int = _ThreadCommissionerAddJoiner(euiBytes, pskdBytes, timeoutSecs)
	MemFree(euiBytes)
	MemFree(pskdBytes)
	Return result
End Function

Function ThreadCommissionerStop:Int()
	Return _ThreadCommissionerStop()
End Function

' Starts asynchronous commissioning. Call ThreadJoinerStatus until it returns 0 or an error.
Function ThreadJoinerStart:Int(pskd:String)
	If Not pskd Then Return -22
	Local bytes:Byte Ptr = pskd.ToUTF8String()
	Local result:Int = _ThreadJoinerStart(bytes)
	MemFree(bytes)
	Return result
End Function

' 1 while joining; 0 after the commissioned network has started; negative on error.
Function ThreadJoinerStatus:Int()
	Return _ThreadJoinerStatus()
End Function

Function ThreadJoinerStop:Int()
	Return _ThreadJoinerStop()
End Function

?
