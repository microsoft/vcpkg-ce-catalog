@echo off
@setlocal enabledelayedexpansion

set _targetArch=%1
if "%_targetArch%" == "" (
    echo INFO: no Platform specified - using x64
    set _targetArch=x64
) 
if /I "%_targetArch%" NEQ "x64" if /I "%_targetArch%" NEQ "x86" (
    echo invalid Platform architecture '%_targetArch%' - running x64 instead
    set _targetArch=x64
)

:start
set $_exeFile=.\Outputs\%_targetArch%\Debug\ConsoleApplication.exe
if not exist %$_exeFile% (
    echo - error: unable to run - '%$_exeFile%' does not exist
    exit /b 1
)

echo Running '%$_exeFile%'...
%$_exeFile%

rem Note: link.exe won't be on the path unless we activate 
rem 
rem echo Verify machine type...
rem link.exe -dump -headers %$_exeFile% | findstr /i machine

:done
exit /b 0
