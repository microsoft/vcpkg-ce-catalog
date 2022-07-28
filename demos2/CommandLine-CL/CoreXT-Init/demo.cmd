@echo off

:init
if "%$_DEMO_ENVIRONMENT_INITIALIZED%" NEQ "" goto :skip_demo_env_init
call ..\set-demo-environment.cmd
set $_envvarList=Enable INC LIB VC_
set $_DEMO_ENVIRONMENT_INITIALIZED=1
doskey reset_demo_env=set $_DEMO_ENVIRONMENT_INITIALIZED=
:skip_demo_env_init
set $_actionOptions=bootstrap acquire activate activatex86 activatex64 build
set $_activateTarget=
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

:install_empty_manifest
call :echo Activating empty manifest to bootstrap core dependencies...
copy default.config-bootstrap .corext\Configs\default.config
call init.cmd

:end_bootstrap
echo [%TIME%] Finish Bootstrap...
pause
exit /b %$_exitCode%

:acquire
echo [%TIME%] Start Acquisition...
call :echo Using demo manifest to install MSVC and Windows SDK...
copy default.config-demo .corext\Configs\default.config
copy components.json-demo .corext\Configs\components.json
call init.cmd
:end_acquire
echo [%TIME%] Finish Acquisition...
pause
exit /b %$_exitCode%

:activatex86
set $_activateTarget=x86
goto :activate
:activatex64
set $_activateTarget=x64
goto :activate

:activate
if "%$_activateTarget%" == "" set $_activateTarget=x86
echo [%TIME%] Start Activation (--target:%$_activateTarget%)...
set $_exitCode=0

call :show_environment initial
call :echo Activating (%$_activateTarget%)...
call set-corext-environment.cmd --target:%$_activateTarget%
call :show_environment activated

:end_activate
echo [%TIME%] Finish Activation...
pause
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
pause
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
