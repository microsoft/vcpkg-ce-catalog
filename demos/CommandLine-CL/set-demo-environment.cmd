@echo off

echo Setting demo environment (variables and shortcuts)...
set $_vcpkgDemoDir=c:\VcpkgDemo
set $_vcpkgInstallDir=%USERPROFILE%\.vcpkg
set $_vcpkgCatalogsDir=%$_vcpkgDemoDir%\catalogs
set $_vcpkgCatalogRoot=%$_vcpkgCatalogsDir%\vcpkg-ce-catalog.demo1
set $_vcpkgTempDir=%TEMP%\vcpkg
set $_corextNugetCache=c:\NugetCache
set $_nugetPackageCache=%USERPROFILE%\.nuget\packages
doskey bootstrap=demo.cmd bootstrap
doskey acquire=demo.cmd acquire
doskey activate=demo.cmd activate
doskey build=demo.cmd build
doskey activatex86=demo.cmd activatex86
doskey activatex64=demo.cmd activatex64
doskey x86=demo.cmd activatex86
doskey x64=demo.cmd activatex64

