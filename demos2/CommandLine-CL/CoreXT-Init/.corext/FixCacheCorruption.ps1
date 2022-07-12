#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

<#
.SYNOPSIS

Marks packages that are corrupt for re-download by CoreXT
.DESCRIPTION

This script will iterate over the set of packages in your Nuget cache and determine for each of them whether or not they have been corrupted. If they have, the tracker file in that directory will be renamed, if it exists. That will cause CoreXt to download the package again the next time it is run, and restore the cache to the correct state. 

There are two methods of determining whether or not a package has been corrupted. 

1.) If GenerateExpectedFileLists.ps1 has been run already, there will be an ExpectedFileList.txt file in each package directory. The contents of that file is a simple list of the relative paths (to the cache root) of each file under the directories. The expectation is that this list was generated when the cache was in a good state so this is the full set of expected files. We will go through the list of all the files and check if any are missing. If they are, the package is flagged as corrupt. 

2.) If the ExpectedFileList.txt file cannot be found, we will instead check each file against the time the package tracker was last updated. If files have been deleted or added in a subfolder of the package folder, the LastWriteTime of that folder will have been updated at that point. The delta between that time and the tracker time will be significant and the package will be flagged as corrupt.

.EXAMPLE

FixCacheCorruption.ps1

.NOTES

.LINK

http://aka.ms/dd1es-help
.LINK

https://microsoft.sharepoint.com/teams/corext/LivingDocs/CorextInitialization.aspx
#>
[CmdletBinding(SupportsShouldProcess=$true)]
Param()

. $PSScriptRoot\Common\Environment.ps1

function Get-IsCorrupted($path)
{
    Write-Verbose "Checking $path"

    # We skip the tmp directory because it's just a working space for corext/nuget to expand files to and
    # we don't actually care about validating its contents.
    if($path.EndsWith("tmp"))
    {
        Write-Verbose "skipping tmp"
        return $false
    }

    $packageInfoFile = "$path\.devconsole.packageinfo.json"
    if(Test-Path $packageInfoFile)
    {
        $json = ConvertFrom-Json -InputObject (Get-Content -Raw $packageInfoFile)
        $expectedFiles = $json.Layout.Files
        foreach ($fileEntry in $expectedFiles)
        {
            $filePath = Join-Path -Path $path -ChildPath $fileEntry.Path
            if (!(Test-Path -LiteralPath $filePath))
            {
                Write-Host ("At least one file listed in packageinfo is missing from $path ($($fileEntry.Path))")
                return $true
            }
            if ($fileEntry.Size -ne (Get-Item -LiteralPath $filePath).Length)
            {
                Write-Host ("At least one file listed in packageinfo is the wrong size in $path ($($fileEntry.Path))")
                return $true
            }
        }
    }
    else
    {
        # Fall back on ExpectedFileList.txt
        $expectedFilesFile = "$path\ExpectedFileList.txt"
        if(Test-Path $expectedFilesFile)
        {
            $expectedFiles = Get-Content $expectedFilesFile
            # For performance reasons, we only check for missing files here.
            # We don't check for modified or added files. 
            # That would require a more expensive check which is outside the 
            # scope of the general problem we trying to solve with the cache corruption.
            foreach ($file in $expectedFiles)
            {
                if (!(Test-Path -LiteralPath (Join-Path $NugetCachePath $file)))
                {
                    Write-Host ("At least one expected file is missing from $path ($file)")
                    return $true
                }
            }
        }
        else
        {
            # Fall back on using last write time
            $trackerFile = Get-TrackerFileLocationForPackage $path
            if(Test-Path $trackerFile)
            {
                [DateTime]$whenCoreXtAddedIt = gc $trackerFile
            }
            else
            {
                Write-Host "$trackerFile does not exist"
                return $true
            }

            $recentlyWrittenFiles = @(Get-ChildItem $path -Recurse) + (Get-item $path) |
            ? { [datetime]$_.LastWriteTime -gt $whenCoreXtAddedIt } |
            ? { $_.Name -ne ".tracker" } |
            ? { Get-IsFileModifiedAfterCoreXtAddedIt $_ $whenCoreXtAddedIt } 

            if($recentlyWrittenFiles.Count -gt 0) 
            {
                Write-Host "Folders or files were updated after the tracker file"; 
                return $true 
            }
        }
    }
    return $false
}

function Get-IsFileModifiedAfterCoreXtAddedIt($file, $trackertime)
{
    return ([datetime]$file.LastWriteTime - $trackertime) -gt [timespan]"0:0:1"
}

function Get-TrackerFileLocationForPackage($path)
{
    return Join-Path $path ".tracker"
}

function Delete-PackageIfCorrupted
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($path)

    if(Get-IsCorrupted $path)
    {
        Write-Host -ForegroundColor Red "$path is corrupted"
        Write-Verbose "Deleting package $path"

        try
        {
            if($pscmdlet.shouldprocess("rmdir /s /q $path"))
            {
                $output = Invoke-Command { cmd /c rmdir /s /q $path 2>&1 }
                return @{"Success" = !(Test-Path -PathType Container $path); "Output" = $path + " " + $output}
            }
        }
        catch
        {
            return @{"Success" = $false; "Output" = $_.Exception.Message }
        }
    }

    return @{"Success" = $true; "Output" = "No corrupt package to delete"}
}

function Load-DevConsoleCacheSettings($nugetCachePath)
{
    $filePath = Join-Path $nugetCachePath ".devconsole.cache.json"
    if (Test-Path $filePath)
    {
        return (Get-Content ($filePath) -Raw) | ConvertFrom-Json
    }

    return $null
}

function Get-SubDirectoryPackageFolders($subFolderPath)
{
    $resultFolders = @()
    if(Test-Path $subFolderPath)
    {
        $folders = Get-ChildItem $subFolderPath -Directory

        foreach($folder in $folders)
        {
            # Ignore subfolders containing aggregate packages
            $aggregateFiles = Get-ChildItem $(Join-Path $subFolderPath $folder) -Recurse -Include ".aggregate"
            if($aggregateFiles.Count -eq 0)
            {
                $resultFolders += $folder
            }
        }
    }

    return $resultFolders
}

function Get-PackageFolders($nugetCachePath)
{
    # Get all package folders from Nuget cache path excluding those beginning with "."
    $packageFolders = @()
    $packageFolders += Get-ChildItem $nugetCachePath -Directory -Exclude ".*"

    # Corext also extracts packages to sub folders within nuget cache root path to prevent conflict issues.
    # Get list of sub folders from .devconsole.cache.json file
    $settings = Load-DevConsoleCacheSettings $nugetCachePath

    if($settings -ne $null)
    {
        foreach ($setting in $settings.Caches)
        {
            $subFolderPath = Join-Path $nugetCachePath $setting.CachePath
            $subDirPackages = Get-SubDirectoryPackageFolders $subFolderPath
            $packageFolders += $subDirPackages
        }
    }
    
    return $packageFolders
}

function Fix-Packages($nugetCachePath)
{
    $overAllResult = @()
    $packageFolders = Get-PackageFolders $nugetCachePath
    
    foreach ($package in $packageFolders)
    {
        $result = Delete-PackageIfCorrupted $package.FullName
        if (!$result.Success)
        {
            $overAllResult += $result.Output
        }
    }

    return $overAllResult
}


$NugetCachePath =  (Get-NugetCachePath)
if (!(Test-Path $NugetCachePath))
{
    throw "Nuget cache directory does not exist at $NugetCachePath. Please run init first to ensure it is created."
}

$result = Fix-Packages $NugetCachePath

if ($result.Count -gt 0)
{
    throw [System.IO.IOException] "Error deleting corrupted packages $result"
}
