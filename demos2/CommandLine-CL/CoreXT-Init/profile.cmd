@echo off
SETLOCAL
SET PS=%windir%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy bypass -Command

FOR %%I IN (%~dp0\.corext\..) DO @SET ROOT=%%~fI
SET CoreXTRepoRoot=%ROOT%
SET CoreXTConfig=%ROOT%\.corext
SET COMPLUS_InstallRoot=
SET COMPLUS_Version=

%PS% %CoreXTConfig%\Profile.ps1 %*
ENDLOCAL