Set fso = CreateObject("Scripting.FileSystemObject")
sm = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%ProgramData%") & "\Microsoft\Windows\Start Menu\Programs\DrSuporti Remote Cliente\DrSuporti Remote Cliente.lnk"
desk = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%Public%") & "\Desktop\DrSuporti Remote Cliente.lnk"
If fso.FileExists(sm) Then fso.DeleteFile(sm)
If fso.FileExists(desk) Then fso.DeleteFile(desk)
