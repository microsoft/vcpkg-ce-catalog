@echo off

echo Setting demo environment (variables and shortcuts)...
set $_vcpkgDemoName=%1
if "%$_vcpkgDemoName%" NEQ "" goto :set_variables
set $_vcpkgDemoName=CommandLine-MSBuild
echo INFO: no demo name specified - using %$_vcpkgDemoName%

:set_variables
set $_vcpkgDemoRoot=%~dp0
set $_vcpkgDemoRoot=%$_vcpkgDemoRoot:~,-1%
if not exist %$_vcpkgDemoRoot%\%$_vcpkgDemoName% (
    echo ERROR: demo directory '%$_vcpkgDemoName%' not found
    exit /b 1
)
set $_vcpkgDemoDir=%$_vcpkgDemoRoot%\%$_vcpkgDemoName%
set $_vcpkgCatalogsDir=%$_vcpkgDemoRoot%\catalogs
set $_vcpkgCatalogRoot=%$_vcpkgCatalogsDir%\vcpkg-ce-catalog.demo1
set $_vcpkgInstallDir=%USERPROFILE%\.vcpkg
set $_vcpkgTempDir=%TEMP%\vcpkg
set $_corextNugetCache=c:\NugetCache
set $_nugetPackageCache=%USERPROFILE%\.nuget\packages

if "%~dp0" == "%CD%\" pushd %$_vcpkgDemoDir%

:set_shortcuts
set _msg=demo commands must be run in the demo directory
doskey reset_machine=%$_vcpkgDemoRoot%\reset_machine.cmd $*
doskey reset=if exist demo.cmd ( demo.cmd reset ) else (echo %_msg%)
doskey bootstrap=if exist demo.cmd ( demo.cmd bootstrap $* ) else (echo %_msg%)
doskey acquire=if exist demo.cmd ( demo.cmd acquire $* ) else (echo %_msg%)
doskey activate=if exist demo.cmd ( demo.cmd activate $* ) else (echo %_msg%)
doskey clean=if exist demo.cmd ( demo.cmd clean $* ) else (echo %_msg%)
doskey build=if exist demo.cmd ( demo.cmd build $* ) else (echo %_msg%)
set _msg=

:show_usage
if "%SET_DEMO_ENVIRONMENT%" == "-quiet" goto :end_show_usage
echo Demo commands/shortcuts:
echo ^  reset_machine       Uninstall/remove per-user acquisition components
echo ^  reset               Uninstall/remove both per-user and per-demo acquisition components
echo ^  bootstrap           Install acquisition prerequisites (no build toolset components)
echo ^  acquire             Download build toolset components
echo ^  activate [{arch}]   Activate build environment for the target architecture
echo ^  clean [{arch}]      Clean build output
echo ^  build [{$arch}]     Build and run demo project
echo.
:end_show_usage

:done

