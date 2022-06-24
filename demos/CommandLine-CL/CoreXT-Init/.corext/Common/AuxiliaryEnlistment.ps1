#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

. "$PSScriptRoot\GeneralUtilities.ps1"
. "$PSScriptRoot\PackageCache.ps1"

function Test-ConfigFileExists()
{
    return (Test-Path (Get-AuxConfigPath))
}

function Get-AuxConfigPath()
{
    Join-Path (Get-ConfigsFolder) "branches.json"
}

function Load-Config()
{
    # Temporary check because we are rolling out this plugin via a conditional based on if the config file exists.
    # This should be able to be removed after the init refactoring work is completed and plugins can be included
    # as needed in the enlistment.
    if (Test-ConfigFileExists)
    {
        $cachedPackageLocation = Get-RequiredPackageLocationOrExit "VS.Tools.TfvcToolFiles"
        $tfvcModulePath = Join-Path $cachedPackageLocation "TfvcTool.PowerShell.psm1"
        Import-Module $tfvcModulePath

        if (Should-UseOfficialBuildProfile)
        {
            # We need to overwrite the value of all workspace profiles to be "OfficialBuild"
            foreach ($profile in (Get-WorkspaceNames -StartingDirectory $SourceRoot))
            {
                Save-Profile $profile "OfficialBuild"
            }
        }

        # TODO: Pass in the branch information for build machines,
        # because auto-detection is not reliable for official branches for Git.
        $params = @{
            'location' = $SourceRoot;
            'workspaceProfiles' = Get-SavedProfiles;
            'getPackageLocation' = { return Get-RequiredPackageLocationOrExit $args[0] };
        }
        return Get-BranchInfo @params -Verbose:$VerbosePreference
    }
    return $null
}

function Generate-EnlistmentStatusFileContent($config, $jsonPropertiesToRemove)
{
    # -Depth 5 is needed because by default, ConvertTo-Json only serializes to depth 2, which means that
    # if you have deeply nested objects, it will not serialize them all the way down. When it stops at 
    # the max depth, it just calls ToString() on the leaf node, which is not what we want here. The $config
    # object is a bit more complex, so we tell it to serialize all properties down 5 levels, which covers
    # all of the properties on the object.

    # Convert the string to lowercase so that different casing of file paths does not produce a different
    # hashed result. This is needed because Windows file paths are case-insensitive, so d:\git\path and
    # D:\git\path should be considered identical for the workspace state.
    $jsonString = ConvertTo-Json $config -Depth 5

    if ($jsonPropertiesToRemove -ne $null)
    {
        $jsonObject = ConvertFrom-Json $jsonString
        ForEach ($property in $jsonPropertiesToRemove)
        {
            $jsonObject.PSObject.Properties.Remove($property)
        }

        $jsonString = ConvertTo-Json $jsonObject -Depth 5
    }

    return $jsonString.ToLowerInvariant()
}

function Load-EnlistmentStatusFileContent($location)
{
    if (Test-Path $location)
    {
        return (Get-Content $location -Raw)
    }
    return ""
}

function Get-EnlistmentStatusFileLocation($enlistmentFile)
{
    return (Join-Path (Get-PackageAddressGenDir) $enlistmentFile)
}

function Save-EnlistmentStatusFileContent($location, $content)
{
    try
    {
        # We use WriteAllText instead of Set-Content because Set-Content appends a newline character
        # at the end of the stream. This would break our hash that determines if updates are needed, so
        # instead we want to write the bytes in exactly the same way as we expect
        [IO.File]::WriteAllText($location, $content)
    }
    catch
    {
        Write-Output "Could not update enlistment status file at '$location'. The next run of init.cmd will not used the cached state file."

        # Try to remove the old cached file if it exists since it is now incorrect. We want the next
        # invocation of the script to always show that it is out of date since we could not record
        # the current state properly.
        try
        {
            if (Test-Path $location)
            {
                Remove-Item $location
            }
        }
        catch
        {
            throw "Could not remove old enlistment state file at '$location'. Please manually delete the file or run init /force next time."
        }
    }
}

function Test-UpdatesAreNeeded($config, $enlistmentFile, $jsonPropertiesToRemove)
{
    # If the configuration is null, then that means we have no work to do, so we are therefore up to date
    if ($config -ne $null)
    {
        $workspacesFileLocation = Get-EnlistmentStatusFileLocation $enlistmentFile
        $current = Get-TextHash (Generate-EnlistmentStatusFileContent $config $jsonPropertiesToRemove)
        $previous = Get-TextHash (Load-EnlistmentStatusFileContent $workspacesFileLocation)

        Write-Verbose "Hashes are computed based on the contents of auxiliary enlistment and the sync semantics"
        Write-Verbose "The previous auxiliary enlistment content is stored at $workspacesFileLocation"
        Write-Verbose "The current auxiliary enlistment content is determined via the config file and the tags determined by the current commit"
        Write-Verbose "Current hash: $current"
        Write-Verbose "Previous hash: $previous"

        if ($previous -ne $current)
        {
            return $true
        }
    }
     
    return $false
}