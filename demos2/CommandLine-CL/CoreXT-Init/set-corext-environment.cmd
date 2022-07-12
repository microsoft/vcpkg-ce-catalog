@echo off

:init
set _targetArch=

:getargs
set _targetArg=%1
for %%t in (x86 x64) do (
    if /I "%_targetArg%" == "--target:%%t" set _targetArch=%%t& goto :start
)
echo ERROR: invalid target '%_targetArg%' specified; must be x86 or x64
exit /b 1

:start
if "%SAVED_ENVVAR_COUNT%" == "" (
    set SAVED_ENVVAR_COUNT=0
)
set /A SAVED_ENVVAR_COUNT+=1
set PATH.SAVED%SAVED_ENVVAR_COUNT%=%PATH%
set LIB.SAVED%SAVED_ENVVAR_COUNT%=%LIB%
set LIBPATH.SAVED%SAVED_ENVVAR_COUNT%=%LIBPATH%
set INCLUDE.SAVED%SAVED_ENVVAR_COUNT%=%INCLUDE%

set _toolsRoot=%CD%\src\tools\Vctools\Dev16\lib\native
set _winsdkRoot1=%CD%\src\ExternalApis\Windows\10.0\sdk
set _winsdkRoot2inc=%CD%\src\ExternalApis\WindowsSDKInc\c\Include\10.0.22000.0
set _winsdkRoot2lib=%CD%\src\ExternalApis\WindowsSDKLib

goto :set_target%_targetArch%
goto :done

:set_targetx64
set PATH=%_toolsRoot%\bin\HostX64\x64;%PATH%
set INCLUDE=%_toolsRoot%\include;%_winsdkRoot2inc%\ucrt;%_winsdkRoot2inc%\um
set LIB=%_toolsRoot%\lib\x64;%_winsdkRoot2Lib%\x64\c\ucrt\x64;%_winsdkRoot2Lib%\x64\c\um\x64
set LIBPATH=%_toolsRoot%\lib\x64;%_winsdkRoot2Lib%\x64\c\ucrt\x64;%_winsdkRoot2Lib%\x64\c\um\x64
goto :done

:set_targetx86
set PATH=%_toolsRoot%\bin\HostX64\x86;%PATH%
set INCLUDE=%_toolsRoot%\include;%_winsdkRoot2inc%\ucrt;%_winsdkRoot2inc%\um
set LIB=%_toolsRoot%\lib\x86;%_winsdkRoot2Lib%\x86\c\ucrt\x86;%_winsdkRoot2Lib%\x86\c\um\x86
set LIBPATH=%_toolsRoot%\lib\x86;%_winsdkRoot2Lib%\x86\c\ucrt\x86;%_winsdkRoot2Lib%\x86\c\um\x86

:done
exit /b 0
