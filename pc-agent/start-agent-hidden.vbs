' Command Center agent - hidden launcher.
'
' Starts the agent with no console window and appends its output to agent.log,
' so a failure at login is diagnosable instead of invisible.
'
' If something is already listening on the port (for example an agent you
' started by hand), this exits quietly rather than starting a second copy that
' could only fail with EADDRINUSE.
'
' Change PORT below if you ever change "port" in agent.config.json.

Const PORT = 8765

Dim shell, fso, folder, log, probe, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

folder = fso.GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = folder
log = folder & "\agent.log"

probe = "powershell -NoProfile -Command ""$c=New-Object Net.Sockets.TcpClient;" & _
        "try{$c.Connect('127.0.0.1'," & PORT & ");exit 0}" & _
        "catch{exit 1}finally{$c.Dispose()}"""

If shell.Run(probe, 0, True) = 0 Then
    ' An agent is already serving this port.
    WScript.Quit 0
End If

command = "cmd /c echo [%DATE% %TIME%] starting agent on port " & PORT & _
          " >> """ & log & """ & node server.js >> """ & log & """ 2>&1"
shell.Run command, 0, False
