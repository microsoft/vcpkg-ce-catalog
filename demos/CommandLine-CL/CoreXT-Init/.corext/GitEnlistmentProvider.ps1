# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches

# This script is used to manage a sub-git repo under a bigger git repo
# This script will do git clone into auxiliary folders
# based on configuration file.
#
# It is also coded up to be compatible with new init.ps1 Provider model
# design, so that it is easy to switch over

#remove this CmdBinding code when move to Provider
[CmdletBinding(DefaultParametersetName="execute")]
param (
    # The full path to the configuration file that contains the workspace mapping information.
    [Parameter(Position=0, Mandatory=$false, ParameterSetName="execute")]
    [AllowEmptyString()]
    [String] $ConfigFilePath,
    [Parameter(ParameterSetName="checkForUpdates")]
    [Switch] $CheckIfUpdatesAreNeeded
)

. "$PSScriptRoot\Common\PackageCache.ps1"
. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\GitUtilities.ps1"
. "$PSScriptRoot\Common\AuxiliaryEnlistment.ps1"

function Generate-GitOutFiles($config)
{
    $properties = @{}
    foreach ($repo in $config.repos.Values)
    {
        $properties[$repo.Name + "Path"] = $repo.LocalRoot
    }

    Create-MsbuildPropsFile (Get-OutFilePath "git.props")  $properties
    Create-BatchCmdFiles $properties
    Create-BuildIncFiles $properties

    # return the created hash mainly for unit testing purposes
    return $properties
}

function Get-GitRepoCacheFile
{
    return "gitenlistments.txt"
}

#$state is not being used right now
function Invoke-Provider([string]$state)
{
    $config = Load-Config
    if ($config -eq $null)
    {
        return
    }
    
    $repoRoot = "$PSScriptRoot\.."
    $gitModulesFile = [IO.Path]::Combine($repoRoot, ".gitmodules")
    $useGitModules = [System.IO.File]::Exists($gitModulesFile)

    foreach ($repo in $config.repos.Values)
    {
        if ($useGitModules -And $repo.LocalRoot -like "*auxsrc\Localize*")
        {
            $expectedSubmoduleBranch = $repo.Branch # branches.json is the source of truth to which submodule branch we are expecting.
            ."$PSScriptRoot\UpdateGitSubmodule.ps1" -submoduleName "Localize" -expectedBranch $expectedSubmoduleBranch
        }
        else
        {
            ."$PSScriptRoot\MapGit.ps1" -repo $repo.Url -branch $repo.Branch -localPath $repo.LocalRoot -syncTime $repo.SyncTime
        }
    }
    
    Generate-GitOutFiles $config | Out-Null
    $gitEnlistmentStatusFile = Get-EnlistmentStatusFileLocation (Get-GitRepoCacheFile)

    if (!$useGitModules)
    {
        $content = Generate-EnlistmentStatusFileContent $config
        Save-EnlistmentStatusFileContent $gitEnlistmentStatusFile $content
    }
    else
    {
        # For submodules, delete the old git status file.
        # While the submodule rolls out, this will protect against scenarios of (no submodule build) -> (submodule build) -> (no submodule build)
        # resulting in the third build thinking the git repository is up-to-date when it is not because the status file stuck around from the first build.
        if ([System.IO.File]::Exists($gitEnlistmentStatusFile))
        {
            Remove-Item $gitEnlistmentStatusFile
        }
    }

    
    return; #TODO: add return object here when refactor for provider again
}

#$state is not being used right now
function Test-ShouldInvoke([string]$state)
{
    $config = Load-Config
    if ($config -eq $null)
    {
        #if the branch does not have branch.json, it means we have to do nothing
        return $false
    }
    
    $repoRoot = "$PSScriptRoot\.."
    $gitModulesFile = [IO.Path]::Combine($repoRoot, ".gitmodules")
    $useGitModules = [System.IO.File]::Exists($gitModulesFile)
    
    if (!$useGitModules)
    {
        $needUpdates = Test-UpdatesAreNeeded $config (Get-GitRepoCacheFile)
        return $needUpdates
    }
    
    foreach ($repo in $config.repos.Values)
    {
        if ($repo.LocalRoot -like "*auxsrc\Localize*")
        {
            $localizeSubmodule = Parse-Submodule $gitModulesFile "Localize"
            $repoRoot = "$PSScriptRoot\.."
            return Does-Submodule-Require-Update $localizeSubmodule $repoRoot
        }
    }
    
    # If the profile does not have localization enabled, then we do not need updates.
    return $false
}

#$state is not being used right now
function Get-AvailableProfiles()
{
    #not implemented right now
}

# main code. This section of code should be removed when this file is converted to
# a real provider
if ($IsUnderTest)
{
    exit 
}

$ErrorActionPreference = "Stop"

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