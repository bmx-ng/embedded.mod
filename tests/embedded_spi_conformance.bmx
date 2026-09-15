SuperStrict

Import BRL.StandardIO
Import Embedded.Hardware.SPI

Local passed:Int = SPIControllerCount() > 0
passed :& SPIDefaultController() >= SPIUnavailableController
Local defaultRX:UInt = SPIDefaultRXPin()
Local defaultTX:UInt = SPIDefaultTXPin()
Local defaultClock:UInt = SPIDefaultClockPin()
Local defaultCS:UInt = SPIDefaultChipSelectPin()
passed :& defaultRX = SPIUnavailablePin Or defaultRX < 256
passed :& defaultTX = SPIUnavailablePin Or defaultTX < 256
passed :& defaultClock = SPIUnavailablePin Or defaultClock < 256
passed :& defaultCS = SPIUnavailablePin Or defaultCS < 256

Local byteValue:Byte
Local shortValue:Short
passed :& SPIConfigurePins(-1, 0, 1, 2) = False
passed :& SPIInit(-1, 1000000) = 0
passed :& SPISetBaudrate(-1, 2000000) = 0
passed :& SPIGetBaudrate(-1) = 0
passed :& SPISetFormat(-1, 8, SPIClockPolarity0, SPIClockPhase0, SPIBitOrderMSBFirst) = False
passed :& SPIWriteBlocking(-1, Varptr byteValue, 1) = SPIErrorInvalidArgument
passed :& SPIReadBlocking(-1, $ff, Varptr byteValue, 1) = SPIErrorInvalidArgument
passed :& SPIWrite16Blocking(-1, Varptr shortValue, 1) = SPIErrorInvalidArgument
passed :& SPIDeinit(-1) = False

If passed Then
	Print "Embedded SPI conformance test passed"
Else
	Print "Embedded SPI conformance test failed"
End If
