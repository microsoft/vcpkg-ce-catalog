#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

#Requires -Version 3.0
[CmdletBinding()]
Param()

. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\PackageCache.ps1"
. "$PSScriptRoot\Common\FastUpdateCheck.ps1"

function Check-CoreXT()
{
    $shouldInvoke, $message = Test-ShouldInvokeCoreXt
    if ($shouldInvoke)
    {
        Write-Host -ForegroundColor Yellow "CoreXT updates are required"
        if ($message) 
        {
            Write-Host $message
        }
        exit 1
    }
}

# Note: This will be moved into CoreXTProvider later.
function Test-ShouldInvokeCoreXt()
{
    $packageListFile = Get-PackageListFile
    if (!(Test-Path $packageListFile))
    {
        return $true, "Package list file at $packageListFile is missing"
    }
    
    $lastUpdateCheckPath = Get-OutFilePath "LastUpdateCheck.sem"
    $previousAllPackagesHash = Get-PreviousCoreXTHash -filteredPackagesHash $false
    $currentAllPackagesHash = Get-CurrentCoreXtHash -filteredPackagesHash $false

    Write-Verbose "CoreXT Hashes are computed based on the contents of $CoreXtConfigFile and the value of the CoreXT Profile"
    Write-Verbose "Current hash (all packages): $currentAllPackagesHash"
    Write-Verbose "Previous hash (all packages): $previousAllPackagesHash"

    # Most of the time, the contents of the config file won't change between subsequent
    # checks for whether or not updates are required. Therefore, we can save time by
    # quickly computing the hash for all files (~ 30 millseconds.) 
    if ($previousAllPackagesHash -ne $currentAllPackagesHash)
    {
        # Do a more in-depth analysis to determine if we really need to update
        # Specifically, we will filter packages, which is a slightly (~1.5 seconds) expensive operation.
        # This way, if the changes are in versions to packages we don't care about, we can skip updating.
        Write-Verbose "The basic check failed, so we will do a more detailed check."
        $previousFilteredPackagesHash = Get-PreviousCoreXTHash $true
        $currentFilteredPackagesHash = Get-CurrentCoreXtHash $true
        Write-Verbose "Current hash (filtered packages): $currentAllPackagesHash"
        Write-Verbose "Previous hash (filtered packages): $previousAllPackagesHash"

        if ($previousFilteredPackagesHash -ne $currentFilteredPackagesHash)
        {
            # Even when we try to eliminate packages that are not selected by the current profile,
            # there is a difference in the hash value. So, we must update.
            return $true
        }
    }
    else
    {
        # Update file to compare timestamps with package configuration for faster init checks in msbuild.
        Write-Verbose "Updating $lastUpdateCheckPath"
        try
        {
            $null = New-Item $lastUpdateCheckPath -Force -ItemType File
        }
        catch
        {
            # Worst case scenario is that init checks will take longer to compare hashes.
            Write-Verbose "Failed to update $lastUpdateCheckPath"
        }
    }

    if (!(Get-AreAllExpectedPackagesStillInCache))
    {
        return $true, "At least one previously cached package is missing"
    }

    return $false
}

function Check-TFS()
{
    & "$PSScriptRoot\TfsEnlistmentProvider.ps1" -CheckIfUpdatesAreNeeded
    if ($LastExitCode -ne 0)
    {
        Write-Host -ForegroundColor Yellow "Auxiliary TFS workspace updates are required"
        exit 1
    }
}

function Check-Git()
{
    & "$PSScriptRoot\GitEnlistmentProvider.ps1" -CheckIfUpdatesAreNeeded
    if ($LastExitCode -ne 0)
    {
        Write-Host -ForegroundColor Yellow "Auxiliary git repo updates are required"
        exit 1
    }
}

function Check-VstsDrop()
{
    & "$PSScriptRoot\VstsDropProvider.ps1" -CheckIfUpdatesAreNeeded
    if ($LastExitCode -ne 0)
    {
        Write-Host -ForegroundColor Yellow "Auxiliary VSTS Drop updates are required"
        exit 1
    }
}

function Check-Components()
{
    & "$PSScriptRoot\ComponentsProvider.ps1" -CheckIfUpdatesAreNeeded
    if ($LastExitCode -ne 0)
    {
        Write-Host -ForegroundColor Yellow "Component manifest updates are required"
        exit 1
    }
}

if ($IsUnderTest)
{
    exit 
}

Set-Environment
# TODO: When the CoreXT refactoring work is completed, these functions should be refactored into their respective plugins.
# Then, this script should just ask each plugin if they need to be invoked. We should also make it so that init plugins
# can run independently. I.e, if the TFS workspaces are out of date, but the CoreXT packages are not, then only run the
# TFS workspaces updating code and not the CoreXT updating code.
    
# These functions should 'exit' as soon as they detect that they are out of date (fail-fast)
Check-CoreXT

if (-not $env:QBUILD_DISTRIBUTED)
{
    Check-VstsDrop
    Check-TFS
    Check-Git
    Check-Components
}

Write-Host -ForegroundColor Cyan "Everything is up to date, no updates required"
exit 0
