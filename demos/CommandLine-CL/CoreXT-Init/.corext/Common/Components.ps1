#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

function Get-ComponentConfigPath()
{
    Join-Path (Get-ConfigsFolder) "branches.json"
}

function Get-ComponentsListPath()
{
    Join-Path (Get-ConfigsFolder) "components.json"
}

function Load-ComponentProfiles($profiles)
{
    $configPath = Get-ComponentConfigPath
    if (Test-Path $configPath)
    {
        $config = Get-Content -Raw $configPath | ConvertFrom-Json
        $componentProfiles = $config.Components.Profiles
        if ($componentProfiles)
        {
            $profiles["Components"] = $componentProfiles | Get-Member -MemberType NoteProperty | %{ @{ Name = $_.Name; Description = $componentProfiles.($_.Name).Description } }
        }
    }
}
