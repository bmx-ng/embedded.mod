' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Rem
bbdoc: Portable Bluetooth Low Energy discovery, central, and GATT peripheral support.
about: Native radio callbacks copy advertisement data into fixed storage.
PollSystem and WaitSystem create managed events in application context.
End Rem
Module Embedded.Network.BLE
?embedded

ModuleInfo "Version: 0.1"
ModuleInfo "License: zlib/libpng"

Import BRL.Event
Import BRL.System

Const BLEAddressPublic:Int = 0
Const BLEAddressRandom:Int = 1
Const BLEAddressPublicIdentity:Int = 2
Const BLEAddressRandomIdentity:Int = 3

Const BLEAdvertisementConnectableUndirected:Int = 0
Const BLEAdvertisementConnectableDirected:Int = 1
Const BLEAdvertisementScannableUndirected:Int = 2
Const BLEAdvertisementNonConnectableUndirected:Int = 3
Const BLEAdvertisementScanResponse:Int = 4

Const BLEAdvertisementFieldFlags:Int = $01
Const BLEAdvertisementFieldIncomplete16BitServiceUUIDs:Int = $02
Const BLEAdvertisementFieldComplete16BitServiceUUIDs:Int = $03
Const BLEAdvertisementFieldIncomplete32BitServiceUUIDs:Int = $04
Const BLEAdvertisementFieldComplete32BitServiceUUIDs:Int = $05
Const BLEAdvertisementFieldIncomplete128BitServiceUUIDs:Int = $06
Const BLEAdvertisementFieldComplete128BitServiceUUIDs:Int = $07
Const BLEAdvertisementFieldShortName:Int = $08
Const BLEAdvertisementFieldCompleteName:Int = $09
Const BLEAdvertisementFieldManufacturerData:Int = $ff

Const BLEGATTRead:UInt = $01
Const BLEGATTWrite:UInt = $02
Const BLEGATTNotify:UInt = $04
Const BLEGATTIndicate:UInt = $08
Const BLEGATTWriteWithoutResponse:UInt = $10
Const BLEGATTReadEncrypted:UInt = $20
Const BLEGATTReadAuthenticated:UInt = $40
Const BLEGATTWriteEncrypted:UInt = $80
Const BLEGATTWriteAuthenticated:UInt = $100
Const BLEGATTSubscribeEncrypted:UInt = $200
Const BLEGATTSubscribeAuthenticated:UInt = $400
Const BLEMaximumAttributeLength:UInt = 512

Const BLEIOCapabilityDisplayOnly:Int = 0
Const BLEIOCapabilityDisplayYesNo:Int = 1
Const BLEIOCapabilityKeyboardOnly:Int = 2
Const BLEIOCapabilityNone:Int = 3
Const BLEIOCapabilityKeyboardDisplay:Int = 4

Const BLEPasskeyActionNone:Int = 0
Const BLEPasskeyActionOOB:Int = 1
Const BLEPasskeyActionInput:Int = 2
Const BLEPasskeyActionDisplay:Int = 3
Const BLEPasskeyActionNumericComparison:Int = 4

Const BLEConnectionRoleCentral:Int = 0
Const BLEConnectionRolePeripheral:Int = 1

Const BLEPHY1M:Int = 1
Const BLEPHY2M:Int = 2
Const BLEPHYCoded:Int = 3
Const BLEPHYMask1M:Int = $01
Const BLEPHYMask2M:Int = $02
Const BLEPHYMaskCoded:Int = $04
Const BLEPHYMaskAny:Int = BLEPHYMask1M | BLEPHYMask2M | BLEPHYMaskCoded
Const BLEPHYCodedAny:Int = 0
Const BLEPHYCodedS2:Int = 1
Const BLEPHYCodedS8:Int = 2

Const BLECharacteristicPropertyBroadcast:Int = $01
Const BLECharacteristicPropertyRead:Int = $02
Const BLECharacteristicPropertyWriteWithoutResponse:Int = $04
Const BLECharacteristicPropertyWrite:Int = $08
Const BLECharacteristicPropertyNotify:Int = $10
Const BLECharacteristicPropertyIndicate:Int = $20
Const BLECharacteristicPropertyAuthenticatedWrite:Int = $40
Const BLECharacteristicPropertyExtended:Int = $80

Global EVENT_BLEREADY:Int = AllocUserEventId("BLEReady")
Global EVENT_BLESCANRESULT:Int = AllocUserEventId("BLEScanResult")
Global EVENT_BLESCANCOMPLETE:Int = AllocUserEventId("BLEScanComplete")
Global EVENT_BLERESET:Int = AllocUserEventId("BLEReset")
Global EVENT_BLECONNECTED:Int = AllocUserEventId("BLEConnected")
Global EVENT_BLEDISCONNECTED:Int = AllocUserEventId("BLEDisconnected")
Global EVENT_BLEADVERTISINGCOMPLETE:Int = AllocUserEventId("BLEAdvertisingComplete")
Global EVENT_BLEGATTWRITE:Int = AllocUserEventId("BLEGATTWrite")
Global EVENT_BLEGATTSUBSCRIBE:Int = AllocUserEventId("BLEGATTSubscribe")
Global EVENT_BLESERVICEDISCOVERED:Int = AllocUserEventId("BLEServiceDiscovered")
Global EVENT_BLESERVICEDISCOVERYCOMPLETE:Int = AllocUserEventId("BLEServiceDiscoveryComplete")
Global EVENT_BLECHARACTERISTICDISCOVERED:Int = AllocUserEventId("BLECharacteristicDiscovered")
Global EVENT_BLECHARACTERISTICDISCOVERYCOMPLETE:Int = AllocUserEventId("BLECharacteristicDiscoveryComplete")
Global EVENT_BLEDESCRIPTORDISCOVERED:Int = AllocUserEventId("BLEDescriptorDiscovered")
Global EVENT_BLEDESCRIPTORDISCOVERYCOMPLETE:Int = AllocUserEventId("BLEDescriptorDiscoveryComplete")
Global EVENT_BLEREADCOMPLETE:Int = AllocUserEventId("BLEReadComplete")
Global EVENT_BLEWRITECOMPLETE:Int = AllocUserEventId("BLEWriteComplete")
Global EVENT_BLENOTIFICATION:Int = AllocUserEventId("BLENotification")
Global EVENT_BLEMTUCHANGED:Int = AllocUserEventId("BLEMTUChanged")
Global EVENT_BLEGATTUPDATECOMPLETE:Int = AllocUserEventId("BLEGATTUpdateComplete")
Global EVENT_BLESECURITYCHANGED:Int = AllocUserEventId("BLESecurityChanged")
Global EVENT_BLEPASSKEYACTION:Int = AllocUserEventId("BLEPasskeyAction")
Global EVENT_BLECONNECTIONUPDATED:Int = AllocUserEventId("BLEConnectionUpdated")
Global EVENT_BLEPHYUPDATED:Int = AllocUserEventId("BLEPHYUpdated")
Global BLEEventSource:Object = New TBLEEventSource

Type TBLEAdvertisement
	Field address:Byte[]
	Field addressType:Int
	Field eventType:Int
	Field rssi:Int
	Field data:Byte[]

	Method IsConnectable:Int()
		Return eventType = BLEAdvertisementConnectableUndirected Or ..
			eventType = BLEAdvertisementConnectableDirected
	End Method

	Method IsScanResponse:Int()
		Return eventType = BLEAdvertisementScanResponse
	End Method

	Method AddressString:String()
		Return _BLEAddressString(address)
	End Method

	Method Field:Byte[](fieldType:Int)
		If Not data Then Return Null
		Local offset:Int
		While offset < data.length
			Local fieldLength:Int = data[offset]
			If fieldLength = 0 Then Exit
			Local nextOffset:Int = offset + fieldLength + 1
			If nextOffset > data.length Then Exit
			If fieldLength > 0 And data[offset + 1] = fieldType Then
				Local value:Byte[] = New Byte[fieldLength - 1]
				If value.length Then MemCopy(value, Varptr data[offset + 2], value.length)
				Return value
			End If
			offset = nextOffset
		Wend
		Return Null
	End Method

	Method LocalName:String()
		Local bytes:Byte[] = Field(BLEAdvertisementFieldCompleteName)
		If Not bytes Then bytes = Field(BLEAdvertisementFieldShortName)
		If Not bytes Then Return ""
		Return String.FromUTF8Bytes(bytes, bytes.length)
	End Method

	Method ManufacturerData:Byte[]()
		Return Field(BLEAdvertisementFieldManufacturerData)
	End Method

	Method AdvertisesService:Int(uuid:String)
		If Not uuid Then Return False
		Local start:Int
		If uuid.length > 2 And uuid[0] = 48 And (uuid[1] = 120 Or uuid[1] = 88) Then start = 2
		Local digitCount:Int
		For Local index:Int = start Until uuid.length
			If uuid[index] <> 45 Then digitCount :+ 1
		Next
		If digitCount <> 4 And digitCount <> 8 And digitCount <> 32 Then Return False
		Local canonical:Byte[] = New Byte[digitCount / 2]
		Local high:Int = -1
		Local byteIndex:Int
		For Local index:Int = start Until uuid.length
			Local character:Int = uuid[index]
			If character = 45 Then Continue
			Local nibble:Int
			If character >= 48 And character <= 57
				nibble = character - 48
			Else If character >= 65 And character <= 70
				nibble = character - 55
			Else If character >= 97 And character <= 102
				nibble = character - 87
			Else
				Return False
			End If
			If high < 0
				high = nibble
			Else
				canonical[byteIndex] = Byte((high Shl 4) | nibble)
				byteIndex :+ 1
				high = -1
			End If
		Next
		Local incompleteType:Int, completeType:Int
		Select canonical.length
			Case 2
				incompleteType = BLEAdvertisementFieldIncomplete16BitServiceUUIDs
				completeType = BLEAdvertisementFieldComplete16BitServiceUUIDs
			Case 4
				incompleteType = BLEAdvertisementFieldIncomplete32BitServiceUUIDs
				completeType = BLEAdvertisementFieldComplete32BitServiceUUIDs
			Case 16
				incompleteType = BLEAdvertisementFieldIncomplete128BitServiceUUIDs
				completeType = BLEAdvertisementFieldComplete128BitServiceUUIDs
		End Select
		Return _FieldContainsService(incompleteType, canonical) Or ..
			_FieldContainsService(completeType, canonical)
	End Method

	Method _FieldContainsService:Int(fieldType:Int, canonical:Byte[])
		Local values:Byte[] = Field(fieldType)
		If Not values Or values.length Mod canonical.length Then Return False
		For Local offset:Int = 0 Until values.length Step canonical.length
			Local matches:Int = True
			For Local index:Int = 0 Until canonical.length
				If values[offset + index] <> canonical[canonical.length - index - 1]
					matches = False
					Exit
				End If
			Next
			If matches Then Return True
		Next
		Return False
	End Method
End Type

Type TBLEConnectionEvent
	Field connectionHandle:Int
	Field status:Int
	Field reason:Int
	Field addressType:Int
	Field address:Byte[]
	Field role:Int

	Method AddressString:String()
		Return _BLEAddressString(address)
	End Method

	Method DiscoverServices:Int()
		Return _BLEDiscoverServices(connectionHandle)
	End Method

	Method Disconnect:Int()
		Return _BLEDisconnect(connectionHandle)
	End Method

	Method ExchangeMTU:Int()
		Return _BLEExchangeMTU(connectionHandle)
	End Method

	Method MTU:Int()
		Return _BLEConnectionMTU(connectionHandle)
	End Method

	Method Secure:Int()
		Return _BLESecureConnection(connectionHandle)
	End Method

	Method Security:TBLESecurityEvent()
		Return BLESecurity(connectionHandle)
	End Method

	Method Info:TBLEConnectionInfo()
		Return BLEConnectionInfo(connectionHandle)
	End Method

	Method SignalStrength:Int(value:Int Var)
		Return BLEConnectionRSSI(connectionHandle, value)
	End Method

	Method UpdateParameters:Int(minimumIntervalMicroseconds:Int, ..
			maximumIntervalMicroseconds:Int, latency:Int, supervisionTimeoutMilliseconds:Int)
		Return BLEUpdateConnectionParameters(connectionHandle, minimumIntervalMicroseconds, ..
			maximumIntervalMicroseconds, latency, supervisionTimeoutMilliseconds)
	End Method

	Method PreferPHY:Int(txPHYMask:Int, rxPHYMask:Int, codedPreference:Int = BLEPHYCodedAny)
		Return BLESetPreferredPHY(connectionHandle, txPHYMask, rxPHYMask, codedPreference)
	End Method
End Type

Type TBLEConnectionInfo
	Field connectionHandle:Int
	Field status:Int
	Field role:Int
	Field addressType:Int
	Field address:Byte[]
	Field intervalMicroseconds:Int
	Field latency:Int
	Field supervisionTimeoutMilliseconds:Int
	Field mtu:Int
	Field rssi:Int
	Field rssiStatus:Int
	Field txPHY:Int
	Field rxPHY:Int
	Field phyStatus:Int

	Method AddressString:String()
		Return _BLEAddressString(address)
	End Method
End Type

Type TBLEConnectionUpdateEvent
	Field connectionHandle:Int
	Field status:Int
	Field intervalMicroseconds:Int
	Field latency:Int
	Field supervisionTimeoutMilliseconds:Int
End Type

Type TBLEPHYEvent
	Field connectionHandle:Int
	Field status:Int
	Field txPHY:Int
	Field rxPHY:Int
End Type

Type TBLEBond
	Field index:Int
	Field status:Int
	Field addressType:Int
	Field address:Byte[]

	Method AddressString:String()
		Return _BLEAddressString(address)
	End Method

	Method Forget:Int()
		If status <> 0 Or Not address Or address.length <> 6 Then Return -1
		Return _BLEForgetBond(addressType, address)
	End Method
End Type

Type TBLEMTUEvent
	Field connectionHandle:Int
	Field mtu:Int
End Type

Type TBLESecurityEvent
	Field connectionHandle:Int
	Field status:Int
	Field encrypted:Int
	Field authenticated:Int
	Field bonded:Int
	Field keySize:Int
End Type

Type TBLEPasskeyEvent
	Field connectionHandle:Int
	Field action:Int
	Field passkey:Int

	Method Provide:Int(value:Int)
		Return _BLEProvidePasskey(connectionHandle, action, value)
	End Method

	Method Confirm:Int(accept:Int = True)
		If action <> BLEPasskeyActionNumericComparison Then Return -1
		Return _BLEConfirmPasskey(connectionHandle, accept)
	End Method
End Type

Type TBLEDiscoveryCompleteEvent
	Field connectionHandle:Int
	Field status:Int
	Field parent:Object
End Type

Type TBLEClientValueEvent
	Field connectionHandle:Int
	Field attributeHandle:Int
	Field status:Int
	Field indication:Int
	Field value:Byte[]
End Type

Type TBLEGATTUpdateEvent
	Field connectionHandle:Int
	Field characteristic:TBLEGATTCharacteristic
	Field status:Int
	Field indication:Int
	Field confirmed:Int
End Type

Type TBLEClientService
	Private
	Field _connectionHandle:Int
	Field _startHandle:Int
	Field _endHandle:Int
	Field _uuid:String

	Public
	Method New(connectionHandle:Int, startHandle:Int, endHandle:Int, uuid:String)
		_connectionHandle = connectionHandle
		_startHandle = startHandle
		_endHandle = endHandle
		_uuid = uuid
	End Method

	Method ConnectionHandle:Int()
		Return _connectionHandle
	End Method

	Method StartHandle:Int()
		Return _startHandle
	End Method

	Method EndHandle:Int()
		Return _endHandle
	End Method

	Method UUID:String()
		Return _uuid
	End Method

	Method DiscoverCharacteristics:Int()
		Return _BLEDiscoverCharacteristics(_connectionHandle, _startHandle, _endHandle)
	End Method
End Type

Type TBLEClientCharacteristic
	Private
	Field _service:TBLEClientService
	Field _definitionHandle:Int
	Field _valueHandle:Int
	Field _descriptorEndHandle:Int
	Field _properties:Int
	Field _uuid:String

	Public
	Method New(service:TBLEClientService, definitionHandle:Int, valueHandle:Int, ..
			properties:Int, uuid:String)
		_service = service
		_definitionHandle = definitionHandle
		_valueHandle = valueHandle
		_properties = properties
		_uuid = uuid
		If service Then _descriptorEndHandle = service.EndHandle()
	End Method

	Method Service:TBLEClientService()
		Return _service
	End Method

	Method DefinitionHandle:Int()
		Return _definitionHandle
	End Method

	Method ValueHandle:Int()
		Return _valueHandle
	End Method

	Method Properties:Int()
		Return _properties
	End Method

	Method UUID:String()
		Return _uuid
	End Method

	Method CanRead:Int()
		Return (_properties & BLECharacteristicPropertyRead) <> 0
	End Method

	Method CanWrite:Int()
		Return (_properties & BLECharacteristicPropertyWrite) <> 0
	End Method

	Method CanWriteWithoutResponse:Int()
		Return (_properties & BLECharacteristicPropertyWriteWithoutResponse) <> 0
	End Method

	Method CanNotify:Int()
		Return (_properties & BLECharacteristicPropertyNotify) <> 0
	End Method

	Method CanIndicate:Int()
		Return (_properties & BLECharacteristicPropertyIndicate) <> 0
	End Method

	Method _SetDescriptorEndHandle(endHandle:Int)
		_descriptorEndHandle = endHandle
	End Method

	Method DiscoverDescriptors:Int()
		If Not _service Or _descriptorEndHandle <= _valueHandle Then Return -1
		Return _BLEDiscoverDescriptors(_service.ConnectionHandle(), _valueHandle, _descriptorEndHandle)
	End Method

	Method Read:Int(offset:UInt = 0)
		If Not _service Then Return -1
		Return _BLEClientRead(_service.ConnectionHandle(), _valueHandle, offset)
	End Method

	Method Write:Int(value:Byte[], response:Int = True)
		If Not _service Then Return -1
		Local bytes:Byte Ptr, length:UInt
		If value And value.length
			bytes = value
			length = value.length
		End If
		Return _BLEClientWrite(_service.ConnectionHandle(), _valueHandle, bytes, length, response)
	End Method
End Type

Type TBLEClientDescriptor
	Private
	Field _characteristic:TBLEClientCharacteristic
	Field _handle:Int
	Field _uuid:String

	Public
	Method New(characteristic:TBLEClientCharacteristic, handle:Int, uuid:String)
		_characteristic = characteristic
		_handle = handle
		_uuid = uuid
	End Method

	Method Characteristic:TBLEClientCharacteristic()
		Return _characteristic
	End Method

	Method Handle:Int()
		Return _handle
	End Method

	Method UUID:String()
		Return _uuid
	End Method

	Method Read:Int(offset:UInt = 0)
		If Not _characteristic Or Not _characteristic.Service() Then Return -1
		Return _BLEClientRead(_characteristic.Service().ConnectionHandle(), _handle, offset)
	End Method

	Method Write:Int(value:Byte[], response:Int = True)
		If Not _characteristic Or Not _characteristic.Service() Then Return -1
		Local bytes:Byte Ptr, length:UInt
		If value And value.length
			bytes = value
			length = value.length
		End If
		Return _BLEClientWrite(_characteristic.Service().ConnectionHandle(), _handle, ..
			bytes, length, response)
	End Method

	Method SetSubscription:Int(notifications:Int = True, indications:Int = False)
		Local value:Int
		If notifications Then value :| 1
		If indications Then value :| 2
		Local bytes:Byte[] = [Byte(value), Byte(value Shr 8)]
		Return Write(bytes, True)
	End Method
End Type

Type TBLEGATTWriteEvent
	Field connectionHandle:Int
	Field characteristic:TBLEGATTCharacteristic
	Field value:Byte[]
End Type

Type TBLEGATTSubscriptionEvent
	Field connectionHandle:Int
	Field characteristic:TBLEGATTCharacteristic
	Field notifications:Int
	Field indications:Int
End Type

Type TBLEGATTService
	Private
	Field _identifier:Int
	Field _uuid:String

	Public
	Method New(identifier:Int, uuid:String)
		_identifier = identifier
		_uuid = uuid
	End Method

	Method Identifier:Int()
		Return _identifier
	End Method

	Method UUID:String()
		Return _uuid
	End Method

	Method AddCharacteristic:TBLEGATTCharacteristic(uuid:String, flags:UInt, ..
			initialValue:Byte[] = Null, capacity:UInt = BLEMaximumAttributeLength)
		If _identifier = 0 Or Not uuid Then Return Null
		Local uuidLength:Size_T
		Local uuidBytes:Byte Ptr = uuid.ToUTF8String(uuidLength)
		Local valueBytes:Byte Ptr, valueLength:UInt
		If initialValue And initialValue.length
			valueBytes = initialValue
			valueLength = initialValue.length
		End If
		Local characteristicId:Int
		_bleGATTLastError = _BLEGATTAddCharacteristic(_identifier, uuidBytes, UInt(uuidLength), ..
			flags, valueBytes, valueLength, capacity, characteristicId)
		MemFree(uuidBytes)
		If _bleGATTLastError <> 0 Or characteristicId <= 0 Or characteristicId >= _bleGATTCharacteristics.length Then Return Null
		Local characteristic:TBLEGATTCharacteristic = New TBLEGATTCharacteristic(characteristicId, uuid, capacity)
		_bleGATTCharacteristics[characteristicId] = characteristic
		Return characteristic
	End Method
End Type

Type TBLEGATTCharacteristic
	Private
	Field _identifier:Int
	Field _uuid:String
	Field _capacity:UInt

	Public
	Method New(identifier:Int, uuid:String, capacity:UInt)
		_identifier = identifier
		_uuid = uuid
		_capacity = capacity
	End Method

	Method Identifier:Int()
		Return _identifier
	End Method

	Method UUID:String()
		Return _uuid
	End Method

	Method Capacity:UInt()
		Return _capacity
	End Method

	Method SetValue:Int(value:Byte[], notifySubscribers:Int = False)
		Local bytes:Byte Ptr, length:UInt
		If value And value.length
			bytes = value
			length = value.length
		End If
		Return _BLEGATTSetValue(_identifier, bytes, length, notifySubscribers)
	End Method

	Method Value:Byte[]()
		Local length:Int
		If _BLEGATTGetValue(_identifier, Null, 0, length) <> 0 Then Return Null
		Local value:Byte[] = New Byte[length]
		If length And _BLEGATTGetValue(_identifier, value, value.length, length) <> 0 Then Return Null
		Return value
	End Method

	Method Notify:Int(connectionHandle:Int = -1)
		Return _BLEGATTNotify(_identifier, connectionHandle, False)
	End Method

	Method Indicate:Int(connectionHandle:Int)
		Return _BLEGATTNotify(_identifier, connectionHandle, True)
	End Method
End Type

Private

Const BLENativeEventReady:Int = 1
Const BLENativeEventScanResult:Int = 2
Const BLENativeEventScanComplete:Int = 3
Const BLENativeEventReset:Int = 4
Const BLENativeEventConnected:Int = 5
Const BLENativeEventDisconnected:Int = 6
Const BLENativeEventGATTWrite:Int = 7
Const BLENativeEventGATTSubscribe:Int = 8
Const BLENativeEventAdvertisingComplete:Int = 9
Const BLENativeEventServiceDiscovered:Int = 10
Const BLENativeEventServiceDiscoveryComplete:Int = 11
Const BLENativeEventCharacteristicDiscovered:Int = 12
Const BLENativeEventCharacteristicDiscoveryComplete:Int = 13
Const BLENativeEventDescriptorDiscovered:Int = 14
Const BLENativeEventDescriptorDiscoveryComplete:Int = 15
Const BLENativeEventReadComplete:Int = 16
Const BLENativeEventWriteComplete:Int = 17
Const BLENativeEventNotification:Int = 18
Const BLENativeEventMTUChanged:Int = 19
Const BLENativeEventGATTUpdateComplete:Int = 20
Const BLENativeEventSecurityChanged:Int = 21
Const BLENativeEventPasskeyAction:Int = 22
Const BLENativeEventConnectionUpdated:Int = 23
Const BLENativeEventPHYUpdated:Int = 24

Global _bleGATTCharacteristics:TBLEGATTCharacteristic[33]
Global _bleGATTLastError:Int
Global _bleClientServices:TBLEClientService[32]
Global _bleClientCharacteristics:TBLEClientCharacteristic[64]
Global _bleClientDescriptors:TBLEClientDescriptor[128]

Type TBLEEventSource
End Type

Extern "C"
	Function _BLEInitialize:Int(name:Byte Ptr, nameLength:UInt) = "bmx_embedded_ble_initialize"
	Function _BLEDeinitialize:Int() = "bmx_embedded_ble_deinitialize"
	Function _BLEInitialized:Int() = "bmx_embedded_ble_initialized"
	Function _BLEReady:Int() = "bmx_embedded_ble_ready"
	Function _BLEStartScan:Int(duration:UInt, active:Int, filterDuplicates:Int) = "bmx_embedded_ble_start_scan"
	Function _BLEStopScan:Int() = "bmx_embedded_ble_stop_scan"
	Function _BLEScanActive:Int() = "bmx_embedded_ble_scan_active"
	Function _BLEStartAdvertising:Int(serviceId:Int, duration:UInt, connectable:Int, ..
		autoRestart:Int) = "bmx_embedded_ble_start_advertising"
	Function _BLEStopAdvertising:Int() = "bmx_embedded_ble_stop_advertising"
	Function _BLEAdvertisingActive:Int() = "bmx_embedded_ble_advertising_active"
	Function _BLEConnect:Int(addressType:Int, address:Byte Ptr, timeout:UInt) = "bmx_embedded_ble_connect"
	Function _BLECancelConnect:Int() = "bmx_embedded_ble_cancel_connect"
	Function _BLEDisconnect:Int(connectionHandle:Int) = "bmx_embedded_ble_disconnect"
	Function _BLEExchangeMTU:Int(connectionHandle:Int) = "bmx_embedded_ble_exchange_mtu"
	Function _BLEConnectionMTU:Int(connectionHandle:Int) = "bmx_embedded_ble_connection_mtu"
	Function _BLEConnectionCount:Int() = "bmx_embedded_ble_connection_count"
	Function _BLEConnectionHandle:Int(index:Int, connectionHandle:Int Var) = "bmx_embedded_ble_connection_handle"
	Function _BLEConnectionInfo:Int(connectionHandle:Int, role:Int Var, addressType:Int Var, ..
		address:Byte Ptr, intervalUnits:Int Var, latency:Int Var, ..
		supervisionTimeoutUnits:Int Var) = "bmx_embedded_ble_connection_info"
	Function _BLEConnectionRSSI:Int(connectionHandle:Int, rssi:Int Var) = "bmx_embedded_ble_connection_rssi"
	Function _BLEConnectionPHY:Int(connectionHandle:Int, txPHY:Int Var, ..
		rxPHY:Int Var) = "bmx_embedded_ble_connection_phy"
	Function _BLEUpdateConnectionParameters:Int(connectionHandle:Int, ..
		minimumIntervalMicroseconds:Int, maximumIntervalMicroseconds:Int, latency:Int, ..
		supervisionTimeoutMilliseconds:Int) = "bmx_embedded_ble_update_connection_parameters"
	Function _BLESetPreferredPHY:Int(connectionHandle:Int, txPHYMask:Int, rxPHYMask:Int, ..
		codedPreference:Int) = "bmx_embedded_ble_set_preferred_phy"
	Function _BLEConfigureSecurity:Int(ioCapability:Int, bonding:Int, authentication:Int, ..
		secureConnections:Int, secureConnectionsOnly:Int) = "bmx_embedded_ble_configure_security"
	Function _BLESecureConnection:Int(connectionHandle:Int) = "bmx_embedded_ble_secure_connection"
	Function _BLESecurityState:Int(connectionHandle:Int, encrypted:Int Var, ..
		authenticated:Int Var, bonded:Int Var, keySize:Int Var) = "bmx_embedded_ble_security_state"
	Function _BLEProvidePasskey:Int(connectionHandle:Int, action:Int, passkey:Int) = "bmx_embedded_ble_provide_passkey"
	Function _BLEConfirmPasskey:Int(connectionHandle:Int, accept:Int) = "bmx_embedded_ble_confirm_passkey"
	Function _BLEBondCount:Int() = "bmx_embedded_ble_bond_count"
	Function _BLEBond:Int(index:Int, addressType:Int Var, address:Byte Ptr) = "bmx_embedded_ble_bond"
	Function _BLEForgetBond:Int(addressType:Int, address:Byte Ptr) = "bmx_embedded_ble_forget_bond"
	Function _BLEForgetAllBonds:Int() = "bmx_embedded_ble_forget_all_bonds"
	Function _BLEDiscoverServices:Int(connectionHandle:Int) = "bmx_embedded_ble_discover_services"
	Function _BLEDiscoverCharacteristics:Int(connectionHandle:Int, startHandle:Int, ..
		endHandle:Int) = "bmx_embedded_ble_discover_characteristics"
	Function _BLEDiscoverDescriptors:Int(connectionHandle:Int, valueHandle:Int, ..
		endHandle:Int) = "bmx_embedded_ble_discover_descriptors"
	Function _BLEClientRead:Int(connectionHandle:Int, attributeHandle:Int, ..
		offset:UInt) = "bmx_embedded_ble_client_read"
	Function _BLEClientWrite:Int(connectionHandle:Int, attributeHandle:Int, value:Byte Ptr, ..
		valueLength:UInt, response:Int) = "bmx_embedded_ble_client_write"
	Function _BLEGATTReset:Int() = "bmx_embedded_ble_gatt_reset"
	Function _BLEGATTAddService:Int(uuid:Byte Ptr, uuidLength:UInt, serviceId:Int Var) = "bmx_embedded_ble_gatt_add_service"
	Function _BLEGATTAddCharacteristic:Int(serviceId:Int, uuid:Byte Ptr, uuidLength:UInt, ..
		flags:UInt, value:Byte Ptr, valueLength:UInt, capacity:UInt, ..
		characteristicId:Int Var) = "bmx_embedded_ble_gatt_add_characteristic"
	Function _BLEGATTSetValue:Int(characteristicId:Int, value:Byte Ptr, valueLength:UInt, ..
		notifySubscribers:Int) = "bmx_embedded_ble_gatt_set_value"
	Function _BLEGATTGetValue:Int(characteristicId:Int, value:Byte Ptr, capacity:UInt, ..
		valueLength:Int Var) = "bmx_embedded_ble_gatt_get_value"
	Function _BLEGATTNotify:Int(characteristicId:Int, connectionHandle:Int, ..
		indication:Int) = "bmx_embedded_ble_gatt_notify"
	Function _BLETakeEvent:Int(kind:Int Var, status:Int Var, addressType:Int Var, ..
		address:Byte Ptr, eventType:Int Var, rssi:Int Var, data:Byte Ptr, ..
		dataLength:Int Var, connectionHandle:Int Var, attributeId:Int Var, ..
		notifications:Int Var, indications:Int Var, attributeEnd:Int Var, ..
		parentAttribute:Int Var, properties:Int Var) = "bmx_embedded_ble_take_event"
	Function _BLEDroppedEvents:UInt() = "bmx_embedded_ble_dropped_events"
End Extern

Function _StoreBLEClientService:TBLEClientService(service:TBLEClientService)
	For Local index:Int = 0 Until _bleClientServices.length
		If Not _bleClientServices[index]
			_bleClientServices[index] = service
			Return service
		End If
	Next
	Return service
End Function

Function _FindBLEClientService:TBLEClientService(connectionHandle:Int, startHandle:Int)
	For Local service:TBLEClientService = EachIn _bleClientServices
		If service And service.ConnectionHandle() = connectionHandle And ..
				service.StartHandle() = startHandle Then Return service
	Next
End Function

Function _StoreBLEClientCharacteristic:TBLEClientCharacteristic(characteristic:TBLEClientCharacteristic)
	Local previous:TBLEClientCharacteristic
	Local available:Int = -1
	For Local index:Int = 0 Until _bleClientCharacteristics.length
		Local existing:TBLEClientCharacteristic = _bleClientCharacteristics[index]
		If existing
			If existing.Service() = characteristic.Service() And ..
					existing.DefinitionHandle() < characteristic.DefinitionHandle() And ..
					(Not previous Or existing.DefinitionHandle() > previous.DefinitionHandle())
				previous = existing
			End If
		Else If available < 0
			available = index
		End If
	Next
	If previous Then previous._SetDescriptorEndHandle(characteristic.DefinitionHandle() - 1)
	If available >= 0 Then _bleClientCharacteristics[available] = characteristic
	Return characteristic
End Function

Function _FindBLEClientCharacteristic:TBLEClientCharacteristic(connectionHandle:Int, valueHandle:Int)
	For Local characteristic:TBLEClientCharacteristic = EachIn _bleClientCharacteristics
		If characteristic And characteristic.Service() And ..
				characteristic.Service().ConnectionHandle() = connectionHandle And ..
				characteristic.ValueHandle() = valueHandle Then Return characteristic
	Next
End Function

Function _StoreBLEClientDescriptor:TBLEClientDescriptor(descriptor:TBLEClientDescriptor)
	For Local index:Int = 0 Until _bleClientDescriptors.length
		If Not _bleClientDescriptors[index]
			_bleClientDescriptors[index] = descriptor
			Return descriptor
		End If
	Next
	Return descriptor
End Function

Function _FindBLEClientAttribute:Object(connectionHandle:Int, attributeHandle:Int)
	Local characteristic:TBLEClientCharacteristic = _FindBLEClientCharacteristic(connectionHandle, attributeHandle)
	If characteristic Then Return characteristic
	For Local descriptor:TBLEClientDescriptor = EachIn _bleClientDescriptors
		If descriptor And descriptor.Characteristic() And descriptor.Characteristic().Service() And ..
				descriptor.Characteristic().Service().ConnectionHandle() = connectionHandle And ..
				descriptor.Handle() = attributeHandle Then Return descriptor
	Next
	Return BLEEventSource
End Function

Function _ClearBLEClientConnection(connectionHandle:Int)
	For Local index:Int = 0 Until _bleClientDescriptors.length
		Local descriptor:TBLEClientDescriptor = _bleClientDescriptors[index]
		If descriptor And descriptor.Characteristic() And descriptor.Characteristic().Service() And ..
				descriptor.Characteristic().Service().ConnectionHandle() = connectionHandle Then _bleClientDescriptors[index] = Null
	Next
	For Local index:Int = 0 Until _bleClientCharacteristics.length
		Local characteristic:TBLEClientCharacteristic = _bleClientCharacteristics[index]
		If characteristic And characteristic.Service() And ..
				characteristic.Service().ConnectionHandle() = connectionHandle Then _bleClientCharacteristics[index] = Null
	Next
	For Local index:Int = 0 Until _bleClientServices.length
		Local service:TBLEClientService = _bleClientServices[index]
		If service And service.ConnectionHandle() = connectionHandle Then _bleClientServices[index] = Null
	Next
End Function

Function _ClearBLEClients()
	For Local index:Int = 0 Until _bleClientDescriptors.length
		_bleClientDescriptors[index] = Null
	Next
	For Local index:Int = 0 Until _bleClientCharacteristics.length
		_bleClientCharacteristics[index] = Null
	Next
	For Local index:Int = 0 Until _bleClientServices.length
		_bleClientServices[index] = Null
	Next
End Function

Function _PollBLE:Object(hookId:Int, hookData:Object, context:Object)
	Local kind:Int, status:Int, addressType:Int, eventType:Int, rssi:Int, dataLength:Int
	Local connectionHandle:Int, attributeId:Int, notifications:Int, indications:Int
	Local attributeEnd:Int, parentAttribute:Int, properties:Int
	Local nativeAddress:Byte[6]
	Local nativeData:Byte[BLEMaximumAttributeLength]
	While _BLETakeEvent(kind, status, addressType, nativeAddress, eventType, rssi, nativeData, ..
			dataLength, connectionHandle, attributeId, notifications, indications, ..
			attributeEnd, parentAttribute, properties)
		Select kind
			Case BLENativeEventReady
				EmitEvent(CreateEvent(EVENT_BLEREADY, BLEEventSource))
			Case BLENativeEventScanResult
				Local advertisement:TBLEAdvertisement = New TBLEAdvertisement
				advertisement.address = New Byte[6]
				MemCopy(advertisement.address, nativeAddress, 6)
				advertisement.addressType = addressType
				advertisement.eventType = eventType
				advertisement.rssi = rssi
				advertisement.data = New Byte[dataLength]
				If dataLength Then MemCopy(advertisement.data, nativeData, dataLength)
				EmitEvent(CreateEvent(EVENT_BLESCANRESULT, BLEEventSource, rssi, addressType, eventType, 0, advertisement))
			Case BLENativeEventScanComplete
				EmitEvent(CreateEvent(EVENT_BLESCANCOMPLETE, BLEEventSource, status))
			Case BLENativeEventReset
				EmitEvent(CreateEvent(EVENT_BLERESET, BLEEventSource, status))
			Case BLENativeEventConnected, BLENativeEventDisconnected
				Local connection:TBLEConnectionEvent = New TBLEConnectionEvent
				connection.connectionHandle = connectionHandle
				connection.status = status
				connection.reason = status
				connection.addressType = addressType
				connection.role = properties
				connection.address = New Byte[6]
				MemCopy(connection.address, nativeAddress, 6)
				If kind = BLENativeEventConnected
					connection.reason = 0
					EmitEvent(CreateEvent(EVENT_BLECONNECTED, BLEEventSource, status, addressType, connectionHandle, 0, connection))
				Else
					EmitEvent(CreateEvent(EVENT_BLEDISCONNECTED, BLEEventSource, status, addressType, connectionHandle, 0, connection))
					_ClearBLEClientConnection(connectionHandle)
				End If
			Case BLENativeEventGATTWrite
				Local writeEvent:TBLEGATTWriteEvent = New TBLEGATTWriteEvent
				writeEvent.connectionHandle = connectionHandle
				If attributeId > 0 And attributeId < _bleGATTCharacteristics.length Then writeEvent.characteristic = _bleGATTCharacteristics[attributeId]
				writeEvent.value = New Byte[dataLength]
				If dataLength Then MemCopy(writeEvent.value, nativeData, dataLength)
				Local writeSource:Object = writeEvent.characteristic
				If Not writeSource Then writeSource = BLEEventSource
				EmitEvent(CreateEvent(EVENT_BLEGATTWRITE, writeSource, dataLength, 0, connectionHandle, attributeId, writeEvent))
			Case BLENativeEventGATTSubscribe
				Local subscription:TBLEGATTSubscriptionEvent = New TBLEGATTSubscriptionEvent
				subscription.connectionHandle = connectionHandle
				If attributeId > 0 And attributeId < _bleGATTCharacteristics.length Then subscription.characteristic = _bleGATTCharacteristics[attributeId]
				subscription.notifications = notifications
				subscription.indications = indications
				Local subscriptionSource:Object = subscription.characteristic
				If Not subscriptionSource Then subscriptionSource = BLEEventSource
				EmitEvent(CreateEvent(EVENT_BLEGATTSUBSCRIBE, subscriptionSource, notifications, indications, connectionHandle, attributeId, subscription))
			Case BLENativeEventAdvertisingComplete
				EmitEvent(CreateEvent(EVENT_BLEADVERTISINGCOMPLETE, BLEEventSource, status))
			Case BLENativeEventServiceDiscovered
				Local serviceUUID:String = String.FromUTF8Bytes(nativeData, dataLength)
				Local clientService:TBLEClientService = New TBLEClientService(connectionHandle, ..
					attributeId, attributeEnd, serviceUUID)
				_StoreBLEClientService(clientService)
				EmitEvent(CreateEvent(EVENT_BLESERVICEDISCOVERED, clientService, 0, 0, ..
					connectionHandle, attributeId, clientService))
			Case BLENativeEventServiceDiscoveryComplete
				Local serviceComplete:TBLEDiscoveryCompleteEvent = New TBLEDiscoveryCompleteEvent
				serviceComplete.connectionHandle = connectionHandle
				serviceComplete.status = status
				EmitEvent(CreateEvent(EVENT_BLESERVICEDISCOVERYCOMPLETE, BLEEventSource, status, ..
					0, connectionHandle, 0, serviceComplete))
			Case BLENativeEventCharacteristicDiscovered
				Local parentService:TBLEClientService = _FindBLEClientService(connectionHandle, parentAttribute)
				Local characteristicUUID:String = String.FromUTF8Bytes(nativeData, dataLength)
				Local clientCharacteristic:TBLEClientCharacteristic = New TBLEClientCharacteristic( ..
					parentService, attributeId, attributeEnd, properties, characteristicUUID)
				_StoreBLEClientCharacteristic(clientCharacteristic)
				EmitEvent(CreateEvent(EVENT_BLECHARACTERISTICDISCOVERED, clientCharacteristic, ..
					properties, 0, connectionHandle, attributeEnd, clientCharacteristic))
			Case BLENativeEventCharacteristicDiscoveryComplete
				Local characteristicComplete:TBLEDiscoveryCompleteEvent = New TBLEDiscoveryCompleteEvent
				characteristicComplete.connectionHandle = connectionHandle
				characteristicComplete.status = status
				characteristicComplete.parent = _FindBLEClientService(connectionHandle, parentAttribute)
				Local characteristicCompleteSource:Object = characteristicComplete.parent
				If Not characteristicCompleteSource Then characteristicCompleteSource = BLEEventSource
				EmitEvent(CreateEvent(EVENT_BLECHARACTERISTICDISCOVERYCOMPLETE, ..
					characteristicCompleteSource, status, 0, connectionHandle, parentAttribute, ..
					characteristicComplete))
			Case BLENativeEventDescriptorDiscovered
				Local parentCharacteristic:TBLEClientCharacteristic = ..
					_FindBLEClientCharacteristic(connectionHandle, parentAttribute)
				Local descriptorUUID:String = String.FromUTF8Bytes(nativeData, dataLength)
				Local clientDescriptor:TBLEClientDescriptor = New TBLEClientDescriptor( ..
					parentCharacteristic, attributeId, descriptorUUID)
				_StoreBLEClientDescriptor(clientDescriptor)
				EmitEvent(CreateEvent(EVENT_BLEDESCRIPTORDISCOVERED, clientDescriptor, 0, 0, ..
					connectionHandle, attributeId, clientDescriptor))
			Case BLENativeEventDescriptorDiscoveryComplete
				Local descriptorComplete:TBLEDiscoveryCompleteEvent = New TBLEDiscoveryCompleteEvent
				descriptorComplete.connectionHandle = connectionHandle
				descriptorComplete.status = status
				descriptorComplete.parent = _FindBLEClientCharacteristic(connectionHandle, parentAttribute)
				Local descriptorCompleteSource:Object = descriptorComplete.parent
				If Not descriptorCompleteSource Then descriptorCompleteSource = BLEEventSource
				EmitEvent(CreateEvent(EVENT_BLEDESCRIPTORDISCOVERYCOMPLETE, ..
					descriptorCompleteSource, status, 0, connectionHandle, parentAttribute, ..
					descriptorComplete))
			Case BLENativeEventReadComplete, BLENativeEventWriteComplete, ..
					BLENativeEventNotification
				Local valueEvent:TBLEClientValueEvent = New TBLEClientValueEvent
				valueEvent.connectionHandle = connectionHandle
				valueEvent.attributeHandle = attributeId
				valueEvent.status = status
				valueEvent.indication = indications
				valueEvent.value = New Byte[dataLength]
				If dataLength Then MemCopy(valueEvent.value, nativeData, dataLength)
				Local valueSource:Object = _FindBLEClientAttribute(connectionHandle, attributeId)
				If kind = BLENativeEventReadComplete
					EmitEvent(CreateEvent(EVENT_BLEREADCOMPLETE, valueSource, status, dataLength, ..
						connectionHandle, attributeId, valueEvent))
				Else If kind = BLENativeEventWriteComplete
					EmitEvent(CreateEvent(EVENT_BLEWRITECOMPLETE, valueSource, status, 0, ..
						connectionHandle, attributeId, valueEvent))
				Else
					EmitEvent(CreateEvent(EVENT_BLENOTIFICATION, valueSource, indications, dataLength, ..
						connectionHandle, attributeId, valueEvent))
				End If
			Case BLENativeEventMTUChanged
				Local mtuEvent:TBLEMTUEvent = New TBLEMTUEvent
				mtuEvent.connectionHandle = connectionHandle
				mtuEvent.mtu = attributeEnd
				EmitEvent(CreateEvent(EVENT_BLEMTUCHANGED, BLEEventSource, attributeEnd, 0, ..
					connectionHandle, 0, mtuEvent))
			Case BLENativeEventGATTUpdateComplete
				Local updateEvent:TBLEGATTUpdateEvent = New TBLEGATTUpdateEvent
				updateEvent.connectionHandle = connectionHandle
				updateEvent.status = status
				updateEvent.indication = indications
				updateEvent.confirmed = properties
				If attributeId > 0 And attributeId < _bleGATTCharacteristics.length Then ..
					updateEvent.characteristic = _bleGATTCharacteristics[attributeId]
				Local updateSource:Object = updateEvent.characteristic
				If Not updateSource Then updateSource = BLEEventSource
				EmitEvent(CreateEvent(EVENT_BLEGATTUPDATECOMPLETE, updateSource, status, ..
					properties, connectionHandle, attributeId, updateEvent))
			Case BLENativeEventSecurityChanged
				Local securityEvent:TBLESecurityEvent = New TBLESecurityEvent
				securityEvent.connectionHandle = connectionHandle
				securityEvent.status = status
				securityEvent.encrypted = notifications
				securityEvent.authenticated = indications
				securityEvent.bonded = properties
				securityEvent.keySize = attributeEnd
				EmitEvent(CreateEvent(EVENT_BLESECURITYCHANGED, BLEEventSource, status, ..
					properties, connectionHandle, attributeEnd, securityEvent))
			Case BLENativeEventPasskeyAction
				Local passkeyEvent:TBLEPasskeyEvent = New TBLEPasskeyEvent
				passkeyEvent.connectionHandle = connectionHandle
				passkeyEvent.action = eventType
				passkeyEvent.passkey = status
				EmitEvent(CreateEvent(EVENT_BLEPASSKEYACTION, BLEEventSource, eventType, ..
					status, connectionHandle, 0, passkeyEvent))
			Case BLENativeEventConnectionUpdated
				Local connectionUpdate:TBLEConnectionUpdateEvent = New TBLEConnectionUpdateEvent
				connectionUpdate.connectionHandle = connectionHandle
				connectionUpdate.status = status
				connectionUpdate.intervalMicroseconds = attributeId * 1250
				connectionUpdate.latency = attributeEnd
				connectionUpdate.supervisionTimeoutMilliseconds = parentAttribute * 10
				EmitEvent(CreateEvent(EVENT_BLECONNECTIONUPDATED, BLEEventSource, status, ..
					connectionUpdate.intervalMicroseconds, connectionHandle, 0, connectionUpdate))
			Case BLENativeEventPHYUpdated
				Local phyEvent:TBLEPHYEvent = New TBLEPHYEvent
				phyEvent.connectionHandle = connectionHandle
				phyEvent.status = status
				phyEvent.txPHY = eventType
				phyEvent.rxPHY = properties
				EmitEvent(CreateEvent(EVENT_BLEPHYUPDATED, BLEEventSource, status, eventType, ..
					connectionHandle, properties, phyEvent))
		End Select
	Wend
	Return hookData
End Function

Public

Function BLEInitialize:Int(deviceName:String = "")
	Local wasInitialized:Int = BLEInitialized()
	Local nameLength:Size_T
	Local nameBytes:Byte Ptr
	If deviceName Then nameBytes = deviceName.ToUTF8String(nameLength)
	Local result:Int = _BLEInitialize(nameBytes, UInt(nameLength))
	If nameBytes Then MemFree(nameBytes)
	If result = 0 And Not wasInitialized Then _ClearBLEClients()
	Return result
End Function

Function BLEDeinitialize:Int()
	Local result:Int = _BLEDeinitialize()
	If result = 0 Then _ClearBLEClients()
	Return result
End Function

Function BLEInitialized:Int()
	Return _BLEInitialized()
End Function

Function BLEReady:Int()
	Return _BLEReady()
End Function

Function BLEWaitReady:Int(timeout:UInt = 5000)
	Local started:UInt = MilliSecs()
	While Not BLEReady() And MilliSecs() - started < timeout
		PollSystem()
		Delay 1
	Wend
	Return BLEReady()
End Function

Function BLEStartScan:Int(duration:UInt = 10000, active:Int = True, ..
		filterDuplicates:Int = True)
	Return _BLEStartScan(duration, active, filterDuplicates)
End Function

Function BLEStopScan:Int()
	Return _BLEStopScan()
End Function

Function BLEScanActive:Int()
	Return _BLEScanActive()
End Function

Function BLEStartAdvertising:Int(service:TBLEGATTService = Null, duration:UInt = 0, ..
		connectable:Int = True, autoRestart:Int = True)
	Local serviceId:Int
	If service Then serviceId = service.Identifier()
	Return _BLEStartAdvertising(serviceId, duration, connectable, autoRestart)
End Function

Function BLEStopAdvertising:Int()
	Return _BLEStopAdvertising()
End Function

Function BLEAdvertisingActive:Int()
	Return _BLEAdvertisingActive()
End Function

Function BLEConnect:Int(address:Byte[], addressType:Int, timeout:UInt = 30000)
	If Not address Or address.length <> 6 Then Return -1
	Return _BLEConnect(addressType, address, timeout)
End Function

Function BLEConnectAdvertisement:Int(advertisement:TBLEAdvertisement, timeout:UInt = 30000)
	If Not advertisement Then Return -1
	Return BLEConnect(advertisement.address, advertisement.addressType, timeout)
End Function

Function BLECancelConnect:Int()
	Return _BLECancelConnect()
End Function

Function BLEDisconnect:Int(connectionHandle:Int)
	Return _BLEDisconnect(connectionHandle)
End Function

Function BLEExchangeMTU:Int(connectionHandle:Int)
	Return _BLEExchangeMTU(connectionHandle)
End Function

Function BLEConnectionMTU:Int(connectionHandle:Int)
	Return _BLEConnectionMTU(connectionHandle)
End Function

Function BLEConnectionCount:Int()
	Return _BLEConnectionCount()
End Function

Function BLEConnectionAt:TBLEConnectionInfo(index:Int)
	Local connectionHandle:Int = -1
	Local result:Int = _BLEConnectionHandle(index, connectionHandle)
	If result <> 0
		Local failed:TBLEConnectionInfo = New TBLEConnectionInfo
		failed.connectionHandle = connectionHandle
		failed.status = result
		Return failed
	End If
	Return BLEConnectionInfo(connectionHandle)
End Function

Function BLEConnectionInfo:TBLEConnectionInfo(connectionHandle:Int)
	Local info:TBLEConnectionInfo = New TBLEConnectionInfo
	info.connectionHandle = connectionHandle
	info.address = New Byte[6]
	Local intervalUnits:Int, supervisionTimeoutUnits:Int
	info.status = _BLEConnectionInfo(connectionHandle, info.role, info.addressType, info.address, ..
		intervalUnits, info.latency, supervisionTimeoutUnits)
	If info.status = 0
		info.intervalMicroseconds = intervalUnits * 1250
		info.supervisionTimeoutMilliseconds = supervisionTimeoutUnits * 10
		info.mtu = BLEConnectionMTU(connectionHandle)
		info.rssiStatus = _BLEConnectionRSSI(connectionHandle, info.rssi)
		info.phyStatus = _BLEConnectionPHY(connectionHandle, info.txPHY, info.rxPHY)
	End If
	Return info
End Function

Function BLEConnectionRSSI:Int(connectionHandle:Int, rssi:Int Var)
	Return _BLEConnectionRSSI(connectionHandle, rssi)
End Function

Function BLEConnectionPHY:TBLEPHYEvent(connectionHandle:Int)
	Local phy:TBLEPHYEvent = New TBLEPHYEvent
	phy.connectionHandle = connectionHandle
	phy.status = _BLEConnectionPHY(connectionHandle, phy.txPHY, phy.rxPHY)
	Return phy
End Function

Function BLEUpdateConnectionParameters:Int(connectionHandle:Int, ..
		minimumIntervalMicroseconds:Int, maximumIntervalMicroseconds:Int, latency:Int, ..
		supervisionTimeoutMilliseconds:Int)
	Return _BLEUpdateConnectionParameters(connectionHandle, minimumIntervalMicroseconds, ..
		maximumIntervalMicroseconds, latency, supervisionTimeoutMilliseconds)
End Function

Function BLESetPreferredPHY:Int(connectionHandle:Int, txPHYMask:Int = BLEPHYMaskAny, ..
		rxPHYMask:Int = BLEPHYMaskAny, codedPreference:Int = BLEPHYCodedAny)
	Return _BLESetPreferredPHY(connectionHandle, txPHYMask, rxPHYMask, codedPreference)
End Function

Function BLEConfigureSecurity:Int(ioCapability:Int = BLEIOCapabilityNone, bonding:Int = True, ..
		authentication:Int = False, secureConnections:Int = True, ..
		secureConnectionsOnly:Int = False)
	Return _BLEConfigureSecurity(ioCapability, bonding, authentication, secureConnections, ..
		secureConnectionsOnly)
End Function

Function BLESecureConnection:Int(connectionHandle:Int)
	Return _BLESecureConnection(connectionHandle)
End Function

Function BLESecurity:TBLESecurityEvent(connectionHandle:Int)
	Local state:TBLESecurityEvent = New TBLESecurityEvent
	state.connectionHandle = connectionHandle
	state.status = _BLESecurityState(connectionHandle, state.encrypted, state.authenticated, ..
		state.bonded, state.keySize)
	Return state
End Function

Function BLEProvidePasskey:Int(connectionHandle:Int, action:Int, passkey:Int)
	Return _BLEProvidePasskey(connectionHandle, action, passkey)
End Function

Function BLEConfirmPasskey:Int(connectionHandle:Int, accept:Int = True)
	Return _BLEConfirmPasskey(connectionHandle, accept)
End Function

Function BLEBondCount:Int()
	Return _BLEBondCount()
End Function

Function BLEBondAt:TBLEBond(index:Int)
	Local bond:TBLEBond = New TBLEBond
	bond.index = index
	bond.address = New Byte[6]
	bond.status = _BLEBond(index, bond.addressType, bond.address)
	Return bond
End Function

Function BLEForgetAllBonds:Int()
	Return _BLEForgetAllBonds()
End Function

Function _BLEAddressString:String(address:Byte[])
	If Not address Or address.length <> 6 Then Return ""
	Local digits:String = "0123456789ABCDEF"
	Local result:String
	For Local index:Int = 0 Until address.length
		If index Then result :+ ":"
		Local value:Int = address[index]
		Local high:Int = (value Shr 4) & $f
		Local low:Int = value & $f
		result :+ digits[high..high + 1] + digits[low..low + 1]
	Next
	Return result
End Function

Function BLEMaximumWriteWithoutResponse:Int(connectionHandle:Int)
	Local mtu:Int = BLEConnectionMTU(connectionHandle)
	If mtu <= 3 Then Return 0
	Return mtu - 3
End Function

Function BLEDiscoverServices:Int(connectionHandle:Int)
	Return _BLEDiscoverServices(connectionHandle)
End Function

Function BLEGATTReset:Int()
	Local result:Int = _BLEGATTReset()
	_bleGATTLastError = result
	If result = 0
		For Local index:Int = 0 Until _bleGATTCharacteristics.length
			_bleGATTCharacteristics[index] = Null
		Next
	End If
	Return result
End Function

Function CreateBLEGATTService:TBLEGATTService(uuid:String)
	If Not uuid Then Return Null
	Local uuidLength:Size_T
	Local uuidBytes:Byte Ptr = uuid.ToUTF8String(uuidLength)
	Local serviceId:Int
	_bleGATTLastError = _BLEGATTAddService(uuidBytes, UInt(uuidLength), serviceId)
	MemFree(uuidBytes)
	If _bleGATTLastError <> 0 Or serviceId <= 0 Then Return Null
	Return New TBLEGATTService(serviceId, uuid)
End Function

Function BLEGATTLastError:Int()
	Return _bleGATTLastError
End Function

Function BLEDroppedEvents:UInt()
	Return _BLEDroppedEvents()
End Function

AddHook PollSystemHook, _PollBLE
?
