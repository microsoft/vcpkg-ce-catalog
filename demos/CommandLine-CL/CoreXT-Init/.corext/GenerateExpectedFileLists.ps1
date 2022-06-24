#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

<#
.SYNOPSIS

Generates expected file list for each package in the Nuget package cache
.DESCRIPTION

This script will traverse the set of packages and dump the set of files as a list of full paths into a file in the root of each package. This is intended to be run before FixCacheCorruption.ps1

.EXAMPLE

GenerateExpectedFileLists.ps1

.NOTES

.LINK

http://aka.ms/dd1es-help
.LINK

https://microsoft.sharepoint.com/teams/corext/LivingDocs/CorextInitialization.aspx
#>
[CmdletBinding()]
Param()

. $PSScriptRoot\Common\Environment.ps1

function GenerateExpectedFilesList($path)
{
    $expectedFileListPath = Join-Path $path ExpectedFileList.txt
    if (Test-Path $expectedFileListPath)
    {
        # The file list has already been generated and should be constant (or else we would consider it corruption)
        return
    }
    
    # We need to escape this because the path will contain characters that have special meanings in regexes and we
    # just want to replace the path altogether.
    $regexCachePath = [regex]::Escape("$NugetCachePath\")
    (dir $path -Recurse -File).FullName | % { $_ -replace $regexCachePath } | Set-Content $expectedFileListPath
    Write-Verbose "Generated expected files list for $path"
}

$NugetCachePath =  (Get-NugetCachePath)
if (!(Test-Path $NugetCachePath))
{
    throw "Nuget cache directory does not exist at $NugetCachePath. Please run init first to ensure it is created."
}

# We skip the tmp and .t directory because they are working space for corext/nuget to expand files
# We skip the other . directories created by CoreXT because they just contain package source informaion today
#  however may need to scan packages under these directories in future (dependent on CoreXT changes)
Get-ChildItem $env:NugetMachineInstallRoot -Directory | ? { $_.Name -ne "tmp"  -and -not $_.Name.StartsWith(".") }| % { GenerateExpectedFilesList($_.FullName) }