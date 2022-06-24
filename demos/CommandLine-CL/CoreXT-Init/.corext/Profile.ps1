# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches

# This script is used to view and edit profile selections for the enlistment.

[CmdletBinding(DefaultParametersetName="help")]
param (
    [Parameter(Mandatory=$true, ParameterSetName="discover")]
    [switch] $Discover,
    [Parameter(Mandatory=$true, ParameterSetName="list")]
    [switch] $List,
    [Parameter(Position=0, Mandatory=$true, ParameterSetName="set")]
    [String] $Set,
    [Parameter(Position=0, Mandatory=$true, ParameterSetName="add")]
    [String] $Add,
    [Parameter(Position=1, Mandatory=$false, ParameterSetName="set")]
    [Parameter(Position=1, Mandatory=$false, ParameterSetName="add")]
    [AllowEmptyString()]
    [String[]] $Value
)

. "$PSScriptRoot\Common\SettingManager.ps1"
. "$PSScriptRoot\Common\AuxiliaryEnlistment.ps1"
. "$PSScriptRoot\Common\Components.ps1"

function Profile-SupportsMultipleValues($profileName)
{
    if ($profileName -eq "CoreXT")
    {
        return $true
    }
    return $false
}

function Print-ProfileValue($profileName, $values)
{
    $multiSelect = Profile-SupportsMultipleValues $profileName
    foreach ($value in $values)
    {
        if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent -eq $true)
        {
            # Print the results in "Verbose" mode (from the PS default cmdlet argument '-Verbose')
            Write-Output "---------------------------------------------"
            Write-Output "Profile: $profileName"
            Write-Output "Value: $($value.Name)"
            Write-Output "Description: $($value.Description)"
            Write-Output "Multiselect: $multiSelect"
        }
        else
        {
            # The reason we pass the list of properties to Select-Object when printing the results to the screen
            # is so that we can specify the exact order in which the columns are printed. Without this, the
            # order of the columns will be determined by the order of the keys in the hashtable, which is
            # not what we want.
            New-Object PSObject -Property @{ Profile = $profileName; Value = $value.Name; Description = $value.Description; Multiselect = $multiSelect } |
              Select-Object -Property Profile, Value, Description, Multiselect
        }
    }
}

function List-ProfileSelections()
{
    $profiles = Get-AvailableProfiles
    foreach ($profileName in $profiles.Keys | Sort-Object)
    {
        $value = Get-Profile $profileName
        $properties = @{
            Name = $value;
            Description = $profiles[$profileName] | ?{ $_.Name -eq $value } | %{ $_.Description }
        }
        Print-ProfileValue $profileName @($properties)
    }
}

function List-AvailableProfiles()
{
    foreach ($profile in (Get-AvailableProfiles).GetEnumerator() | Sort-Object Name)
    {
        Print-ProfileValue $profile.Name $profile.Value
    }
}

function Get-AvailableProfiles()
{
    $profiles = @{}

    # TODO: refactor to delegate this logic to each plugin. I.e, say "Plugin: please provide me with the list of profile names/values you support"
    # For now, we will store this logic centrally until the init refactoring work is completed.

    Load-CoreXTProfiles $profiles
    Load-TfsProfiles $profiles
    Load-GitProfiles $profiles
    Load-VstsDropProfiles $profiles
    Load-ComponentProfiles $profiles

    return $profiles
}

function Load-CoreXTProfiles($profiles)
{
    if (Test-Path $CoreXtConfigFile)
    {
        [xml]$xml = Get-Content $CoreXtConfigFile
        $profiles["CoreXT"] = $xml.corext.profiles.profile | %{ @{ Name = $_.name; Description = $_.description } }
    }
}

function Load-TfsProfiles($profiles)
{
    $configPath = Get-AuxConfigPath
    if (Test-Path $configPath)
    {
        $config = Get-Content -Raw $configPath | ConvertFrom-Json
        if ($config.WorkspaceMappings)
        {
            foreach ($workspaceName in $config.WorkspaceMappings | Get-Member -MemberType NoteProperty | %{ $_.Name })
            {
                $workspaceProfiles = $config.WorkspaceMappings.$workspaceName.Profiles
                $profiles[$workspaceName] = $workspaceProfiles | Get-Member -MemberType NoteProperty | %{ @{ Name = $_.Name; Description = $workspaceProfiles.($_.Name).Description } }
            }
        }
    }
}

function Load-GitProfiles($profiles)
{
    $configPath = Get-AuxConfigPath
    if (Test-Path $configPath)
    {
        $config = Get-Content -Raw $configPath | ConvertFrom-Json
        if ($config.RepoConfigurations)
        {
            foreach ($repo in $config.RepoConfigurations | Get-Member -MemberType NoteProperty | %{ $_.Name })
            {
                $repoProfiles = $config.RepoConfigurations.$repo.Profiles
                $profiles[$repo] = $repoProfiles | Get-Member -MemberType NoteProperty | %{ @{ Name = $_.Name; Description = $repoProfiles.($_.Name).Description } }
            }
        }
    }
}

function Load-VstsDropProfiles($profiles)
{
    $configPath = Get-AuxConfigPath
    if (Test-Path $configPath)
    {
        $config = Get-Content -Raw $configPath | ConvertFrom-Json
        if ($config.VstsDropConfigurations)
        {
            foreach ($drop in $config.VstsDropConfigurations | Get-Member -MemberType NoteProperty | %{ $_.Name })
            {
                $dropProfiles = $config.VstsDropConfigurations.$drop.Profiles
                $profiles[$drop] = $dropProfiles | Get-Member -MemberType NoteProperty | %{ @{ Name = $_.Name; Description = $dropProfiles.($_.Name).Description } }
            }
        }
    }
}

function Set-ProfileValues($profileName, $values)
{
    Save-Profile $profileName ($values -join ",")
}

function Add-ProfileValues($profileName, $values)
{
    if (-not (Profile-SupportsMultipleValues $profileName))
    {
        throw "The profile '$profileName' does not support multiple values"
    }

    $existing = Get-Profile $profileName
    $newValues = @()
    if ($existing -ne "")
    {
        $newValues = $existing -split ","
    }

    # Add the new values to the list while removing duplicates (case-insensitive)
    $newValues = ($newValues + $values) | Sort-Object -Unique

    # Save the new combined value back
    Set-ProfileValues $profileName $newValues
}

if ($IsUnderTest)
{
    exit
}

Set-Environment

switch($PSCmdlet.ParameterSetName)
{
    "help" {
        Write-Output "Display or update profile selections for the enlistment."
        Write-Output "To display all available profiles, run '-Discover [-Verbose]'"
        Write-Output "To display profile selections, run '-List [-Verbose]'"
        Write-Output "To update profile selections, run '-Set {profileName} [-Value {value}]'"
        Write-Output "To add a new value to a multiselect-enabled profile, run '-Add {profileName} [-Value {value}]'"
        break
    }

    "discover" {
        List-AvailableProfiles | Format-Table -AutoSize
        break
    }

    "list" {
        List-ProfileSelections | Format-Table -AutoSize
        break
    }

    "set" {
        Set-ProfileValues $Set $Value
        List-ProfileSelections | Format-Table -AutoSize
        break
    }

    "add" {
        Add-ProfileValues $Add $Value
        List-ProfileSelections | Format-Table -AutoSize
        break
    }
}
