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

rem set EnableExperimentalVcpkgIntegration=true

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


