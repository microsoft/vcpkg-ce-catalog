#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

#Requires -Version 3.0
[CmdletBinding()]
Param()

. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\CoreXtConfig.ps1"

try
{
    $coreXtProfileConfigFile = Get-CoreXtProfileConfigFile
    $targetFolder = [IO.Path]::GetDirectoryName($coreXtProfileConfigFile)
    if (!(Test-Path $targetFolder))
    {
        mkdir $targetFolder | Out-Null
    }

    [xml]$xml = Get-Content $CoreXtConfigFile

    Remove-PackagesNotUsedByCoreXTProfileInXmlElement $xml
    Update-RepositoryForLocation $xml $CoreXtConfigFile

    $xml.PreserveWhitespace = $false    #this results in better formatting
    $xml.Save($coreXtProfileConfigFile)

    Write-Host "Created $coreXtProfileConfigFile"
    exit 0
}
catch
{
    Write-Error $_
    exit 1
}
