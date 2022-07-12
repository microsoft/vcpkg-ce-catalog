#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

#Requires -Version 3.0
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [String] $Destination
)

. "$PSScriptRoot\Common\Environment.ps1"


if ($IsUnderTest)
{
    exit
}

$ScriptTotalTime = Measure-Command {
    $coreXtProfileConfigFile = Get-CoreXtProfileConfigFile
    
    Write-Host "Downloading Metadata to $Destination"

    if (!(Test-Path $Destination))
    {
        New-Item -ItemType Directory -Force -Path $Destination
    }
    else
    {
        Remove-Item (Join-Path -Path $Destination -ChildPath "*.metadata")
    } 

    [xml]$xml = Get-Content $coreXtProfileConfigFile

    $packages = $xml.corext.packages
    
    # Only look in file repositories for .metadata files
    $regex = "^((\\\\[a-zA-Z0-9-]+\\[a-zA-Z0-9`~!@#$%^&(){}'._-]+([ ]+[a-zA-Z0-9`~!@#$%^&(){}'._-]+)*)|([a-zA-Z]:))(\\[^ \\/:*?""<>|]+([ ]+[^ \\/:*?""<>|]+)*)*\\?$"
    $repositories = $xml.corext.repositories.repo | %{ $_.uri } | ? { $_ -match $regex } 


    foreach ($package in $packages.package)
    {
        $metadataFilename = $package.id + "." + $package.version + ".metadata"

        foreach ($repo in $repositories)
        {
            $metadataPath = Join-Path $repo -ChildPath $metadataFilename
            if (Test-Path $metadataPath)
            {
                Write-Host " " $metadataPath
                Copy-Item -Path $metadataPath -Destination (Join-Path -Path $Destination -Child $metadataFilename)
                break;
            }
        }
    }
}

Write-Host Total execution time for Download-Metadata: $ScriptTotalTime