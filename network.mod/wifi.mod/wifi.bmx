' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable wireless LAN station support for embedded targets.
about: Native radio callbacks copy data into fixed storage. PollSystem and
WaitSystem create the corresponding managed events in application context.
End Rem
Module Embedded.Network.WiFi
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import BRL.System

Const WiFiCountryWorldwide:UInt = $00005858
Const WiFiCountryUK:UInt = $00004247
Const WiFiCountryUSA:UInt = $00005355

Const WiFiLinkDown:Int = 0
Const WiFiLinkJoined:Int = 1
Const WiFiLinkNoIP:Int = 2
Const WiFiLinkUp:Int = 3
Const WiFiLinkFailed:Int = -1
Const WiFiLinkNoNetwork:Int = -2
Const WiFiLinkBadAuthentication:Int = -3

Const WiFiScanSecurityOpen:Int = 0
Const WiFiScanSecurityWEP:Int = $01
Const WiFiScanSecurityWPA:Int = $02
Const WiFiScanSecurityWPA2:Int = $04
Const WiFiScanSecurityWPA3:Int = $08

Const WiFiAuthenticationOpen:UInt = 0
Const WiFiAuthenticationWPATKIPPSK:UInt = 1
Const WiFiAuthenticationWPA2AESPSK:UInt = 2
Const WiFiAuthenticationWPA2MixedPSK:UInt = 3
Const WiFiAuthenticationWPA3SAEAESPSK:UInt = 4
Const WiFiAuthenticationWPA3WPA2AESPSK:UInt = 5

Global EVENT_WIFISCANRESULT:Int = AllocUserEventId("WiFiScanResult")
Global EVENT_WIFISCANCOMPLETE:Int = AllocUserEventId("WiFiScanComplete")
Global EVENT_WIFILINKSTATE:Int = AllocUserEventId("WiFiLinkState")
Global WiFiEventSource:Object = New TWiFiEventSource

Type TWiFiNetwork
	Field ssid:String
	Field bssid:Byte[]
	Field channel:Int
	Field rssi:Int
	Field security:Int

	Method IsOpen:Int()
		Return security = WiFiScanSecurityOpen
	End Method
End Type

Type TWiFiLinkState
	Field status:Int
	Field address:String
	Field netmask:String
	Field gateway:String

	Method IsConnected:Int()
		Return status = WiFiLinkUp
	End Method
End Type

Private

Const WiFiNativeEventScanResult:Int = 1
Const WiFiNativeEventScanComplete:Int = 2
Const WiFiNativeEventLinkState:Int = 3

Type TWiFiEventSource
End Type

Extern "C"
	Function _WiFiInitialize:Int(country:UInt) = "bmx_embedded_wifi_initialize"
	Function _WiFiDeinitialize:Int() = "bmx_embedded_wifi_deinitialize"
	Function _WiFiInitialized:Int() = "bmx_embedded_wifi_initialized"
	Function _WiFiStartScan:Int() = "bmx_embedded_wifi_start_scan"
	Function _WiFiConnect:Int(ssid:Byte Ptr, ssidLength:UInt, password:Byte Ptr, ..
		passwordLength:UInt, authentication:UInt) = "bmx_embedded_wifi_connect"
	Function _WiFiDisconnect:Int() = "bmx_embedded_wifi_disconnect"
	Function _WiFiScanActive:Int() = "bmx_embedded_wifi_scan_active"
	Function _WiFiLinkStatus:Int() = "bmx_embedded_wifi_link_status"
	Function _WiFiService() = "bmx_embedded_wifi_service"
	Function _WiFiTakeEvent:Int(kind:Int Var, ssid:Byte Ptr, ssidLength:Int Var, ..
		bssid:Byte Ptr, channel:Int Var, rssi:Int Var, security:Int Var, ..
		linkStatus:Int Var, address:UInt Var, netmask:UInt Var, gateway:UInt Var) = "bmx_embedded_wifi_take_event"
	Function _WiFiDroppedEvents:UInt() = "bmx_embedded_wifi_dropped_events"
	Function _WiFiIPv4Address:UInt() = "bmx_embedded_wifi_ipv4_address"
	Function _WiFiIPv4Netmask:UInt() = "bmx_embedded_wifi_ipv4_netmask"
	Function _WiFiIPv4Gateway:UInt() = "bmx_embedded_wifi_ipv4_gateway"
End Extern

Function _IPv4String:String(value:UInt)
	If value = 0 Then Return ""
	Return String(value & $ff) + "." + String((value Shr 8) & $ff) + "." + ..
		String((value Shr 16) & $ff) + "." + String((value Shr 24) & $ff)
End Function

Function _PollWiFi:Object(hookId:Int, data:Object, context:Object)
	_WiFiService()
	Local kind:Int, ssidLength:Int, channel:Int, rssi:Int, security:Int, linkStatus:Int
	Local address:UInt, netmask:UInt, gateway:UInt
	Local ssidBytes:Byte[32]
	Local bssidBytes:Byte[6]
	While _WiFiTakeEvent(kind, ssidBytes, ssidLength, bssidBytes, channel, rssi, security, ..
			linkStatus, address, netmask, gateway)
		Select kind
			Case WiFiNativeEventScanResult
				Local network:TWiFiNetwork = New TWiFiNetwork
				network.ssid = String.FromUTF8Bytes(ssidBytes, ssidLength)
				network.bssid = New Byte[6]
				MemCopy(network.bssid, bssidBytes, 6)
				network.channel = channel
				network.rssi = rssi
				network.security = security
				EmitEvent(CreateEvent(EVENT_WIFISCANRESULT, WiFiEventSource, security, 0, channel, rssi, network))
			Case WiFiNativeEventScanComplete
				EmitEvent(CreateEvent(EVENT_WIFISCANCOMPLETE, WiFiEventSource))
			Case WiFiNativeEventLinkState
				Local state:TWiFiLinkState = New TWiFiLinkState
				state.status = linkStatus
				state.address = _IPv4String(address)
				state.netmask = _IPv4String(netmask)
				state.gateway = _IPv4String(gateway)
				EmitEvent(CreateEvent(EVENT_WIFILINKSTATE, WiFiEventSource, linkStatus, 0, 0, 0, state))
		End Select
	Wend
	Return data
End Function

Public

Function WiFiCountryCode:UInt(code:String, revision:UInt = 0)
	If code.length <> 2 Or revision > $ffff Then Return 0
	Local upper:String = code.ToUpper()
	Local first:Int = upper[0], second:Int = upper[1]
	If first < Asc("A") Or first > Asc("Z") Or second < Asc("A") Or second > Asc("Z") Then Return 0
	Return UInt(first) | (UInt(second) Shl 8) | (revision Shl 16)
End Function

Function WiFiInitialize:Int(country:UInt = WiFiCountryWorldwide)
	Return _WiFiInitialize(country)
End Function

Function WiFiDeinitialize:Int()
	Return _WiFiDeinitialize()
End Function

Function WiFiInitialized:Int()
	Return _WiFiInitialized()
End Function

Function WiFiStartScan:Int()
	Return _WiFiStartScan()
End Function

Function WiFiConnect:Int(ssid:String, password:String = "", ..
		authentication:UInt = WiFiAuthenticationWPA2MixedPSK)
	If Not ssid Then Return -5
	Local ssidLength:Size_T, passwordLength:Size_T
	Local ssidBytes:Byte Ptr = ssid.ToUTF8String(ssidLength)
	Local passwordBytes:Byte Ptr
	If password Then passwordBytes = password.ToUTF8String(passwordLength)
	Local result:Int = _WiFiConnect(ssidBytes, UInt(ssidLength), passwordBytes, UInt(passwordLength), authentication)
	MemFree(ssidBytes)
	If passwordBytes Then MemFree(passwordBytes)
	Return result
End Function

Function WiFiConnectWait:Int(ssid:String, password:String = "", ..
		authentication:UInt = WiFiAuthenticationWPA2MixedPSK, attempts:Int = 3, ..
		timeout:UInt = 15000, retryDelay:UInt = 1000)
	If attempts < 1 Then Return -5
	Local lastStatus:Int = WiFiLinkDown
	For Local attempt:Int = 1 To attempts
		Local result:Int = WiFiConnect(ssid, password, authentication)
		If result <> 0 Then Return result
		Local started:UInt = MilliSecs()
		While MilliSecs() - started < timeout
			PollSystem()
			lastStatus = WiFiLinkStatus()
			If lastStatus = WiFiLinkUp Then Return 0
			If lastStatus < 0 Then Exit
			Delay 10
		Wend
		If attempt < attempts Then
			WiFiDisconnect()
			Delay retryDelay
		End If
	Next
	If lastStatus < 0 Then Return lastStatus
	Return WiFiLinkFailed
End Function

Function WiFiDisconnect:Int()
	Return _WiFiDisconnect()
End Function

Function WiFiScanActive:Int()
	Return _WiFiScanActive()
End Function

Function WiFiLinkStatus:Int()
	Return _WiFiLinkStatus()
End Function

Function WiFiIPv4Address:String()
	Return _IPv4String(_WiFiIPv4Address())
End Function

Function WiFiIPv4Netmask:String()
	Return _IPv4String(_WiFiIPv4Netmask())
End Function

Function WiFiIPv4Gateway:String()
	Return _IPv4String(_WiFiIPv4Gateway())
End Function

Function WiFiDroppedEvents:UInt()
	Return _WiFiDroppedEvents()
End Function

Function WiFiDroppedScanResults:UInt()
	Return WiFiDroppedEvents()
End Function

AddHook PollSystemHook, _PollWiFi
?
