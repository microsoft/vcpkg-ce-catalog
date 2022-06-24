# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches

. "$PSScriptRoot\Environment.ps1"

function Get-SettingsFilePath()
{
    return Join-Path (Join-Path (Get-SourceRoot) ".settings") "EnlistmentSettings.json"
}

function Load-Settings()
{
    $filePath = Get-SettingsFilePath
    if (Test-Path $filePath)
    {
        return (Get-Content ($filePath) -Raw) | ConvertFrom-Json
    }
    return $null
}

function Save-Settings($settings)
{
    $path = Get-SettingsFilePath

    # Create the directory if it doesn't exist
    $directory = Split-Path $path
    New-Item -ItemType directory $directory -Force | Out-Null

    $code = {
        # Save the settings file
        $settings | ConvertTo-Json | Set-Content $path
    }
    Invoke-SynchronizedAccess $path $code
}

# Retrieves a value from the settings file. If the value does not exist,
# it returns the empty string.
function Get-Setting($key)
{
    # For now, load the file on each get request. As an optimization, we could cache this data
    # in memory, but we would need to be aware of writes that can happen outside of this method,
    # such as via a user who manually updates the settings in the file, and expire the cache
    # entries accordingly.
    $settings = Load-Settings
    
    if ($settings -ne $null)
    {
        $value = $settings.$key
        if ($value -ne $null)
        {
            return $value
        }
    }
    return ""
}

function Save-Setting([String]$key, $value)
{
    # For now, load the file on each save request. As an optimization, we could cache this data
    # in memory, but we would need to be aware of writes that can happen outside of this method,
    # such as via a user who manually updates the settings in the file, and expire the cache
    # entries accordingly.
    $settings = Load-Settings

    if ($settings -eq $null)
    {
        $settings = @{$key=$value}
    }
    else
    {
        # ConvertFrom-Json returns a PSCustomObject so we need to add/edit properties on that object
        if (($settings | Get-Member -MemberType NoteProperty | ?{ $_.Name -eq $key }).length -gt 0)
        {
            # Update the value of the existing setting
            $settings.$key = $value
        }
        else
        {
            # Add a new setting
            $settings | Add-Member -MemberType NoteProperty -Name $key -Value $value
        }
    }

    Save-Settings $settings
}

function Get-SavedProfiles()
{
    $profiles = @{}

    $settings = Load-Settings
    if ($settings -ne $null)
    {
        foreach ($key in $settings | Get-Member -MemberType NoteProperty | ?{ $_.Name.StartsWith("Profile-") -and $settings.($_.Name) -ne ""} | %{ $_.Name })
        {
            $profileName = $key.Replace("Profile-","")
            $profiles[$profileName] = $settings.$key
        }
    }

    return $profiles
}

function Get-Profile($name)
{
    $profile = Get-Setting ("Profile-" + $name)
    if ($profile -eq "")
    {
        # If we don't have a value set for the profile, use the default
        return "Default"
    }

    return $profile
}

function Save-Profile($name, $value)
{
    Save-Setting ("Profile-" + $name) $value
}