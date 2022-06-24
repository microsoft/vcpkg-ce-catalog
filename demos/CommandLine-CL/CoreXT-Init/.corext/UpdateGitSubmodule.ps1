# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches
#
# This script is used to synchronize a git submodule that exists in the repository.
# If no sync time is provided, the submodule is synchronized to the commit specified in the main repository
# If a sync time is provided, the submodule is synchronized to the first commit prior to the sync time of the branch specified in .gitmodules
#
# Example script parameters:
# $(EnlistRoot)>%PS% .corext\UpdateGitSubmodules.ps1 -submoduleName Localize -expectedBranch rel/d15rel
# $(EnlistRoot)>%PS% .corext\UpdateGitSubmodules.ps1 -submoduleName Localize -expectedBranch rel/d15rel -syncTime D2015/04/24T11:50:00

[CmdletBinding(DefaultParametersetName="execute")]
param (
    [Parameter(Position=0, Mandatory=$true, ParameterSetName="execute")]
    [String] $submoduleName,
    [Parameter(Position=1, Mandatory=$true, ParameterSetName="execute")]
    [String] $expectedBranch,
    [Parameter(Position=2, Mandatory=$false, ParameterSetName="execute")]
    [String] $syncTime
)

. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\GitUtilities.ps1"
. "$PSScriptRoot\Common\PackageCache.ps1"

function Format-Submodule ($submodule)
{
    return "$($submodule.Name) $($submodule.Path)"
}

# Gets the current commit the submodule is on by inspecting the submodule repository.
# Note that we can't use --work-tree because the submodule has no .git directory.
function Get-Submodule-Current-Commit ($submodule)
{
    Execute-Command "$(Get-GitExePath) -C $($submodule.Path) rev-parse HEAD"
}

# Inits the submodule.
function Submodule-Init ($submodule)
{
    $command = "$(Get-GitExePath) submodule init -- $($submodule.Path)"
    Execute-Command $command
}

function Submodule-Update ($submodule)
{
    Write-Host "Update submodule $(Format-Submodule $submodule)..."
    $command = "$(Get-GitExePath) submodule update -f -- $($submodule.Path)"
    Execute-Command $command
}

# Updates the submodule to the latest.
function Submodule-Update-Latest ($submodule)
{
    Write-Host "Updating submodule $(Format-Submodule $submodule) to latest..."
    $command = "$(Get-GitExePath) submodule update --remote -- $($submodule.Path)"
    Execute-Command $command
}

# Updates the submodule to the specified commit by entering the submodule and doing a hard reset to the commit (after fetching)
# Note that we can't use --work-tree because the submodule has no .git directory.
function Submodule-Update-To-Commit ($submodule, $commitId)
{
    Write-Host "Updating submodule $(Format-Submodule $submodule) to commitId $commitId..."

    # Create a detatched head state (if not already a detached head).
    # We want this so if the next build comes along and it does not use a submodule, we don't corrupt any of the branch pointers
    # For example, if we instead did a git reset --hard $commitId, would could end up with merge conflicts in the next build.
    Execute-Command "$(Get-GitExePath) -C $($submodule.Path) checkout -f --detach $commitId"
}

$oldPath = (Get-Location).Path
# Run commands from the repository root.
cd "$PSScriptRoot\.."
$repoRoot = (Get-Location).Path

Try
{
    $gitModulesFile = [IO.Path]::Combine($repoRoot, ".gitmodules")
    $submodule = Parse-Submodule $gitModulesFile $submoduleName

    if ($submodule.Branch -ne $expectedBranch)
    {
        throw "git submodule '$($submodule.Name)' has branch '$($submodule.Branch)' listed in .gitmodules, but .corext/Configs/branches.json indicates this should be branch '$expectedBranch'"
    }

    Submodule-Init $submodule

    if (!$syncTime)
    {
        # No sync time: sync to commit specified in main repository.
        Submodule-Update $submodule
        return
    }

    # Get the latest submodule bits. This is a bit like doing a git pull, even though we may need to checkout to a previous commit below.
    Submodule-Update-Latest $submodule

    $currentCommit = Get-Submodule-Current-Commit $submodule

    # Get the commit the submodule should be on.
    $vsoToolsPath = Get-RequiredPackageLocationOrExit "VS.Tools.VSORestAPI"
    $syncTimeCommitId = Get-CommitIdBeforeTimeStampUsingVSO $submodule.Branch $syncTime $vsoToolsPath $submodule.Url

    Write-Host "Submodule $(Format-Submodule $submodule) is on commit $currentCommit"
    Write-Host "Commit prior to $syncTime is $syncTimeCommitId"

    if ($currentCommit -ne $syncTimeCommitId)
    {
        Submodule-Update-To-Commit $submodule $syncTimeCommitId
    }
}
Finally
{
    cd $oldPath
}

