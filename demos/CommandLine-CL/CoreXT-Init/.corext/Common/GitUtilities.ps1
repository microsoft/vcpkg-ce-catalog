# Parses the .gitmodules file to extract the information about the specified submodule.
# Returns an object with {Name, Branch, Path, Url} properties corresponding to the .gitmodules entries for the submodule.
function Parse-Submodule($gitModulesFile, $submoduleName)
{
    $submodule = @{}
    $gitModulesContent = [IO.File]::ReadAllLines($gitModulesFile)
    $foundSubmodule = $false
    
    foreach ($line in $gitModulesContent)
    {
        $submoduleMatch = [Regex]::Match($line, '\[submodule "(.*)"\]')
        if ($submoduleMatch.Success -And $foundSubmodule)
        {
            # We are done parsing the submodule that was specified, so break.
            break
        }
        
        if ($submoduleMatch.Success -And !$foundSubmodule)
        {
            $parsedSubmoduleName = $submoduleMatch.Groups[1].Value
            if ($parsedSubmoduleName -eq $submoduleName)
            {
                # We have found the specified submodule.
                $foundSubmodule = $true
                $submodule.Name = $parsedSubmoduleName
                continue
            }
        }
        
        # Get the submodule path if not yet parsed.
        if (!$submodule.Path -And $foundSubmodule)
        {
            $pathMatch = [Regex]::Match($line, "path = (.*)")
            if ($pathMatch.Success)
            {
                $submodule.Path = $pathMatch.Groups[1].Value
            }
            continue
        }
        
        # Get the submodule url if not yet parsed.
        if (!$submodule.Url -And $foundSubmodule)
        {
            $urlMatch = [Regex]::Match($line, "url = (.*)")
            if ($urlMatch.Success)
            {
                $submodule.Url = $urlMatch.Groups[1].Value
            }
            continue
        }
        
        # Get the submodule branch if not yet parsed.
        if (!$submodule.Branch -And $foundSubmodule)
        {
            $branchMatch = [Regex]::Match($line, "branch = (.*)")
            if ($branchMatch.Success)
            {
                $submodule.Branch = $branchMatch.Groups[1].Value
            }
            continue
        }      
    }
    
    if (!$submodule.Name)
    {
        throw "Could not find submodule with name '$submoduleName'"
    }
    
    if (!$submodule.Path)
    {
        throw "Submodule '$submoduleName' has no path specified in .gitmodules"
    }
 
    if (!$submodule.Branch)
    {
        throw "Submodule '$submoduleName' has no branch specified in .gitmodules"
    }
    
    return $submodule
}

# Tests if a submodule is not on the correct commit
# If the submodule is uninitialized, return true.
# Expects a submodule object parsed with Parse-Submodule.
function Does-Submodule-Require-Update ($submodule, $repoRoot)
{
    $command = "$(Get-GitExePath) -C $repoRoot submodule status -- $($submodule.Path)"
    $statusOutput = (Execute-Command $command)
    # Starting with a '-' character indicates the submodule is not initialized.
    # Starting with a '+' character indicates the currently checked out submodule commit does not match the SHA-1 found in the index of the parent repo.
    # Starting with a 'U' character indicates the submodule has merge conflicts.
    # Starting with a ' ' means the submodule is up to date.
    return $statusOutput.StartsWith("+") -Or $statusOutput.StartsWith("-")
}

function Get-GitExePath
{
    if($CloudBuild)
    {
        Write-Verbose "Using Git from checked in package"
        $cachedGitPackageLocation = Get-RequiredPackageLocationOrExit "PortableGit.CoreXT"
        return Join-Path (Join-Path $cachedGitPackageLocation "cmd") "git.exe"
    }

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty definition;
    if ($gitCommand -eq $null)
    {
        throw [IO.FileNotFoundException] "Failed to find git.exe. Please ensure %PATH% contains path to git.exe."
    }
    return "`"$gitCommand`"";
}

function Get-CommitIdBeforeTimeStampUsingVSO ($branch, $timeStamp, $vsoToolsPath, $remoteUrl)
{
    $regex = "https://(.*).visualstudio.com.*"

    if ($remoteUrl -notmatch $regex) 
    {
        throw "Unable to extract account name from remote repository URL '$remoteUrl'"
    }

    # Extract the account name.
    $accountName = $matches[1]

    # Run GetRepositoryId.exe, and grab the last line of output, which is the repository id. 
    # We grab just the last line because there may be extraneous output if a transient exception is caught.
    $getRepositoryIdExe = Join-Path $vsoToolsPath "GetRepositoryId.exe"
    $repositoryIdCommand = "$getRepositoryIdExe /account:$accountName /repository:""$remoteUrl"""
    $repositoryIdOutput = Execute-Command $repositoryIdCommand

    if (@($repositoryIdOutput).Count -eq 1)
    {
        # If there is 1 line of output, it is not an array, and is the repository id.
        $repositoryId = $repositoryIdOutput
    }
    else
    {
        # If there are multiple lines, it is an array, and we want the last line.
        $repositoryId = $repositoryIdOutput[-1]
    }

    # Run GetLastCommit.exe
    $getLastCommitExe = Join-Path $vsoToolsPath "GetLastCommit.exe"
    $lastCommitCommand = "$getLastCommitExe /account:$accountName /repositoryId:$repositoryId /cutoffTime:$timeStamp /branch:$branch /verbose"
    [Array]$lastCommitOutput = Execute-Command $lastCommitCommand

    # Return the last line of output (again: there may be extra output), which is the commit/object id we want.
    return $lastCommitOutput[-1]
}