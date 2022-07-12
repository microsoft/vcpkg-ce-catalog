@if "%_echo%"=="" echo off

set PS=%windir%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command
set InitCommand=%~dp0\Init.ps1 %*

:: PowerShell doesn't handle forward slashes for arguments
set InitCommand=%InitCommand:/=-%

if not exist %~dp0\cloudbuild.sem goto :RunInit

if "%COMPLUS_Version%" == "" if "%COMPLUS_InstallRoot%" == "" (set clean=true)

::Check if we need to generate a guid as InitScope for official build machine
echo %InitCommand% | findstr /i /c:"officialbuild">nul && (
       for /f %%a in ('%PS% "$([guid]::NewGuid().ToString())"') do ( set NewGuid=%%a )                   
)

if "%InitScope%" == "" (   
    if not "%NewGuid%" == "" (
	::remove trailing space
        set "InitScope=%NewGuid: =%"        
    ) else (
        set InitScope=%random%
    )
)

if "%RazzleArgsInfoPath%" == "" (   
    set RazzleArgsInfoPath=%temp%\razzleArgs-%InitScope%.info       
)
    
:: Check if we should run razzle
echo %InitCommand% | findstr /i /c:"-?" /c:"-skiprazzle" /c:"-CreateShortcut" /c:"-NewShortcut" /c:"-DownloadMetadata">nul && (
    set SkipRazzle=true
)

:RunInit
setlocal ENABLEDELAYEDEXPANSION
set COMPLUS_InstallRoot=
set COMPLUS_Version=

if "%QBUILD_DISTRIBUTED%" == "1" (
    call %~dp0\profile.cmd -set CoreXT OfficialBuild
    set InitCommand=%InitCommand% -CloudBuild -Verbose
    )

if not "%RazzleArgsInfoPath%" == "" if not "%SkipRazzle%" == "true" (set InitCommand=%InitCommand% -RazzleArgsInfoPath '%RazzleArgsInfoPath%')

::InitRazzleArgs is set when init.cmd in BuildEnv package reads from RazzleArgsInfoPath
if not "%InitRazzleArgs%" == "" if not "%SkipRazzle%" == "true" (set InitCommand=%InitCommand% -PrevRazzleArgs '%InitRazzleArgs%')

set InitCommand=%PS% "%InitCommand%"

:: Clean skiprazzle switch
set InitCommand=%InitCommand:-skiprazzle=%

call %InitCommand%

if errorlevel 1 (
  if "%QBUILD_DISTRIBUTED%" == "1" (
    for /f %%f in ('dir %localappdata%\devconsole\logs\*vs*corext*.log /O:D /s /b') do set file=%%f
    echo %file% 1>&2
    type %file% 1>&2  
    exit /b %errorlevel%
  )
)
endlocal

if exist %~dp0\out\gen\InitOutputEnvironment_%InitScope%.cmd (  
  call %~dp0\out\gen\InitOutputEnvironment_%InitScope%.cmd
  del %~dp0\out\gen\InitOutputEnvironment_%InitScope%.cmd
)

setlocal
if exist %~dp0\cloudbuild.sem if not "%clean%" == "true" (
    set COMPLUS_VERSION=
    set COMPLUS_InstallRoot=
    call %PS% Write-Host -foreground Yellow "Transition from razzle to unified build environment detected. Please open a new cmd window and rerun init.`nReference: https://aka.ms/vseng-unifiedbuildenv"       
    goto :EOF 
)
endlocal

set clean=

::Skip CloudBuild initialization (including running razzle)
if not exist %~dp0\cloudbuild.sem goto :EOF

::Fix for VSTS env variable with new line
set BUILD_SOURCEVERSIONMESSAGE=%BUILD_SOURCEVERSIONMESSAGE%

:: Turn on CoreXT Auto Rewind
set CoreXT_AutoRewind=true

::Turn off CB.Client syncing if using nosync switch
echo %InitCommand% | findstr /i /c:"-NoSync">nul && (
    set QCLIENT_DISABLED=1 
)

:: Do CoreXT package init
if not exist %~dp0\out\gen\Init.cmd goto :SkipPkgInit
if "%SkipRazzle%" == "true" goto :SkipPkgInit
set Corext_ExitOnPackageInitError=1
call %~dp0\out\gen\Init.cmd -recurse
IF %ERRORLEVEL% NEQ 0 EXIT /b %ERRORLEVEL%
:SkipPkgInit


set CSHARPCORETARGETSPATH=%VSSDKTOOLSPATH%\Microsoft.CSharp.Core.targets
:: Turn off pre-process hooks and dbb integration with the RazzleBuildTools build.exe
set BUILD_PRE_PROCESS=
set BUILD_POST_PROCESS=
set BUILD_USE_DBB=0

:: Clear BUILD_ALT_DIR since each flavor-specific build script will set it during invocation
set BUILD_ALT_DIR=

:: setting comspec to 32-bit shell to ensure later spawned shell are 32 bits
set COMSPEC=%WINDIR%\SYSWOW64\CMD.EXE
set SkipRazzle=
set NewGuid=
set QCLIENT_DISABLED=

:: TODO: Push all this environment stuff into init.
:: INETROOT is the CoreXT enlistment root. _NTTREE is the CoreXT output root. By default _NTTREE is the same path as INETROOT.
:: https://microsoft.sharepoint.com/teams/corext/LivingDocs/BuildRoots.aspx 
if "%QBUILD_DISTRIBUTED%" == "1" (
    set MSBuildToolsPath=%MSBuildToolsPath_150%
    set _NTBINROOT=
    set _BuildBins=
    set _NTPOSTBLD=
    set _NTx86TREE=
    set _NTTREE=%INETROOT%
)
