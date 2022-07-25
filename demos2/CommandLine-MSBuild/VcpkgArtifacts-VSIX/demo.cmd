@echo off

:init
if "%$_DEMO_ENVIRONMENT_INITIALIZED%" NEQ "" goto :skip_demo_env_init
set $_DemoName=CommandLine-MSBuild
set $_DemoSourceDir=Source\MySolution
set SET_DEMO_ENVIRONMENT=-quiet
call %$_vcpkgDemoRoot%\set-demo-environment.cmd %$_DemoName%
set SET_DEMO_ENVIRONMENT=
set $_vcpkgDemoSourceDir=%$_vcpkgDemoRoot%\%$_vcpkgDemoName%\%$_DemoSourceDir%
set $_envvarList=VCPKG Enable INC LIB VC_
set $_DEMO_ENVIRONMENT_INITIALIZED=1
doskey reset_demo_env=set $_DEMO_ENVIRONMENT_INITIALIZED=
:skip_demo_env_init
set $_actionOptions=reset bootstrap acquire activate clean build rebuild show_config install_vcrt install_vs
set $_validActivateTargets=x64 x86
set $_activateShowConfig=false
set $_action=
set $_actionArg=
set $_exitCode=
set $_cmdVcpkg=%~dp0vcpkg-init.cmd

:process_args
set $_action=%1
set $_actionArg=%2
set $_buildArgs=%3
setlocal enabledelayedexpansion
set _fIsValidAction=false
for %%o in (%$_actionOptions%) do (
    if /I "%$_action%" == "%%o" set _fIsValidAction=true
)
if "!_fIsValidAction!" == "false" (
    echo ERROR: invalid action '%_action%' specified
    exit /b 1
)
endlocal

:start
call :%$_action% %$_actionArg%
goto :done

:reset
pushd .
echo [%TIME%] Start Reset...
set $_exitCode=0
set $cmd=%$_vcpkgDemoRoot%\reset-machine.cmd %$_vcpkgDemoName%
call :run_command - Running reset script...
set $_exitCode=%ERRORLEVEL%
echo [%TIME%] Finish Reset.
popd .
exit /b %$_exitCode%

:bootstrap
pushd .
echo [%TIME%] Start Bootstrap...
set $_exitCode=0

call :echo Installing Git...
call where.exe git.exe >nul 2>&1
if errorlevel 1 (
    set $cmd=start https://gitforwindows.org/
    call :run_command - Git not installed: please install from https://gitforwindows.org/
) else (
    echo - Git is already installed
)

:install_vcpkg
call :echo Installing vcpkg...
if exist "%$_vcpkgInstallDir%" if exist .\vcpkg-init.cmd (
    echo - Vcpkg is already installed
    goto :end_install_vcpkg
)
set $cmd=curl -LO https://aka.ms/vcpkg-init.cmd
call :run_command - Downloading vcpkg...
if exist .\vcpkg-init.cmd (
    set $cmd=.\vcpkg-init.cmd
    call :run_command - Running vcpkg-init in %CD%...
)
:end_install_vcpkg

:install_vcpkg_ce_catalog
call :echo Installing vcpkg-ce-catalog (private)...
if not exist %$_vcpkgCatalogRoot% (
    set $cmd=git clone https://github.com/microsoft/vcpkg-ce-catalog.git %$_vcpkgCatalogRoot%
    call :run_command - Cloning...
    pushd %$_vcpkgCatalogRoot%
    echo - Updating to current branch...
    set $cmd=git checkout msvc-experiments
    call :run_command - - checkout...
    set $cmd=git pull
    call :run_command - - pull...
    popd
) else (
    echo - Updating to current branch...
    pushd %$_vcpkgCatalogRoot%
    set $cmd=git checkout -f
    call :run_command - - 
    set $cmd=git pull
    call :run_command - - 
    set $cmd=git checkout msvc-experiments
    call :run_command - - 
    set $cmd=git pull
    call :run_command - - 
    popd
)

:update_catalog
rem set $cmd=%$_cmdVcpkg% z-ce regenerate %$_vcpkgCatalogRoot%
rem call :run_command Updating catalog index...

:install_empty_manifest
echo Activating empty manifest to bootstrap core dependencies...
set $cmd=copy vcpkg-configuration.json-bootstrap vcpkg-configuration.json
call :run_command - copy bootstrap manifest...
set $cmd=%$_cmdVcpkg% activate
call :run_command - activate 

:set_environment
call :echo Setting bootstrapped demo environment...
call setenv.cmd

:end_bootstrap
echo [%TIME%] Finish Bootstrap.
popd
exit /b %$_exitCode%

:acquire
pushd .
echo [%TIME%] Start Acquisition...
set $_exitCode=0
echo No action taken, acquisition will be done as part of the activation step.
:end_acquire
echo [%TIME%] Finish Acquisition.
popd
exit /b %$_exitCode%

:activate
set $_vcpkgActivateTarget=%1
if "%$_vcpkgActivateTarget%" == "" (
    set $_vcpkgActivateTarget=x86
    goto :start_activation
)
for %%t in (%$_validActivateTargets%) do (
    if /I "%%t" == "%$_vcpkgActivateTarget%" goto :start_activation
)
echo ERROR: cannot activate invalid target '%$_vcpkgActivateTarget%'
exit /b 400
:start_activation
pushd .
echo [%TIME%] Start Activation (--target:%$_vcpkgActivateTarget%)...
set $_exitCode=0
set $cmd=copy vcpkg-configuration.json-demo %$_vcpkgDemoSourceDir%\vcpkg-configuration.json
call :run_command Update source to use demo manifest...
setlocal enabledelayedexpansion
if "%$_activateShowConfig%" == "true" (
    set /P _responseT=- show vcpkg-configuration.json? [y/n] 
    if "!_responseT:~0,1!" == "y" (
        rem start notepad %$_vcpkgDemoDir%\Source\MySolution\vcpkg-configuration.json
        rem pause
        type %$_vcpkgDemoSourceDir%\vcpkg-configuration.json
    )
)
endlocal
call :show_environment activated
echo No further action taken, activation is integrated with MSBuild and will be done as part of the build step.
:end_activate
echo [%TIME%] Finish Activation.
popd
exit /b %$_exitCode%

:clean
echo [%TIME%] Start Clean...
call :msbuild_common clean %1 
:end_clean
echo [%TIME%] Finish Clean.
exit /b %$_exitCode%

:build
echo [%TIME%] Start Build and Run...
call :msbuild_common build %1 
:end_build
echo [%TIME%] Finish Build.
exit /b %$_exitCode%

:rebuild
echo [%TIME%] Start Rebuild and Run...
call :msbuild_common rebuild %1 
echo [%TIME%] Finish Rebuild.
exit /b %$_exitCode%

:msbuild_common
set $_exitCode=0
setlocal
set _msbuildTarget=%1
set _msbuildPlatformArch=%2
pushd %$_vcpkgDemoDir%\Source\MySolution
if "%_msbuildPlatformArch%" == "" set _msbuildPlatformArch=%$_vcpkgActivateTarget%
call test-project.cmd %_msbuildTarget% %_msbuildPlatformArch%
if /I "%_msbuildTarget%" NEQ "clean" call test-project.cmd run %_msbuildPlatformArch%
popd
endlocal && exit /b %$_exitCode%

:echo
title %*
echo [%TIME%] %*
exit /b 0

:show_config
echo [%TIME%] Showing demo config...
set $_exitCode=0
set _demoConfig=%~dp0\vcpkg-configuration.json-demo
if exist %_demoConfig% (
    type %~dp0\vcpkg-configuration.json-demo
) else (
    call :echo - unable to locate demo config file '%_demoConfig%'
    set $_exitCode=1
)
set _demoConfig=
:end_show_config
echo [%TIME%] Finish Showing demo config.
exit /b %$_exitCode%

:install_vs
call :echo Installing VS...
rem Use internal dogfood build
set $cmd=start https://aka.ms/vs/17/intpreview/vs_community.exe
call :run_command - Downloading latest internal preview VS Community installer...
call :echo - To install MSBuild, run the installer and select the Desktop C++ workload
call :echo - with only the C++ core desktop features selected.
call :echo - Launch Programs and Features to verify VS installation...
start appwiz.cpl
echo [%TIME%] Finish Installing VS.
exit /b 0

:install_vcrt
echo [%TIME%] Installing VC runtimes...
if exist "%USERPROFILE%\Downloads\vc_redist.*.exe" (
    set $cmd=del "%USERPROFILE%\Downloads\vc_redist.*.exe"
    call :run_command - deleting existing vc_redist downloads...
)
call :echo - downloading latest VC runtime (vc_redist) installers...
for %%a in (x86 x64) do start https://aka.ms/vs/17/release/vc_redist.%%a.exe
pause
call :echo - running latest VC runtime installers...
for %%a in (x86 x64) do "%USERPROFILE%\Downloads\vc_redist.%%a.exe" /install /q
call :echo - check Programs and Features to verify install...
start appwiz.cpl
echo [%TIME%] Finish Installing VC runtimes.
exit /b 0

:show_environment
echo Showing environment variables (%*)...
echo **********
for %%e in (%$_envvarList%) do set %%e
echo **********
exit /b 0

:run_command
rem exitCode run_command(message) [$cmd]
rem Prints the message+command, runs the command (in $cmd), returns the exit code from the command
echo %* [command: %$cmd%]
call %$cmd%
set _exitCode=%ERRORLEVEL%
exit /b %_exitCode%

:done
exit /b 0
