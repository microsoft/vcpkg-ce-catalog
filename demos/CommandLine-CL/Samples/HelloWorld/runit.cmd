@echo off
@setlocal enabledelayedexpansion

:start
set $_exeFile=.\hello.exe
if not exist %$_exeFile% (
    echo - error: unable to run - '%$_exeFile%' does not exist
    exit /b 1
)

echo Running '%$_exeFile%'...
%$_exeFile%
echo Verify machine type...
link -dump -headers %$_exeFile% | findstr /i machine

:done
exit /b 0
