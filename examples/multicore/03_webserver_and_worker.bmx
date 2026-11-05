' ESP32: keep the HTTP server on the owner task and calculate on core 1.
SuperStrict

Framework BRL.StandardIO
Import BRL.EventQueue
Import Embedded.Network.WiFi
Import Embedded.Network.HTTPServer
Import Embedded.Runtime.Worker
Import Embedded.System.Time

' Set these in a private copy of this file before flashing.
Const NetworkName:String = "<ssid>"
Const NetworkPassword:String = "<password>"

Global workerResult:Int
Global publishedResult:Int

Function Calculate()
    Local total:Int
    For Local number:Int = 1 To 1000
        total :+ number
    Next
    SleepMilliseconds(500)
    workerResult = total
End Function

Type TStatusHandler Implements IHTTPHandler
    Method Handle(request:THTTPRequest, response:THTTPResponse)
        response.Json("{~qstatus~q:~qok~q,~qresult~q:" + publishedResult + "}")
    End Method
End Type

If NetworkName = "<ssid>" Then RuntimeError "Set Wi-Fi credentials in a private copy"
If WiFiInitialize(WiFiCountryUK) <> 0 Then RuntimeError "Wi-Fi initialization failed"
If WiFiConnectWait(NetworkName, NetworkPassword) <> 0 Then RuntimeError "Wi-Fi connection failed"

Local server:THTTPServer = THTTPServer.Create()
If Not server Then RuntimeError "Could not create HTTP server"
If Not server.Route("GET", "/status", New TStatusHandler) Then RuntimeError "Could not add route"
If Not server.Start() Then RuntimeError server.LastError()

If Not StartManagedWorker(Calculate) Then RuntimeError "Could not start worker"
Print "Open http://" + WiFiIPv4Address() + ":8080/status"

While True
    PollEvent()
    Local result:Int = JoinManagedWorker(0)
    If result = 1 Then
        ' The finished worker can no longer write workerResult.
        publishedResult = workerResult
    ElseIf result = -1 Then
        RuntimeError "Worker failed"
    End If
    server.Service(4)
    Delay(1)
Wend
