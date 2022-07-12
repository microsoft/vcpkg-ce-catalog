# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches

# This script will pull component manifests from specified uris to a local directory based on a configuration file.

#remove this CmdBinding code when move to Provider
[CmdletBinding(DefaultParametersetName="execute")]
param (
    # Full path to the configuration file containing components configuration (typically branches.json)
    [Parameter(Position=0, Mandatory=$false, ParameterSetName="execute")]
    [AllowEmptyString()]
    [String] $ConfigFilePath,
    [Parameter(ParameterSetName="checkForUpdates")]
    [Switch] $CheckIfUpdatesAreNeeded
)

. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\FastUpdateCheck.ps1"
 ."$PSScriptRoot\Common\Components.ps1"

function Get-ComponentPolicy()
{
    if (Test-Path ($ConfigFilePath))
    {
        if (Should-UseOfficialBuildProfile)
        {
            Save-Profile "Components" "OfficialBuild"
        } 

        # Get the active profile from setting manager
        $profile = Get-Profile "Components"

        # Load the configuration from branches.json
        $config = Get-Content -Raw  $ConfigFilePath | ConvertFrom-Json

        if ($config.Components)
        {
            # Get the output directory
            $localRoot = $config.Components.LocalRoot

            # Extract the policy for the active profile
            $componentConfig = $config.Components.Profiles;
            $policy = $componentConfig.($profile).SyncPolicy

            return @{ "LocalRoot" = $localRoot; "SyncPolicy" =  $policy }
        }
    }
    return $null
}

function Get-ComponentsList()
{
    $componentsListPath = Get-ComponentsListPath
    if (Test-Path $componentsListPath)
    {
        $componentsList = Get-Content -Raw $componentsListPath | ConvertFrom-Json
        return $componentsList
    }
    return $null
}

function Get-Components($policy = $(Get-ComponentPolicy))
{
    $localRoot = Join-Path (Get-SourceRoot) $policy.LocalRoot
    $componentsList = Get-ComponentsList;
    if ($componentsList)
    {
        $names = ($componentsList.Components | Get-Member -MemberType NoteProperty).Name
        foreach ($name in $names)
        {
            $component = $componentsList.Components.($name)
            $localPath = $component.fileName
            $destinationPath = Join-Path $localRoot $localPath
            $url = $component.url
            @{"Name"=$name; "FileName"=$localPath; "Url"=$Url; "DestinationPath"=$destinationPath}
        }
    }
}

function Generate-ComponentsOutFiles($policy = $(Get-ComponentPolicy))
{
    $properties = @{}
    $properties["ComponentsOutputLocalRoot"] = $policy.LocalRoot
    $properties["ComponentsOutputFullPath"] = Join-Path (Get-SourceRoot) $policy.LocalRoot

    Create-MsbuildPropsFile (Get-OutFilePath "components.props") $properties

    return $properties
}

function Invoke-Provider([string]$state)
{
    $policy =  Get-ComponentPolicy
    if ($policy)
    {
        Write-Host "Using Components policy: $($policy.SyncPolicy)"

        if ($policy.SyncPolicy -eq "All")
        {
            $components = Get-Components($policy);
            $localRoot = $policy.LocalRoot
            $failCount = 0
            foreach ($component in $components)
            {
                $localPath = $component.FileName
                $url = $component.Url
                $destinationPath = $component.DestinationPath
                $destinationDirectory = Split-Path $destinationPath -Parent
                Write-Host "  Downloading $url to $destinationPath"

                # Call with retries if running in non-interactive mode
                $retry = 0
                $retryTimeouts = @( 5, 25, 90, 180 )
                $success = $false
                Do
                {
                    try
                    {
                        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
                        Invoke-WebRequest -Uri $url -OutFile $destinationPath
                        $success = $true
                    }
                    catch [System.Net.WebException]
                    {
                        $lastException = "Failed to download $localPath from $url : $($_.Exception.Message)"
                        Write-Host $lastException
                    }
                    catch [System.IO.IOException]
                    {
                        $lastException = "Failed to download $localPath from $url : $($_.Exception.Message)"
                        Write-Host $lastException
                    }

                    $terminationCondition = $success -or $retry -ge $retryTimeouts.Count -or -not (Get-NonInteractive)
                    if (-not $terminationCondition)
                    {
                        Write-Host -Foreground Yellow "Retry attempt $retry in $($retryTimeouts[$retry]) seconds"
                        Start-Sleep $retryTimeouts[$retry]
                        $retry++
                    }
                }
                Until ( $terminationCondition )
                if (-not $success)
                {
                    $failCount++
                }
            }
            if ($failCount -gt 0)
            {
               throw "Failed to download $failCount components. Last error: $lastException"
            }
            else
            {
                $hash = Get-CurrentHash
                Save-Setting "ComponentsStateHash" $hash
            }
        }
        Generate-ComponentsOutFiles $policy | Out-Null
    }
}

function Verify-ComponentsCache($policy = $(Get-ComponentPolicy))
{
    $components = Get-Components($policy);
    foreach ($component in $components)
    {
        if (!(Test-Path $component.DestinationPath))
        {
            return $false
        }
    }
    return $true
}

#$state is not being used right now
function Test-ShouldInvoke([string]$state)
{
    $policy = Get-ComponentPolicy
    if ($policy.SyncPolicy -eq "All")
    {
        $componentsListPath = Get-ComponentsListPath
        if (Test-Path $componentsListPath)
        {
            $hash = Get-CurrentHash
            $previousHash = Get-Setting "ComponentsStateHash"
            if ($hash -ne $previousHash -or -not (Verify-ComponentsCache($policy)) )
            {
                return $true
            }
        }
    }
    return $false
}

function Get-CurrentHash($policy = $(Get-ComponentPolicy))
{
    $componentsListPath = Get-ComponentsListPath
    if (Test-Path $componentsListPath)
    {
        $componentsList = Get-Content -Raw $componentsListPath

        $text ="Policy::"
        $policy.GetEnumerator() | Sort-Object -Property Key | ForEach-Object { $text += "$($_.Key):$($_.Value);" }
        $text += [Environment]::NewLine
        $text += $componentsList
        $hash = Get-TextHash($text)
        return $hash
    }
    return $null
}

# main code. This section of code should be removed when this file is converted to a real provider
if ($IsUnderTest)
{
    exit
}

$ErrorActionPreference = "Stop"

if (-not $ConfigFilePath)
{
    $ConfigFilePath = Get-ComponentConfigPath
}

switch($PSCmdlet.ParameterSetName)
{
    "execute"
    {
        Invoke-Provider $null | Write-Host
        break
    }

    "checkForUpdates"
    {
        $needUpdate = Test-ShouldInvoke $null
        if ($needUpdate)
        {
            exit 1
        }
        exit 0
        break # shouldn't be needed, but added in case of refactoring later
    }
}

