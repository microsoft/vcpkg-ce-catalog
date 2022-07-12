@echo off

:init
if "%$_DEMO_ENVIRONMENT_INITIALIZED%" NEQ "" goto :skip_demo_env_init
call ..\set-demo-environment.cmd
set $_DEMO_ENVIRONMENT_INITIALIZED=1
set $_envvarList=VCPKG Enable INC LIB VC_
doskey reset_demo_env=set $_DEMO_ENVIRONMENT_INITIALIZED=
:skip_demo_env_init
set $_actionOptions=bootstrap acquire activate activatex86 activatex64 build
set $_activateTarget=
set $_activateShowConfig=true
set $_actions=
set $_exitCode=
set $_cmdVcpkg=.\vcpkg-init.cmd

:process_args
set $_actions=%*
if /I "%$_actions%" == "" echo Running all actions 'bootstrap acquire activate run'... & set $_actions=%$_actionOptions%
setlocal enabledelayedexpansion
set _allOptionsValid=true
set _invalidActionList=
for %%a in (%$_actions%) do (
    set _fIsValidOption=false
    for %%o in (%$_actionOptions%) do (
        if /I "%%a" == "%%o" set _fIsValidOption=true
    )
    if "!_fIsValidOption!" == "false" (
        set _allOptionsValid=false
        set _invalidActionList=!_invalidActionList! %%a
    )
)
if "%_allOptionsValid%" == "false" (
    echo ERROR: invalid actions '%_invalidActionList:~1%' specified, valid actions are {%$_actionOptions%}
    exit /b 1
)
endlocal

:start
for %%a in (%$_actions%) do (
    call :%%a
)
goto :done

:bootstrap
echo [%TIME%] Start Bootstrap...
set $_exitCode=0

call :echo Installing Git...
call where.exe git.exe >nul 2>&1
if errorlevel 1 (
    echo - Git not installed, please install from https://gitforwindows.org/
    start https://gitforwindows.org/
) else (
    echo - Git is already installed
)

call :echo Installing vcpkg...
if not exist "%$_vcpkgInstallDir%" (
    echo - Downloading...
    curl -LO https://aka.ms/vcpkg-init.cmd
    echo - Running vcpkg-init...
    if exist .\vcpkg-init.cmd call .\vcpkg-init.cmd
) else (
    echo - Vcpkg is already installed
)

:install_vcpkg_ce_catalog
call :echo Installing vcpkg-ce-catalog (private)...
if not exist %$_vcpkgCatalogRoot% (
    echo - Cloning...
    git clone https://github.com/markle11m/vcpkg-ce-catalog.git %$_vcpkgCatalogRoot%
    pushd %$_vcpkgCatalogRoot%
    echo - Updating to current branch...
    git checkout msvc-experiments
    git pull
    popd
) else (
    echo - Updating to current branch...
    pushd %$_vcpkgCatalogRoot%
    git checkout -f
    git pull
    git checkout msvc-experiments
    git pull
    popd
)

:update_catalog
call :echo Updating catalog index
call %$_cmdVcpkg% z-ce regenerate %$_vcpkgCatalogRoot%

:install_empty_manifest
call :echo Activating empty manifest to bootstrap core dependencies...
copy vcpkg-configuration.json-bootstrap vcpkg-configuration.json
call %$_cmdVcpkg% activate

:set_environment
call :echo Setting bootstrapped demo environment...
call setenv.cmd

:end_bootstrap
echo [%TIME%] Finish Bootstrap...
exit /b %$_exitCode%

:acquire
echo [%TIME%] Start Acquisition...
echo No action taken, acquisition will be done as part of the activation step.
:end_acquire
echo [%TIME%] Finish Acquisition...
exit /b %$_exitCode%

:activatex86
set $_activateTarget=x86
set $_activateShowConfig=
goto :activate
:activatex64
set $_activateTarget=x64
set $_activateShowConfig=
goto :activate

:activate
if "%$_activateTarget%" == "" set $_activateTarget=x86
echo [%TIME%] Start Activation (--target:%$_activateTarget%)...
set $_exitCode=0
call :echo Update to demo manifest...
copy vcpkg-configuration.json-demo vcpkg-configuration.json
if "%$_activateShowConfig%" == "true" (
    start notepad vcpkg-configuration.json
    pause
)
call :show_environment initial
call :echo Activating (%$_activateTarget%)...
call %$_cmdVcpkg% activate --target:%$_activateTarget%
call :show_environment activated
:end_activate
echo [%TIME%] Finish Activation...
exit /b %$_exitCode%

:build
echo [%TIME%] Start Build and Run...
set $_exitCode=0
setlocal
pushd %$_vcpkgDemoDir%\Samples\HelloWorld
call buildit.cmd
call runit.cmd
popd
endlocal
:end_build
echo [%TIME%] Finish Build...
exit /b %$_exitCode%

:echo
title %*
echo [%TIME%] %*
exit /b 0

:show_environment
echo Showing environment variables (%*)...
for %%e in (%$_envvarList%) do set %%e
exit /b 0

:done
exit /b 0
