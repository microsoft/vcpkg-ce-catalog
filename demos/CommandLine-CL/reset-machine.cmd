@echo off
@setlocal enabledelayedexpansion

call set-demo-environment.cmd

if exist %$_vcpkgInstallDir% (
    echo Deleting vcpkg installation '%$_vcpkgInstallDir%'...
    rd /s /q %$_vcpkgInstallDir%
)
if exist %$_vcpkgTempDir% (
    echo Deleting vcpkg temp directory '%$_vcpkgTempDir%'...
    rd /s /q %$_vcpkgTempDir%
)
if exist %$_vcpkgCatalogsDir% (
    echo Deleting vcpkg catalogs '%$_vcpkgCatalogsDir%'...
    rd /s /q %$_vcpkgCatalogsDir%
)
set _msgEmitted=false
for %%i in (obj exe pdb ilk) do (
    if exist %$_vcpkgDemoDir%\Samples\HelloWorld\*.%%i (
        if "%_msgEmitted%" == "false" (
            echo Deleting build output in '%$_vcpkgDemoDir%\Samples\HelloWorld'...
            set _msgEmitted=true
        )
        del %$_vcpkgDemoDir%\Samples\HelloWorld\*.%%i
    )
)
if exist %$_corextNugetCache% (
    echo Deleting CoreXT NuGet cache '%$_corextNugetCache%'...
    rd /s /q %$_corextNugetCache%
)
if exist %$_nugetPackageCache% (
    echo Deleting NuGet package cache '%$_nugetPackageCache%'...
    rd /s /q %$_nugetPackageCache%
)
for %%s in (out src) do (
    if exist %$_vcpkgDemoDir%\CoreXT-Init\%%s (
        echo Deleting CoreXT-generated directory '%%s'...
        rd /s /q %$_vcpkgDemoDir%\CoreXT-Init\%%s
    )
)

set _startAppWiz=false
for %%p in ("Program Files" "Program Files (x86)") do (
    if exist "%%~p\Microsoft Visual Studio" (
        set _startAppWiz=true
    )
)
for %%p in (System32 SysWow64) do (
    if exist "%WINDIR%\%%p\vcruntime140.dll" (
        set _startAppWiz=true
    )
)
if "%_startAppWiz%" == "true" (
    echo Opening Programs and Features; please uninstall all Visual Studio and Visual C++ 2015 Runtime items
    start appwiz.cpl
)

set _msgEmitted=false
set _appdataRoot=%USERPROFILE%\AppData\Local
for %%s in (vcpkg npm-cache) do (
    if exist %_appdataRoot%\%%s (
        if "!_msgEmitted!" == "false" (
            echo Deleting application data...
            set _msgEmitted=true
        )
        echo Deleting %%s appdata...
        rd /s /q %_appdataRoot%\%%s
    )
)
for %%s in ("VisualStudio" "VisualStudio Services" "VSCommon" "VSApplicationInsights") do (
    set _appdataDir="%_appdataRoot%\Microsoft\%%~s"
    if exist !%_appdataDir! (
        if "!_msgEmitted!" == "false" (
            echo Deleting application data...
            set _msgEmitted=true
        )
        echo Deleting %%~s appdata...
        rd /s /q !%_appdataDir!
    )
)

:done
