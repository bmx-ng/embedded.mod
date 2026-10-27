' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable wired Ethernet support for embedded targets.
about: Native driver callbacks copy link information into fixed storage.
PollSystem and WaitSystem create managed events in application context.
End Rem
Module Embedded.Network.Ethernet
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import BRL.System

Const EthernetLinkDown:Int = 0
Const EthernetLinkConnected:Int = 1
Const EthernetLinkNoIP:Int = 2
Const EthernetLinkUp:Int = 3
Const EthernetLinkFailed:Int = -1

Global EVENT_ETHERNETLINKSTATE:Int = AllocUserEventId("EthernetLinkState")
Global EthernetEventSource:Object = New TEthernetEventSource

Type TEthernetLinkState
	Field status:Int
	Field address:String
	Field netmask:String
	Field gateway:String
	Field macAddress:Byte[]
	Field speed:Int
	Field fullDuplex:Int

	Method HasLink:Int()
		Return status >= EthernetLinkConnected
	End Method

	Method IsConnected:Int()
		Return status = EthernetLinkUp
	End Method
End Type

Private

Const EthernetNativeEventLinkState:Int = 1

Type TEthernetEventSource
End Type

Extern "C"
	Function _EthernetInitialize:Int() = "bmx_embedded_ethernet_initialize"
	Function _EthernetDeinitialize:Int() = "bmx_embedded_ethernet_deinitialize"
	Function _EthernetInitialized:Int() = "bmx_embedded_ethernet_initialized"
	Function _EthernetLinkStatus:Int() = "bmx_embedded_ethernet_link_status"
	Function _EthernetService() = "bmx_embedded_ethernet_service"
	Function _EthernetTakeEvent:Int(kind:Int Var, linkStatus:Int Var, address:UInt Var, ..
		netmask:UInt Var, gateway:UInt Var, macAddress:Byte Ptr, speed:Int Var, ..
		fullDuplex:Int Var) = "bmx_embedded_ethernet_take_event"
	Function _EthernetDroppedEvents:UInt() = "bmx_embedded_ethernet_dropped_events"
	Function _EthernetIPv4Address:UInt() = "bmx_embedded_ethernet_ipv4_address"
	Function _EthernetIPv4Netmask:UInt() = "bmx_embedded_ethernet_ipv4_netmask"
	Function _EthernetIPv4Gateway:UInt() = "bmx_embedded_ethernet_ipv4_gateway"
	Function _EthernetMACAddress:Int(macAddress:Byte Ptr) = "bmx_embedded_ethernet_mac_address"
	Function _EthernetLinkSpeed:Int() = "bmx_embedded_ethernet_link_speed"
	Function _EthernetFullDuplex:Int() = "bmx_embedded_ethernet_full_duplex"
End Extern

Function _EthernetIPv4String:String(value:UInt)
	If value = 0 Then Return ""
	Return String(value & $ff) + "." + String((value Shr 8) & $ff) + "." + ..
		String((value Shr 16) & $ff) + "." + String((value Shr 24) & $ff)
End Function

Function _PollEthernet:Object(hookId:Int, data:Object, context:Object)
	_EthernetService()
	Local kind:Int, linkStatus:Int, speed:Int, fullDuplex:Int
	Local address:UInt, netmask:UInt, gateway:UInt
	Local macAddress:Byte[6]
	While _EthernetTakeEvent(kind, linkStatus, address, netmask, gateway, macAddress, speed, fullDuplex)
		If kind = EthernetNativeEventLinkState
			Local state:TEthernetLinkState = New TEthernetLinkState
			state.status = linkStatus
			state.address = _EthernetIPv4String(address)
			state.netmask = _EthernetIPv4String(netmask)
			state.gateway = _EthernetIPv4String(gateway)
			state.macAddress = New Byte[6]
			MemCopy(state.macAddress, macAddress, 6)
			state.speed = speed
			state.fullDuplex = fullDuplex
			EmitEvent(CreateEvent(EVENT_ETHERNETLINKSTATE, EthernetEventSource, linkStatus, speed, fullDuplex, 0, state))
		End If
	Wend
	Return data
End Function

Public

Function EthernetInitialize:Int()
	Return _EthernetInitialize()
End Function

Function EthernetDeinitialize:Int()
	Return _EthernetDeinitialize()
End Function

Function EthernetInitialized:Int()
	Return _EthernetInitialized()
End Function

Function EthernetLinkStatus:Int()
	Return _EthernetLinkStatus()
End Function

Function EthernetWaitForIP:Int(timeout:UInt = 15000)
	Local started:UInt = MilliSecs()
	While MilliSecs() - started < timeout
		PollSystem()
		If EthernetLinkStatus() = EthernetLinkUp Then Return 0
		Delay 10
	Wend
	Return EthernetLinkFailed
End Function

Function EthernetIPv4Address:String()
	Return _EthernetIPv4String(_EthernetIPv4Address())
End Function

Function EthernetIPv4Netmask:String()
	Return _EthernetIPv4String(_EthernetIPv4Netmask())
End Function

Function EthernetIPv4Gateway:String()
	Return _EthernetIPv4String(_EthernetIPv4Gateway())
End Function

Function EthernetMACAddress:Byte[]()
	Local value:Byte[6]
	If _EthernetMACAddress(value) <> 0 Then Return Null
	Return value
End Function

Function EthernetLinkSpeed:Int()
	Return _EthernetLinkSpeed()
End Function

Function EthernetFullDuplex:Int()
	Return _EthernetFullDuplex()
End Function

Function EthernetDroppedEvents:UInt()
	Return _EthernetDroppedEvents()
End Function

AddHook PollSystemHook, _PollEthernet
?
