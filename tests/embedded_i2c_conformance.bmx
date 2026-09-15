SuperStrict

Import BRL.StandardIO
Import Embedded.Hardware.I2C

Local passed:Int = I2CControllerCount() > 0
passed :& I2CDefaultController() >= I2CUnavailableController
Local defaultSDA:UInt = I2CDefaultSDAPin()
Local defaultSCL:UInt = I2CDefaultSCLPin()
passed :& defaultSDA = I2CUnavailablePin Or defaultSDA < 256
passed :& defaultSCL = I2CUnavailablePin Or defaultSCL < 256

Local byteValue:Byte
passed :& I2CConfigurePins(-1, 0, 1, False) = False
passed :& I2CInit(-1, I2CSpeedStandard) = 0
passed :& I2CSetBaudrate(-1, I2CSpeedFast) = 0
passed :& I2CWriteBlocking(-1, $40, Varptr byteValue, 1) = I2CErrorInvalidArgument
passed :& I2CReadBlocking(-1, $40, Varptr byteValue, 1) = I2CErrorInvalidArgument
passed :& I2CWriteReadTimeout(-1, $40, Varptr byteValue, 1, Varptr byteValue, 1, 1000) = I2CErrorInvalidArgument
passed :& I2CDeinit(-1) = False

If passed Then
	Print "Embedded I2C conformance test passed"
Else
	Print "Embedded I2C conformance test failed"
End If
