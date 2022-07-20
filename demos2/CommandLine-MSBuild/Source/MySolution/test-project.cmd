@echo off
@setlocal enabledelayedexpansion

set _action=%1
set _targetArch=%2

for %%a in (clean build rebuild run) do (
    if "%_action%" == "%%a" goto :check_targetArch
)
echo %~n0: invalid action '%_action%'& exit /b 1

:check_targetArch
if "%_targetArch%" == "" (
    echo INFO: no Platform specified - using x64
    set _targetArch=x64
) 
if /I "%_targetArch%" NEQ "x64" if /I "%_targetArch%" NEQ "x86" (
    echo invalid Platform architecture '%_targetArch%' - running x64 instead
    set _targetArch=x64
)
set _archOutputDir=!_targetArch!
if /I "%_targetArch%" == "x86" set _archOutputDir=Win32

:start

set _msbuildConfig=Release
set _msbuildTarget=%_action%
goto :%_action%

:rebuild
:build
:clean
if "%$_MSBuildExe%" == "" echo ERROR: unable to build - variable $_MSBuildExe not set& exit /b 1
set $_MSBuildArgs=/t:%_msbuildTarget% /p:Configuration=%_msbuildConfig% /p:Platform=%_targetArch% /p:EnableExperimentalVcpkgIntegration=true
echo Running %_msbuildTarget% command 'msbuild.exe %$_MSBuildArgs%'
"%$_MSBuildExe%" %$_MSBuildArgs%
goto :done

:run
set $_exeFile=.\Outputs\%_archOutputDir%\%_msbuildConfig%\ConsoleApplication.exe
if not exist %$_exeFile% (
    echo - error: unable to run - '%$_exeFile%' does not exist
    exit /b 1
)
echo Running '%$_exeFile%'...
%$_exeFile%
goto :done

:reset
set $_outputDir=.\Outputs\%_archOutputDir%
if not exist %$_outputDir% (
    echo INFO: no output directory to delete
    goto :done
)
set $cmd=rd /s /q %$_outputDir%
echo Deleting output directory [%$cmd%]...
%$cmd%

rem Note: link.exe won't be on the path unless we activate 
rem 
rem echo Verify machine type...
rem link.exe -dump -headers %$_exeFile% | findstr /i machine

:done
exit /b 0
