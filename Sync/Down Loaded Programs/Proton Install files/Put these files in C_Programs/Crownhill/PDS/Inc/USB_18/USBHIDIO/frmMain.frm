VERSION 5.00
Begin VB.Form frmMain 
   Caption         =   "USB Complete"
   ClientHeight    =   5340
   ClientLeft      =   252
   ClientTop       =   336
   ClientWidth     =   6132
   LinkTopic       =   "Form1"
   ScaleHeight     =   5340
   ScaleWidth      =   6132
   Begin VB.Timer tmrContinuousDataCollect 
      Left            =   120
      Top             =   3960
   End
   Begin VB.Frame fraSendAndReceive 
      Caption         =   "Send and Receive Data"
      Height          =   1692
      Left            =   3960
      TabIndex        =   7
      Top             =   120
      Width           =   2052
      Begin VB.CommandButton cmdContinuous 
         Caption         =   "Continuous"
         Height          =   372
         Left            =   360
         TabIndex        =   9
         Top             =   1080
         Width           =   1452
      End
      Begin VB.CommandButton cmdOnce 
         Caption         =   "Once"
         Height          =   372
         Left            =   360
         TabIndex        =   8
         Top             =   360
         Width           =   1452
      End
   End
   Begin VB.Frame fraBytesReceived 
      Caption         =   "Bytes Received"
      Height          =   1692
      Left            =   2400
      TabIndex        =   4
      Top             =   120
      Width           =   1452
      Begin VB.TextBox txtBytesReceived 
         Height          =   732
         Left            =   360
         MultiLine       =   -1  'True
         TabIndex        =   5
         Top             =   600
         Width           =   732
      End
   End
   Begin VB.Frame fraBytesToSend 
      Caption         =   "Bytes to Send"
      Height          =   1692
      Left            =   120
      TabIndex        =   1
      Top             =   120
      Width           =   2172
      Begin VB.CheckBox chkAutoincrement 
         Caption         =   "Autoincrement values"
         Height          =   372
         Left            =   240
         TabIndex        =   6
         Top             =   1200
         Width           =   2412
      End
      Begin VB.ComboBox cboByte1 
         Height          =   288
         Left            =   240
         Style           =   2  'Dropdown List
         TabIndex        =   3
         Top             =   840
         Width           =   1212
      End
      Begin VB.ComboBox cboByte0 
         Height          =   288
         Left            =   240
         Style           =   2  'Dropdown List
         TabIndex        =   2
         Top             =   360
         Width           =   1212
      End
   End
   Begin VB.Timer tmrDelay 
      Enabled         =   0   'False
      Left            =   120
      Top             =   11400
   End
   Begin VB.ListBox lstResults 
      Height          =   3312
      Left            =   120
      TabIndex        =   0
      Top             =   1920
      Width           =   5892
   End
End
Attribute VB_Name = "frmMain"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

'Project: usbhidio.vbp
'Version: 2.0
'Date: 12/18/00
'
'Purpose: demonstrates USB communications with a HID-class device
'Description:
'Finds an attached device that matches specific vendor and product IDs.
'Retrieves the device's capabilities.
'Sends two bytes to the device using Input reports.
'Receives two bytes from the device in Output reports.
'(For testing, the example device firmware adds 1 to the received bytes
'and sends them back.)
'A list box displays the data sent and received,
'along with error and status messages.
'Combo boxes enable you to select data to send, and to select 1-time or
'continuous transfers.

'The companion device firmware is usbhidio.asm,
'for Cypress Semiconductor's CY7C63001 USB Microcontroller,
'or enchid.asm for Cypress' Encore series.
'But you can use any generic HID that sends and receives data
'and has matching Vendor and Product IDs and sends and receives Input and Output reports.
'For more information about HIDs and USB, visit Lakeview Research at http://www.lvr.com .

'Send comments, bug reports, etc. to jan@lvr.com .

'Changes and updates:
'The major change to V2.0 is the use of overlapped ReadFiles.

'About overlapped I/O
'
'Reading HID Input reports is done with the API function ReadFile.
'Non-overlapped ReadFile is a blocking call. If the device doesn't return the
'expected amount of data, the application hangs and waits endlessly.
'
'With overlapped I/O, the call to ReadFile returns immediately. The application uses
'WaitForSingleObject to be notified either that the data has arrived or that a timeout
'has occurred.
'WaitForSingleObject blocks the application thread but specifies a timeout value so the
'application's thread isn't blocked forever.
'
'This application has been tested on Windows 98 SE and Windows 2000.

Dim bAlertable As Long
Dim Capabilities As HIDP_CAPS
Dim DataString As String
Dim DetailData As Long
Dim DetailDataBuffer() As Byte
Dim DeviceAttributes As HIDD_ATTRIBUTES
Dim DevicePathName As String
Dim DeviceInfoSet As Long
Dim ErrorString As String
Dim EventObject As Long
Dim HIDHandle As Long
Dim HIDOverlapped As OVERLAPPED
Dim LastDevice As Boolean
Dim MyDeviceDetected As Boolean
Dim MyDeviceInfoData As SP_DEVINFO_DATA
Dim MyDeviceInterfaceDetailData As SP_DEVICE_INTERFACE_DETAIL_DATA
Dim MyDeviceInterfaceData As SP_DEVICE_INTERFACE_DATA
Dim Needed As Long
Dim OutputReportData(7) As Byte
Dim PreparsedData As Long
Dim ReadHandle As Long
Dim Result As Long
Dim Security As SECURITY_ATTRIBUTES
Dim Timeout As Boolean

'Set these to match the values in the device's firmware and INF file.
'0925h is Lakeview Research's vendor ID.
Const MyVendorID = &H925
Const MyProductID = &H1234

Function FindTheHid() As Boolean
'Makes a series of API calls to locate the desired HID-class device.
'Returns True if the device is detected, False if not detected.

Dim Count As Integer
Dim GUIDString As String
Dim HidGuid As GUID
Dim MemberIndex As Long

LastDevice = False
MyDeviceDetected = False

'Values for SECURITY_ATTRIBUTES structure:
Security.lpSecurityDescriptor = 0
Security.bInheritHandle = True
Security.nLength = Len(Security)

'******************************************************************************
'HidD_GetHidGuid
'Get the GUID for all system HIDs.
'Returns: the GUID in HidGuid.
'The routine doesn't return a value in Result
'but the routine is declared as a function for consistency with the other API calls.
'******************************************************************************

Result = HidD_GetHidGuid(HidGuid)
Call DisplayResultOfAPICall("GetHidGuid")

'Display the GUID.
GUIDString = _
    Hex$(HidGuid.Data1) & "-" & _
    Hex$(HidGuid.Data2) & "-" & _
    Hex$(HidGuid.Data3) & "-"

For Count = 0 To 7
    'Ensure that each of the 8 bytes in the GUID displays two characters.
    If HidGuid.Data4(Count) >= &H10 Then
        GUIDString = GUIDString & Hex$(HidGuid.Data4(Count)) & " "
    Else
        GUIDString = GUIDString & "0" & Hex$(HidGuid.Data4(Count)) & " "
    End If
Next Count

lstResults.AddItem "  GUID for system HIDs: " & GUIDString

'******************************************************************************
'SetupDiGetClassDevs
'Returns: a handle to a device information set for all installed devices.
'Requires: the HidGuid returned in GetHidGuid.
'******************************************************************************

DeviceInfoSet = SetupDiGetClassDevs _
    (HidGuid, _
    vbNullString, _
    0, _
    (DIGCF_PRESENT Or DIGCF_DEVICEINTERFACE))
    
Call DisplayResultOfAPICall("SetupDiClassDevs")
DataString = GetDataString(DeviceInfoSet, 32)

'******************************************************************************
'SetupDiEnumDeviceInterfaces
'On return, MyDeviceInterfaceData contains the handle to a
'SP_DEVICE_INTERFACE_DATA structure for a detected device.
'Requires:
'the DeviceInfoSet returned in SetupDiGetClassDevs.
'the HidGuid returned in GetHidGuid.
'An index to specify a device.
'******************************************************************************

'Begin with 0 and increment until no more devices are detected.
MemberIndex = 0

Do
    'The cbSize element of the MyDeviceInterfaceData structure must be set to
    'the structure's size in bytes. The size is 28 bytes.
    MyDeviceInterfaceData.cbSize = LenB(MyDeviceInterfaceData)
    Result = SetupDiEnumDeviceInterfaces _
        (DeviceInfoSet, _
        0, _
        HidGuid, _
        MemberIndex, _
        MyDeviceInterfaceData)
    
    Call DisplayResultOfAPICall("SetupDiEnumDeviceInterfaces")
    If Result = 0 Then LastDevice = True
    
    'If a device exists, display the information returned.
    If Result <> 0 Then
        lstResults.AddItem "  DeviceInfoSet for device #" & CStr(MemberIndex) & ": "
        lstResults.AddItem "  cbSize = " & CStr(MyDeviceInterfaceData.cbSize)
        lstResults.AddItem _
            "  InterfaceClassGuid.Data1 = " & Hex$(MyDeviceInterfaceData.InterfaceClassGuid.Data1)
        lstResults.AddItem _
            "  InterfaceClassGuid.Data2 = " & Hex$(MyDeviceInterfaceData.InterfaceClassGuid.Data2)
        lstResults.AddItem _
            "  InterfaceClassGuid.Data3 = " & Hex$(MyDeviceInterfaceData.InterfaceClassGuid.Data3)
        lstResults.AddItem _
            "  Flags = " & Hex$(MyDeviceInterfaceData.Flags)
    
        
        '******************************************************************************
        'SetupDiGetDeviceInterfaceDetail
        'Returns: an SP_DEVICE_INTERFACE_DETAIL_DATA structure
        'containing information about a device.
        'To retrieve the information, call this function twice.
        'The first time returns the size of the structure in Needed.
        'The second time returns a pointer to the data in DeviceInfoSet.
        'Requires:
        'A DeviceInfoSet returned by SetupDiGetClassDevs and
        'an SP_DEVICE_INTERFACE_DATA structure returned by SetupDiEnumDeviceInterfaces.
        '*******************************************************************************
        
        MyDeviceInfoData.cbSize = Len(MyDeviceInfoData)
        Result = SetupDiGetDeviceInterfaceDetail _
           (DeviceInfoSet, _
           MyDeviceInterfaceData, _
           0, _
           0, _
           Needed, _
           0)
        
        DetailData = Needed
            
        Call DisplayResultOfAPICall("SetupDiGetDeviceInterfaceDetail")
        lstResults.AddItem "  (OK to say too small)"
        lstResults.AddItem "  Required buffer size for the data: " & Needed
        
        'Store the structure's size.
        MyDeviceInterfaceDetailData.cbSize = _
            Len(MyDeviceInterfaceDetailData)
        
        'Use a byte array to allocate memory for
        'the MyDeviceInterfaceDetailData structure
        ReDim DetailDataBuffer(Needed)
        'Store cbSize in the first four bytes of the array.
        Call RtlMoveMemory _
            (DetailDataBuffer(0), _
            MyDeviceInterfaceDetailData, _
            4)
        
        'Call SetupDiGetDeviceInterfaceDetail again.
        'This time, pass the address of the first element of DetailDataBuffer
        'and the returned required buffer size in DetailData.
        Result = SetupDiGetDeviceInterfaceDetail _
           (DeviceInfoSet, _
           MyDeviceInterfaceData, _
           VarPtr(DetailDataBuffer(0)), _
           DetailData, _
           Needed, _
           0)
        
        Call DisplayResultOfAPICall(" Result of second call: ")
        lstResults.AddItem "  MyDeviceInterfaceDetailData.cbSize: " & _
            CStr(MyDeviceInterfaceDetailData.cbSize)
        
        'Convert the byte array to a string.
        DevicePathName = CStr(DetailDataBuffer())
        'Convert to Unicode.
        DevicePathName = StrConv(DevicePathName, vbUnicode)
        'Strip cbSize (4 bytes) from the beginning.
        DevicePathName = Right$(DevicePathName, Len(DevicePathName) - 4)
        lstResults.AddItem "  Device pathname: "
        lstResults.AddItem "    " & DevicePathName
                
        '******************************************************************************
        'CreateFile
        'Returns: a handle that enables reading and writing to the device.
        'Requires:
        'The DevicePathName returned by SetupDiGetDeviceInterfaceDetail.
        '******************************************************************************
    
        HIDHandle = CreateFile _
            (DevicePathName, _
            GENERIC_READ Or GENERIC_WRITE, _
            (FILE_SHARE_READ Or FILE_SHARE_WRITE), _
            Security, _
            OPEN_EXISTING, _
            0&, _
            0)
            
        Call DisplayResultOfAPICall("CreateFile")
        lstResults.AddItem "  Returned handle: " & Hex$(HIDHandle) & "h"
        
        'Now we can find out if it's the device we're looking for.
        
        '******************************************************************************
        'HidD_GetAttributes
        'Requests information from the device.
        'Requires: The handle returned by CreateFile.
        'Returns: an HIDD_ATTRIBUTES structure containing
        'the Vendor ID, Product ID, and Product Version Number.
        'Use this information to determine if the detected device
        'is the one we're looking for.
        '******************************************************************************
        
        'Set the Size property to the number of bytes in the structure.
        DeviceAttributes.Size = LenB(DeviceAttributes)
        Result = HidD_GetAttributes _
            (HIDHandle, _
            DeviceAttributes)
            
        Call DisplayResultOfAPICall("HidD_GetAttributes")
        If Result <> 0 Then
            lstResults.AddItem "  HIDD_ATTRIBUTES structure filled without error."
        Else
            lstResults.AddItem "  Error in filling HIDD_ATTRIBUTES structure."
        End If
    
        lstResults.AddItem "  Structure size: " & DeviceAttributes.Size
        lstResults.AddItem "  Vendor ID: " & Hex$(DeviceAttributes.VendorID)
        lstResults.AddItem "  Product ID: " & Hex$(DeviceAttributes.ProductID)
        lstResults.AddItem "  Version Number: " & Hex$(DeviceAttributes.VersionNumber)
        
        'Find out if the device matches the one we're looking for.
        If (DeviceAttributes.VendorID = MyVendorID) And _
            (DeviceAttributes.ProductID = MyProductID) Then
                'It's the desired device.
                lstResults.AddItem "  My device detected"
                MyDeviceDetected = True
        Else
                MyDeviceDetected = False
                'If it's not the one we want, close its handle.
                Result = CloseHandle _
                    (HIDHandle)
                DisplayResultOfAPICall ("CloseHandle")
        End If
End If
    'Keep looking until we find the device or there are no more left to examine.
    MemberIndex = MemberIndex + 1
Loop Until (LastDevice = True) Or (MyDeviceDetected = True)

'Free the memory reserved for the DeviceInfoSet returned by SetupDiGetClassDevs.
Result = SetupDiDestroyDeviceInfoList _
    (DeviceInfoSet)
Call DisplayResultOfAPICall("DestroyDeviceInfoList")

If MyDeviceDetected = True Then
    FindTheHid = True
    'Learn the capabilities of the device
     Call GetDeviceCapabilities
    'Get another handle for the overlapped ReadFiles.
    ReadHandle = CreateFile _
            (DevicePathName, _
            (GENERIC_READ Or GENERIC_WRITE), _
            (FILE_SHARE_READ Or FILE_SHARE_WRITE), _
            Security, _
            OPEN_EXISTING, _
            FILE_FLAG_OVERLAPPED, _
            0)

    Call DisplayResultOfAPICall("CreateFile, ReadHandle")
    lstResults.AddItem "  Returned handle: " & Hex$(ReadHandle) & "h"
    Call PrepareForOverlappedTransfer
Else
    lstResults.AddItem " Device not found."
End If

End Function

Private Function GetDataString _
    (Address As Long, _
    Bytes As Long) _
As String

'Retrieves a string of length Bytes from memory, beginning at Address.
'Adapted from Dan Appleman's "Win32 API Puzzle Book"

Dim Offset As Integer
Dim Result$
Dim ThisByte As Byte

For Offset = 0 To Bytes - 1
    Call RtlMoveMemory(ByVal VarPtr(ThisByte), ByVal Address + Offset, 1)
    If (ThisByte And &HF0) = 0 Then
        Result$ = Result$ & "0"
    End If
    Result$ = Result$ & Hex$(ThisByte) & " "
Next Offset

GetDataString = Result$
End Function

Private Function GetErrorString _
    (ByVal LastError As Long) _
As String

'Returns the error message for the last error.
'Adapted from Dan Appleman's "Win32 API Puzzle Book"

Dim Bytes As Long
Dim ErrorString As String
ErrorString = String$(129, 0)
Bytes = FormatMessage _
    (FORMAT_MESSAGE_FROM_SYSTEM, _
    0&, _
    LastError, _
    0, _
    ErrorString$, _
    128, _
    0)
    
'Subtract two characters from the message to strip the CR and LF.
If Bytes > 2 Then
    GetErrorString = Left$(ErrorString, Bytes - 2)
End If

End Function

Private Sub cmdContinuous_Click()
'Enables the user to select 1-time or continuous data transfers.

If cmdContinuous.Caption = "Continuous" Then
    'Change the command button to Cancel Continuous
    cmdContinuous.Caption = "Cancel Continuous"
    'Enable the timer to read and write to the device once/second.
    tmrContinuousDataCollect.Enabled = True
    Call ReadAndWriteToDevice
Else
    'Change the command button to Continuous
    cmdContinuous.Caption = "Continuous"
    'Disable the timer that reads and writes to the device once/second.
    tmrContinuousDataCollect.Enabled = False
End If

End Sub

Private Sub cmdOnce_Click()
Call ReadAndWriteToDevice
End Sub
Private Sub DisplayResultOfAPICall(FunctionName As String)

'Display the results of an API call.

Dim ErrorString As String

lstResults.AddItem ""
ErrorString = GetErrorString(Err.LastDllError)
lstResults.AddItem FunctionName
lstResults.AddItem "  Result = " & ErrorString

'Scroll to the bottom of the list box.
lstResults.ListIndex = lstResults.ListCount - 1

End Sub

Private Sub Form_Load()
frmMain.Show
tmrDelay.Enabled = False
Call Startup
End Sub

Private Sub Form_Unload(Cancel As Integer)
Call Shutdown
End Sub

Private Sub GetDeviceCapabilities()

'******************************************************************************
'HidD_GetPreparsedData
'Returns: a pointer to a buffer containing information about the device's capabilities.
'Requires: A handle returned by CreateFile.
'There's no need to access the buffer directly,
'but HidP_GetCaps and other API functions require a pointer to the buffer.
'******************************************************************************

Dim ppData(29) As Byte
Dim ppDataString As Variant

'Preparsed Data is a pointer to a routine-allocated buffer.
Result = HidD_GetPreparsedData _
    (HIDHandle, _
    PreparsedData)
Call DisplayResultOfAPICall("HidD_GetPreparsedData")

'Copy the data at PreparsedData into a byte array.

Result = RtlMoveMemory _
    (ppData(0), _
    PreparsedData, _
    30)
Call DisplayResultOfAPICall("RtlMoveMemory")

ppDataString = ppData()
'Convert the data to Unicode.
ppDataString = StrConv(ppDataString, vbUnicode)

'******************************************************************************
'HidP_GetCaps
'Find out the device's capabilities.
'For standard devices such as joysticks, you can find out the specific
'capabilities of the device.
'For a custom device, the software will probably know what the device is capable of,
'so this call only verifies the information.
'Requires: The pointer to a buffer containing the information.
'The pointer is returned by HidD_GetPreparsedData.
'Returns: a Capabilites structure containing the information.
'******************************************************************************
Result = HidP_GetCaps _
    (PreparsedData, _
    Capabilities)

Call DisplayResultOfAPICall("HidP_GetCaps")
lstResults.AddItem "  Last error: " & ErrorString
lstResults.AddItem "  Usage: " & Hex$(Capabilities.Usage)
lstResults.AddItem "  Usage Page: " & Hex$(Capabilities.UsagePage)
lstResults.AddItem "  Input Report Byte Length: " & Capabilities.InputReportByteLength
lstResults.AddItem "  Output Report Byte Length: " & Capabilities.OutputReportByteLength
lstResults.AddItem "  Feature Report Byte Length: " & Capabilities.FeatureReportByteLength
lstResults.AddItem "  Number of Link Collection Nodes: " & Capabilities.NumberLinkCollectionNodes
lstResults.AddItem "  Number of Input Button Caps: " & Capabilities.NumberInputButtonCaps
lstResults.AddItem "  Number of Input Value Caps: " & Capabilities.NumberInputValueCaps
lstResults.AddItem "  Number of Input Data Indices: " & Capabilities.NumberInputDataIndices
lstResults.AddItem "  Number of Output Button Caps: " & Capabilities.NumberOutputButtonCaps
lstResults.AddItem "  Number of Output Value Caps: " & Capabilities.NumberOutputValueCaps
lstResults.AddItem "  Number of Output Data Indices: " & Capabilities.NumberOutputDataIndices
lstResults.AddItem "  Number of Feature Button Caps: " & Capabilities.NumberFeatureButtonCaps
lstResults.AddItem "  Number of Feature Value Caps: " & Capabilities.NumberFeatureValueCaps
lstResults.AddItem "  Number of Feature Data Indices: " & Capabilities.NumberFeatureDataIndices

'******************************************************************************
'HidP_GetValueCaps
'Returns a buffer containing an array of HidP_ValueCaps structures.
'Each structure defines the capabilities of one value.
'This application doesn't use this data.
'******************************************************************************

'This is a guess. The byte array holds the structures.
Dim ValueCaps(1023) As Byte

Result = HidP_GetValueCaps _
    (HidP_Input, _
    ValueCaps(0), _
    Capabilities.NumberInputValueCaps, _
    PreparsedData)
   
Call DisplayResultOfAPICall("HidP_GetValueCaps")

'lstResults.AddItem "ValueCaps= " & GetDataString((VarPtr(ValueCaps(0))), 180)
'To use this data, copy the byte array into an array of structures.

'Free the buffer reserved by HidD_GetPreparsedData
Result = HidD_FreePreparsedData _
    (PreparsedData)
Call DisplayResultOfAPICall("HidD_FreePreparsedData")

End Sub

Private Sub InitializeDisplay()
Dim Count As Integer
Dim ByteValue As String
'Create a dropdown list box for each byte to send.
For Count = 0 To 255
    If Len(Hex$(Count)) < 2 Then
        ByteValue = "0" & Hex$(Count)
    Else
        ByteValue = Hex$(Count)
    End If
    frmMain.cboByte0.AddItem ByteValue, Count
Next Count
For Count = 0 To 255
    If Len(Hex$(Count)) < 2 Then
        ByteValue = "0" & Hex$(Count)
    Else
        ByteValue = Hex$(Count)
    End If
    frmMain.cboByte1.AddItem ByteValue, Count
Next Count
'Select a default item for each box
frmMain.cboByte0.ListIndex = 0
frmMain.cboByte1.ListIndex = 128

'Check the autoincrement box to increment the values each time a report is sent.
chkAutoincrement.Value = 1
End Sub

Private Sub PrepareForOverlappedTransfer()

'******************************************************************************
'CreateEvent
'Creates an event object for the overlapped structure used with ReadFile.
'Requires a security attributes structure or null,
'Manual Reset = True (ResetEvent resets the manual reset object to nonsignaled),
'Initial state = True (signaled),
'and event object name (optional)
'Returns a handle to the event object.
'******************************************************************************

If EventObject = 0 Then
    EventObject = CreateEvent _
        (0&, _
        True, _
        True, _
        "")
End If
    
Call DisplayResultOfAPICall("CreateEvent")
    
'Set the members of the overlapped structure.
HIDOverlapped.Offset = 0
HIDOverlapped.OffsetHigh = 0
HIDOverlapped.hEvent = EventObject
End Sub
Private Sub ReadAndWriteToDevice()
'Sends two bytes to the device and reads two bytes back.

'Report Header
lstResults.AddItem ""
lstResults.AddItem "***** HID Test Report *****"
lstResults.AddItem Format(Now, "general date")

'Some data to send
'(if not using the combo boxes):
'OutputReportData(0) = &H12
'OutputReportData(1) = &H34
'OutputReportData(2) = &HF0
'OutputReportData(3) = &HF1
'OutputReportData(4) = &HF2
'OutputReportData(5) = &HF3
'OutputReportData(6) = &HF4
'OutputReportData(7) = &HF5

'If the device hasn't been detected or it timed out on a previous attempt
'to access it, look for the device.
If MyDeviceDetected = False Then
    MyDeviceDetected = FindTheHid
End If

If MyDeviceDetected = True Then

    'Get the bytes to send from the combo boxes.
    'Increment the values if the autoincrement check box is selected.
    If chkAutoincrement.Value = 1 Then
        If cboByte0.ListIndex < 255 Then
            cboByte0.ListIndex = cboByte0.ListIndex + 1
        Else
            cboByte0.ListIndex = 0
        End If
        If cboByte1.ListIndex < 255 Then
            cboByte1.ListIndex = cboByte1.ListIndex + 1
        Else
            cboByte1.ListIndex = 0
        End If
    End If
    
    OutputReportData(0) = cboByte0.ListIndex
    OutputReportData(1) = cboByte1.ListIndex
       
    'Write a report to the device
    Call WriteReport
    'The example firmware adds 1 to each received byte and sends the bytes back
    'to the host.
    'Read a report from the device.
    Call ReadReport
Else
End If

'Scroll to the bottom of the list box.
lstResults.ListIndex = lstResults.ListCount - 1

End Sub

Private Sub ReadReport()
'Read data from the device.

Dim Count
Dim NumberOfBytesRead As Long
'Allocate a buffer for the report.
'Byte 0 is the report ID.
Dim ReadBuffer() As Byte
Dim UBoundReadBuffer As Integer

'******************************************************************************
'ReadFile
'Returns: the report in ReadBuffer.
'Requires: a device handle returned by CreateFile
'(for overlapped I/O, CreateFile must be called with FILE_FLAG_OVERLAPPED),
'the Input report length in bytes returned by HidP_GetCaps,
'and an overlapped structure whose hEvent member is set to an event object.
'******************************************************************************

Dim ByteValue As String
'The ReadBuffer array begins at 0, so subtract 1 from the number of bytes.
ReDim ReadBuffer(Capabilities.InputReportByteLength - 1)
'Scroll to the bottom of the list box.
lstResults.ListIndex = lstResults.ListCount - 1

'Do an overlapped ReadFile.
'The function returns immediately, even if the data hasn't been received yet.
Result = ReadFile _
    (ReadHandle, _
    ReadBuffer(0), _
    CLng(Capabilities.InputReportByteLength), _
    NumberOfBytesRead, _
    HIDOverlapped)
Call DisplayResultOfAPICall("ReadFile")

lstResults.AddItem "waiting for ReadFile"
'Scroll to the bottom of the list box.
lstResults.ListIndex = lstResults.ListCount - 1
bAlertable = True

'******************************************************************************
'WaitForSingleObject
'Used with overlapped ReadFile.
'Returns when ReadFile has received the requested amount of data or on timeout.
'Requires an event object created with CreateEvent
'and a timeout value in milliseconds.
'******************************************************************************
Result = WaitForSingleObject _
    (EventObject, _
    6000)
Call DisplayResultOfAPICall("WaitForSingleObject")

'Find out if ReadFile completed or timeout.
Select Case Result
    Case WAIT_OBJECT_0
        'ReadFile has completed
        lstResults.AddItem "ReadFile completed successfully."
    Case WAIT_TIMEOUT
        'Timeout
        lstResults.AddItem "Readfile timeout"
        'Cancel the operation
        
        '*************************************************************
        'CancelIo
        'Cancels the ReadFile
        'Requires the device handle.
        'Returns non-zero on success.
        '*************************************************************
        Result = CancelIo _
            (ReadHandle)
        lstResults.AddItem "************ReadFile timeout*************"
        lstResults.AddItem "CancelIO"
        Call DisplayResultOfAPICall("CancelIo")
        'The timeout may have been because the device was removed,
        'so close any open handles and
        'set MyDeviceDetected=False to cause the application to
        'look for the device on the next attempt.
        CloseHandle (HIDHandle)
        Call DisplayResultOfAPICall("CloseHandle (HIDHandle)")
        CloseHandle (ReadHandle)
        Call DisplayResultOfAPICall("CloseHandle (ReadHandle)")
        MyDeviceDetected = False
    Case Else
        lstResults.AddItem "Readfile undefined error"
        MyDeviceDetected = False
End Select
    
lstResults.AddItem " Report ID: " & ReadBuffer(0)
lstResults.AddItem " Report Data:"

txtBytesReceived.Text = ""
For Count = 1 To UBound(ReadBuffer)
    'Add a leading 0 to values 0 - Fh.
    If Len(Hex$(ReadBuffer(Count))) < 2 Then
        ByteValue = "0" & Hex$(ReadBuffer(Count))
    Else
        ByteValue = Hex$(ReadBuffer(Count))
    End If
    lstResults.AddItem " " & ByteValue
    'Display the received bytes in the text box.
    txtBytesReceived.SelStart = Len(txtBytesReceived.Text)
    txtBytesReceived.SelText = ByteValue & vbCrLf
Next Count

'******************************************************************************
'ResetEvent
'Sets the event object in the overlapped structure to non-signaled.
'Requires a handle to the event object.
'Returns non-zero on success.
'******************************************************************************

Call ResetEvent(EventObject)
Call DisplayResultOfAPICall("ResetEvent")
End Sub

Private Sub Shutdown()
'Actions that must execute when the program ends.

'Close the open handles to the device.
Result = CloseHandle _
    (HIDHandle)
Call DisplayResultOfAPICall("CloseHandle (HIDHandle)")

Result = CloseHandle _
    (ReadHandle)
Call DisplayResultOfAPICall("CloseHandle (ReadHandle)")

End Sub

Private Sub Startup()
Call InitializeDisplay
tmrContinuousDataCollect.Enabled = False
tmrContinuousDataCollect.Interval = 1000
End Sub

Private Sub tmrContinuousDataCollect_Timer()
Call ReadAndWriteToDevice

End Sub

Private Sub tmrDelay_Timer()
Timeout = True
tmrDelay.Enabled = False
End Sub

Private Sub WriteReport()
'Send data to the device.

Dim Count As Integer
Dim NumberOfBytesRead As Long
Dim NumberOfBytesToSend As Long
Dim NumberOfBytesWritten As Long
Dim ReadBuffer() As Byte
Dim SendBuffer() As Byte

'The SendBuffer array begins at 0, so subtract 1 from the number of bytes.
ReDim SendBuffer(Capabilities.OutputReportByteLength - 1)

'******************************************************************************
'WriteFile
'Sends a report to the device.
'Returns: success or failure.
'Requires: the handle returned by CreateFile and
'The output report byte length returned by HidP_GetCaps
'******************************************************************************

'The first byte is the Report ID
SendBuffer(0) = 0

'The next bytes are data
For Count = 1 To Capabilities.OutputReportByteLength - 1
    SendBuffer(Count) = OutputReportData(Count - 1)
Next Count

NumberOfBytesWritten = 0

Result = WriteFile _
    (HIDHandle, _
    SendBuffer(0), _
    CLng(Capabilities.OutputReportByteLength), _
    NumberOfBytesWritten, _
    0)
Call DisplayResultOfAPICall("WriteFile")

lstResults.AddItem " OutputReportByteLength = " & Capabilities.OutputReportByteLength
lstResults.AddItem " NumberOfBytesWritten = " & NumberOfBytesWritten
lstResults.AddItem " Report ID: " & SendBuffer(0)
lstResults.AddItem " Report Data:"

For Count = 1 To UBound(SendBuffer)
    lstResults.AddItem " " & Hex$(SendBuffer(Count))
Next Count

End Sub


