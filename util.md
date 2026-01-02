para compilar (Windows / MSI, tudo em um comando):

1) Coloque `sciter.dll` na raiz do repo (`C:\github\rustdesk\sciter.dll`) ou passe o caminho via parâmetro.
2) Rode:
`powershell -ExecutionPolicy Bypass -File .\packaging\windows\build_msi.ps1` (não use dot-source `. script.ps1`)

Se aparecer `candle.exe (WiX) not found in PATH`, instale o WiX Toolset v3 (candle/light) ou passe o bin:
`powershell -ExecutionPolicy Bypass -File .\packaging\windows\build_msi.ps1 -WixBinPath "C:\Program Files (x86)\WiX Toolset v3.11\bin"`
