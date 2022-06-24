# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches

# This script is used to clone a repo if it doesn't exist on specified path, and sync the  branch to a commit Id prior to the syncTime

# Example script parameters:
# $(EnlistRoot)>%PS% .corext\mapgit.ps1 https://devdiv.visualstudio.com/DefaultCollection/VSEng%20Testing/_git/Localize master d:\VS\src\auxsrc\localize D2015/04/24T11:50:00

[CmdletBinding(DefaultParametersetName="execute")]
param (
    [Parameter(Position=0, Mandatory=$true, ParameterSetName="execute")]
    [String] $repo,
    [Parameter(Position=1, Mandatory=$true, ParameterSetName="execute")]
    [String] $branch,
    [Parameter(Position=2, Mandatory=$true, ParameterSetName="execute")]
    [String] $localPath,
    [Parameter(Position=3, Mandatory=$true, ParameterSetName="execute")]
    [String] $syncTime
)

. "$PSScriptRoot\Common\AuxiliaryEnlistment.ps1"
. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\GitUtilities.ps1"
. "$PSScriptRoot\Common\PackageCache.ps1"

# Repositories cloned/updated during this script could be a raw git repository, or a git submodule.
#
# The .git directory for submodule by default exist in the .git/modules of the main repository.
# For example, if auxsrc/Localize is a submodule representing the Localize repostitory,
# then assuming the Localize repostitory was NOT cloned into f:\dd\auxsrc\Localize previously, than
# its git directory would be f:\dd\.git\modules\Localize. 
#
# However, if the Localize directory existed at auxsrc\Localize prior to the submodule being created, then the 
# .git directory at f:\dd\auxsrc\Localize\.git would continue to be used for the submodule. 
#
# In either case, just run git rev-parse --git-dir from the local path to discover the .git directory location.
function Get-GitDir-LocalPath($localPath)
{
    $oldPath = (Get-Location).Path
    cd $localPath
    Try
    {
        $command = "$(Get-GitExePath) rev-parse --git-dir"
        $gitDir = Execute-Command $command
        if ($gitDir -eq ".git")
        {
            $current = (Get-Location).Path
            return [IO.Path]::Combine($current, ".git")
        }

        return $gitDir
    }
    Finally
    {
        cd $oldPath
    }
}

function Get-GitExeCommand-LocalPath($localPath)
{
    $localGitDir = Get-GitDir-LocalPath($localPath)
    return "$(Get-GitExePath) --git-dir=$localGitDir --work-tree=$localPath "
}

function Get-CurrentRepoUrl-LocalPath($localPath)
{
    $localGitExeCommand = (Get-GitExeCommand-LocalPath $localPath)
    $command = "$localGitExeCommand config --get remote.origin.url"
    return Execute-Command $command
}

function Clone-Repository($repo, $branch, $localPath)
{
    if (Test-Path $localPath)
    {
        $currentRepoUrl = Get-CurrentRepoUrl-LocalPath $localPath
   
        Write-Host "Current repo URL: $currentRepoUrl"
        if ($currentRepoUrl -eq $repo)
        {
            return;
        }
        Write-Host "Removing current repo at: $localPath"
        Remove-Item $localPath -Force -Recurse
    }
    
    Write-Host "Cloning new repo: '$repo' at: '$localPath'"
    $gitExe = Get-GitExePath
    $completed = $false;
    $retryCnt = 0;
    while(-not $completed)
    {
        $retryCnt++;
        $p = Start-Process $gitExe "clone -q -b $branch $repo $localPath" -Wait -PassThru

        if($p.ExitCode -eq 0)
        {
            $completed = $true;
        }
        elseif ($retryCnt -lt $retries)
        {
            Write-Host "Failed to run command: Start-Process $gitExe clone -q -b $branch $repo $localPath -Wait -PassThru. Retrying in $millisecondsDelay ms"
            Start-Sleep -Milliseconds $millisecondsDelay
        }
        else
        {
             Write-Host "Failed to run command: Start-Process $gitExe clone -q -b $branch $repo $localPath -Wait -PassThru."
             $completed = $true;
        }
     }
}

function Checkout-Branch
{
    $command = "$script:LocalPathGitExeCommand checkout $branch"
    Execute-Command $command
}

function Fetch-Branch($option)
{
    $command = "$script:LocalPathGitExeCommand fetch $option"
    Execute-Command $command
}

function Get-CurrentBranch
{
    $command = "$script:LocalPathGitExeCommand rev-parse --abbrev-ref HEAD"
    return Execute-Command $command
}

function Pull-CurrentBranch
{
    $command = "$script:LocalPathGitExeCommand pull"
    Execute-Command $command
}

function Get-CurrentCommitId
{
    $command = "$script:LocalPathGitExeCommand rev-parse HEAD"
    return Execute-Command $command
}

function SyncTo-CommitId ($commitId)
{
    $command = "$script:LocalPathGitExeCommand reset --hard $commitId"
    Execute-Command $command
}

function Pull-Branch ($branch)
{
    # Check out the desired branch if it is not the current branch in the repo (under $localPath)
    $currentBranch = Get-CurrentBranch
    Write-Output "currentBranch: $currentBranch"
    SyncTo-CommitId "HEAD"
    if($currentBranch -ne $branch)
    {
        Write-Output "Run git fetch to ensure the target branch is visible to the local git workspace"
        Fetch-Branch "--prune"
        Write-Output "Checkout the branch $branch since it is not current"
        Checkout-Branch $branch
    }

    Pull-CurrentBranch
}

function SyncTo-CommitIdPriorToSyncTime ($branch, $syncTime, $remoteUrl)
{
    $vsoToolsPath = Get-RequiredPackageLocationOrExit "VS.Tools.VSORestAPI"
    $syncTimeCommitId = Get-CommitIdBeforeTimeStampUsingVSO $branch $syncTime $vsoToolsPath $remoteUrl
    Write-Output "syncTimeCommitIdStr= $syncTimeCommitId"

    $currentCommitId = Get-CurrentCommitId
    Write-Output "currentCommitId= $currentCommitId"

    if ($syncTimeCommitId -ne $currentCommitId)
    {
        SyncTo-CommitId $syncTimeCommitId
    }
}

if ($IsUnderTest)
{
    $millisecondsDelay = 10
    $retries = 3
    exit
}

Set-Environment

Clone-Repository $repo $branch $localPath

# Repository at the local path must now exist.
$script:LocalPathGitExeCommand = Get-GitExeCommand-LocalPath $localPath

Pull-Branch $branch

$command = "$script:LocalPathGitExeCommand config --get remote.origin.url"
$repoUrl = (Execute-Command $command)
SyncTo-CommitIdPriorToSyncTime $branch $syncTime $repoUrl
