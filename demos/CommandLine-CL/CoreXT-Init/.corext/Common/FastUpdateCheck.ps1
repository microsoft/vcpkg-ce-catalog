#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

#Requires -Version 3.0

function Get-TextHash($text)
{
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $MD5 = [System.Security.Cryptography.MD5]::Create()
    $hashValues = $MD5.ComputeHash($bytes)
    return ($hashValues | % { "{0:x2}" -f $_ }) -join ""
}

#region "These will be moved into CoreXtProvider later"
. "$PSScriptRoot\CoreXtConfig.ps1"
. "$PSScriptRoot\PackageCache.ps1"

function Get-AreAllExpectedPackagesStillInCache()
{
    # There are other checks that ensure that the generated config has not changed.
    # If the previous init was successful, then packagelist.inc has not changed either.
    $packages = Get-InstalledPackagesFromIncFile
    $paths = $packages.Values | Sort -Unique
    foreach ($path in $paths)
    {
        if (!(Test-Path $path))
        {
            return $false
        }
    }
    return $true
}

function Get-CoreXtTextToHash($filterPackages = $false)
{
    [xml]$configXml = Get-Content $CoreXtConfigFile
    if($filterPackages)
    {
        $profilesXml = Get-CoreXTRawProfiles $configXml 
        Write-Output $profilesXml.OuterXml
        Select-Packages $configXml.corext.packages.package (Get-CoreXTProfiles $profilesXml) | % { Write-Output $_.OuterXml }
    }
    else
    {
        # Just write out the whole config file
        Write-Output $configXml.OuterXml	
    }
    Write-Output (Get-CoreXtProfileNames)
    Write-Output (Get-NugetCachePath)
}

function Get-CurrentCoreXtHash($filteredPackagesHash = $false)
{
    return Get-TextHash (Get-CoreXtTextToHash $filteredPackagesHash)
}

function Get-PreviousCoreXtHash($filteredPackagesHash = $false)
{
    try
    {
        if($filteredPackagesHash)
        {
            return (Get-Setting "FilteredPackagesStateHash")
        }
        else
        {
            return (Get-Setting "UnfilteredPackagesStateHash")
        }
    }
    catch
    {
        #If we can't read the settings file, just return a value that will cause linking
    }
    return 0
}

#endregion