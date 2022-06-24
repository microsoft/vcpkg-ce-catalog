#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

. "$PSScriptRoot\Environment.ps1"

function Get-OutFilePath($fileName)
{
    return Join-Path (Get-PackageAddressGenDir) $fileName
}

function Get-PackageListFile()
{
    return Get-OutFilePath packagelist.inc
}

function Get-PackageAddressGenDir()
{
    return $env:PackageAddressGenDir
}

function Get-InstalledPackagesFromIncFile()
{
    $packageListFile = Get-PackageListFile 
    
    if(!(Test-Path $packageListFile))
    {
        throw "Could not find package list file at $packageListFile. Did init.cmd run successfully?"
    }
    $rows = Get-Content $packageListFile | ? { $_ -like '*=*' }
    $packages = @{}
    foreach ($row in $rows)
    {
        $cells = $row -split '='
        try
        {
            $packages.Add($cells[0], $cells[1])
        }
        catch
        {
            if ($packages.ContainsKey($cells[0]))
            {
                Write-Host -ForegroundColor Yellow "Warning: packages dictionary already contains " + $cells[0] + " key for package " + $packages[$cells[0]] + " and " + $cells[1] + ". You should probably rename your packages."
                $packages[$cells[0]] = $cells[1]
            }
            else
            {
                throw
            }
        }
    }
    return $packages
}

function Get-PackageLocation
{
    param(
        [Parameter(Mandatory)]
        $name,
        $packages = $null
    )

    if (!$packages)
    {
        $packages = Get-InstalledPackagesFromIncFile
    }
    # Keys in the cached package locations hash 
    # follow the same pattern provided by the packageList.inc file
    # For example, PkgDevDiv_ExternalApis_AppInsights_Telemetry would be the key 
    # for the DevDiv.ExternalApis.AppInsights.Telemetry package. 
    $fixedUpName = "Pkg" + ($name -replace '[.-]','_')
    return $packages[$fixedUpName]
}

function Get-RequiredPackageLocationOrExit($name)
{
    $packageLocation = Get-PackageLocation $name
    if ($packageLocation -eq $null)
    {
        Write-Error "The required package '$name' could not be found in the cache."
        exit -1
    }
    return $packageLocation
}