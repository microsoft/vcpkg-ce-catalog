@echo off

echo Setting environment...

set $_id=%DATE:~4%-%TIME:~,-3%
set $_id=%$_id:/=-%
set $_id=%$_id::=-%
echo - saving original PATH in PATH.SAVED.%$_id%
set PATH.SAVED.%$_id%=%PATH%
echo - adding VCPKG_ROOT to path
set PATH=%PATH%;%VCPKG_ROOT%
set $_id=

:msbuild_environment
set EnableExperimentalVcpkgIntegration=true
rem Find msbuild.exe
set $_MSBuildExe=
for /f "usebackq tokens=1*" %%m in (`where /r "%HOMEDRIVE%\Program Files\Microsoft Visual Studio\2022" msbuild.exe ^| findstr /i amd64`) do (
    set $_MSBuildExe=%%m %%n
)
if "%$_MSBuildExe%" == "" (
    echo WARNING: Unable to locate msbuild.exe, please set $_MSBuildExe manually to the full path to msbuild.exe
)
rem Find VS Installer
set $_MSBuildExe=
for /f "usebackq tokens=1*" %%m in (`where /r "%HOMEDRIVE%\Program Files\Microsoft Visual Studio\2022" msbuild.exe ^| findstr /i amd64`) do (
    set $_MSBuildExe=%%m %%n
)
if "%$_MSBuildExe%" == "" (
    echo WARNING: Unable to locate msbuild.exe, please set $_MSBuildExe manually to the full path to msbuild.exe
)

:show_variables
echo.
echo Key variables:
set $_varList=VCPKG Enable INC LIB VC_
for %%e in (%$_varList%) do set %%e

echo.
echo Where is vcpkg?:
where vcpkg
echo.
echo Done.


