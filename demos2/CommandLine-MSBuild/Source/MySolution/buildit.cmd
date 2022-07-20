@echo off
@setlocal enabledelayedexpansion

:start
set _targetArch=%1
if "%_targetArch%" == "" (
    echo INFO: no Platform specified - using x64
    set _targetArch=x64
) 
if /I "%_targetArch%" NEQ "x64" if /I "%_targetArch%" NEQ "x86" (
    echo invalid Platform architecture '%_targetArch%' - building x64 instead
    set _targetArch=x64
)

call %~dp0test-project.cmd build %_targetArch%
goto :done

if "%$_MSBuildExe%" == "" echo ERROR: unable to build - variable $_MSBuildExe not set& exit /b 1
set $_MSBuildArgs=/t:rebuild /p:Configuration=Release /p:Platform=%_targetArch% /p:EnableExperimentalVcpkgIntegration=true
echo Running command msbuild.exe %$_MSBuildArgs%
"%$_MSBuildExe%" %$_MSBuildArgs%
goto :done

:done
popd
