# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches

# This script will pull down drops from the VSTS Drop service to a local directory based on a configuration file.
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
    [Parameter(ParameterSetName="execute")]
    [Switch] $BasicAuth,
    [Parameter(ParameterSetName="execute")]
    [Switch] $SkipExportsPrune,
    [Parameter(ParameterSetName="checkForUpdates")]
    [Switch] $CheckIfUpdatesAreNeeded
)

. "$PSScriptRoot\Common\PackageCache.ps1"
. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\FastUpdateCheck.ps1"
. "$PSScriptRoot\Common\AuxiliaryEnlistment.ps1"


function LoadFromPackage-VstsDropAssemblies()
{
    # check for the VSTS package
    $packageName = "Microsoft.DevDiv.Engineering.Shared.Vsts"
    $packageLocation = Get-PackageLocation $packageName

    if ($packageLocation -eq $null)
    {
        Write-Error "A required package '$packageName' could not be found in the cache."
        exit -1;
    }

    $assemblyFiles = @("lib\net45\Engineering.Shared.Vsts.dll",
                       "lib\net45\Engineering.Shared.MinLib.v4.5.dll")

    foreach ($file in $assemblyFiles)
    {
        $fullPath = Join-Path $packageLocation $file
        if (Test-Path $fullPath)
        {
            [Reflection.Assembly]::LoadFile($fullPath) | Out-Null
        }
        else
        {
            throw [IO.FileNotFoundException] "Assembly '$fullPath' does not exist in '$packageLocation'. This assembly is needed to manage the VSTS Drop enlistment."
        }
    }
}

function Generate-VstsDropOutFiles($config)
{
    $properties = @{}
    foreach ($drop in $config.VstsDrops.Values)
    {
        $properties[$drop.Name + "Path"] = $drop.LocalRoot
    }

    Create-MsbuildPropsFile (Get-OutFilePath "vstsDrop.props")  $properties
    Create-BatchCmdFiles $properties
    Create-BuildIncFiles $properties

    # return the created hash mainly for unit testing purposes
    return $properties
}

function Get-VstsDropCacheFile
{
    return "vstsdrops.txt"
}

#$state is not being used right now
function Invoke-Provider([string]$state)
{
    $config = Load-Config
    if ($config -eq $null)
    {
        #if the branch does not have branch.json, it means we have to do nothing
        return
    }

    # Prep the environment for using VSTS Drop object model APIs
    LoadFromPackage-VstsDropAssemblies

    # Delete the files that were sync'ed during the previous execution of the provider
    Remove-PreviousSyncs

    # Sync down the files for the current set of drops
    foreach ($drop in $config.VstsDrops.Values)
    {
        Sync-VstsDrop $drop $config.OfficialBuildTag
    }

    Generate-VstsDropOutFiles $config | Out-Null
    $content = Generate-EnlistmentStatusFileContent $config
    Save-EnlistmentStatusFileContent (Get-EnlistmentStatusFileLocation (Get-VstsDropCacheFile)) $content

    return; #TODO: add return object here when refactor for provider again
}

# This function is responsible for removing the set of files that were sync'ed during the previous session, if any
function Remove-PreviousSyncs()
{
    # Open and parse the cache file and extract the list of LocalRoots that were sync'ed
    $cachedConfigPath = (Get-EnlistmentStatusFileLocation (Get-VstsDropCacheFile))
    if (Test-Path $cachedConfigPath)
    {
        $cachedConfig = Get-Content -Raw $cachedConfigPath | ConvertFrom-Json
        if ($cachedConfig.VstsDrops)
        {
            foreach ($drop in $cachedConfig.VstsDrops | Get-Member -MemberType NoteProperty | %{ $_.Name })
            {
                $localPath = $cachedConfig.VstsDrops.$drop.LocalRoot
                if (Test-Path $localPath)
                {
                    Write-Output "Deleting files from '$localPath'..."
                    Remove-LocalPathWithWarning($localPath)
                }
            }
        }
    }
}

# Note about this function: drop.exe maintains its own cache. When a file is downloaded from VSTS Drop via drop.exe,
# it is first downloaded into a cache on the same drive as LocalRoot and then a hard-link is created between the
# file in the cache and LocalRoot. When the hard link in LocalRoot is removed, the cache is able to detect this.
function Sync-VstsDrop($drop, $officialBuildTag)
{
    Write-TelemetryMetricStart "$($drop.Name) Sync"

    # If the local folder that we're going to sync to somehow still exists, delete it and its contents
    $localPath = $drop.LocalRoot
    if (Test-Path $localPath)
    {
        Write-Output "Deleting files from '$localPath'..."
        Remove-LocalPathWithWarning($localPath)
    }

    # Call drop.exe to download the files from VSTS Drop
    Get-VstsDrop $drop $officialBuildTag

    Write-TelemetryMetricFinish "$($drop.Name) Sync"
}

function Get-VstsDrop($drop, $officialBuildTag)
{
    $dropServiceUrl =  $drop.Url
    $dropName = $drop.DropName
    # Note: drop.exe will create localPath (and all parent folders) if they don't already exist
    $localPath = $drop.LocalRoot
    $folders = $drop.Folders
    $configuration = $drop.Name
    $profile = $drop.ProfileName
    [int]$tmp = $null
    $setting = Get-Setting "Profile-VstsDropCacheSizeOverrideInMB"
    $cacheSizeOverrideInMB = If ([int32]::TryParse($setting, [ref]$tmp)) {$tmp} Else {0} # Default to cache disabled
    $setting = Get-Setting "Profile-VstsDropLocalCachePathOverride"
    $localCachePathOverride = If ([string]::IsNullOrEmpty($setting)) {$null} Else {$setting}

    #TODO: add arguments to control the location and size of the cache
    $VstsDrop = [Engineering.Shared.ArtifactServices.VstsDropFactory]::Create(
        $dropServiceUrl, # dropService
        [Engineering.Shared.ArtifactServices.VstsDropAuthentication]::AAD, # authentication
        $null, # personalAccessToken
        $cacheSizeOverrideInMB, # cacheSizeInMB
        $localCachePathOverride, # cachePath
        $null, # logHandler
        $null, # dropExeUri
        $null, # timeout
        5, # numberOfRetries
        [System.TimeSpan]::FromSeconds(5) # retryDelay
    )

    if ($BasicAuth)
    {
        $VstsDrop.Authentication = [Engineering.Shared.ArtifactServices.VstsDropAuthentication]::Basic
    }

    Write-Output "Downloading VSTS Drop '$dropName' for '$configuration'. This may take a few minutes..."
    Write-Telemetry "$configuration Profile" $profile

    # We want telemetry on the folders being synced because they can be manipulated by users (i.e. exports partitions)
    foreach ($folder in $folders)
    {
        Write-TelemetryList "$configuration Folders" $folder
    }

    Write-TelemetryDiskFreeBefore $configuration $localPath
    try
    {
        Write-TelemetryMetricStart "$configuration Download"
        $duration = Measure-Command {
            # Download $folders from VSTS Drop $dropName to path $localPath
            $VstsDrop.Get($dropName, $localPath, $folders)
        }
        if (!$IsUnderTest)
        {
            Write-Host "Total execution time for '$configuration' download: $duration"

            # Write the value of OptimizationData to f:\dd\.settings\buildlabel.json first.
            # Then, in the later stage of timebuild, this value would be written to the git tag
            if ($configuration -eq 'OptimizationData')
            {
                $buildLabelJsonFile = Join-Path (Get-SourceRoot) ".settings\buildlabel.json"
                if (Test-Path $buildLabelJsonFile)
                {
                    $json = ConvertFrom-Json -InputObject (Get-Content -Raw $buildLabelJsonFile)
                    $json | Add-Member -Name "optimizationData" -value $dropName -MemberType NoteProperty -Force
                    $json | ConvertTo-Json | Set-Content $buildLabelJsonFile
                }
            }
        }
        Write-TelemetryMetricFinish "$configuration Download"

        if (($configuration -split "-")[0] -eq "ExportsCache")
        {
            if ($officialBuildTag -ne $null)
            {
                Remove-PartitionsModifiedFromCacheBaseline $localPath $officialBuildTag
            }

            Populate-TypeScriptApis $localPath
        }
    }
    finally
    {
        # Even if drop download fails, record the disk usage telemetry
        Write-TelemetryDiskFreeAfter $configuration $localPath

        if (($configuration -split "-")[0] -eq "ExportsCache")
        {
            if (!(Test-Path $localPath))
            {
                # Let the user know that their ExportsCache did not get populated
                Write-Output "Could not retrieve contents of VSTS Drop '$dropName'."
            }
        }
    }
}

function Remove-PartitionsModifiedFromCacheBaseline($cacheRoot, $officialBuildTag)
{
    $partitionsProjFile = Join-Path (Join-Path (Get-SourceRoot) "src") "partitions.proj"
    if (Test-Path $partitionsProjFile)
    {
        # Only compute the partitions to cleanup once and save the result in a script-wide variable.
        # If you have multiple flavor/architectures spread across several drops, this will only be
        # computed the first time and then reused on subsequent drops since it is expensive to compute.
        if ($script:cachePartitionsToClean -eq $null)
        {
            Write-Output "Checking for invalidated cache entries..."
            $partitions = @{}

            $duration = Measure-Command {
                [xml]$partitionsProjContent = Get-Content $partitionsProjFile
                $partitionFiles = $partitionsProjContent.Project.ItemGroup.PartitionFile.Include
                foreach ($partitionFile in $partitionFiles)
                {
                    $partitionDir = Join-Path "src" (Split-Path $partitionFile)
                    $partitionFile = Join-Path (Get-SourceRoot) (Join-Path $partitionDir "partition.settings.targets")
                    if (Test-Path $partitionFile)
                    {
                        [xml]$partitionContent = Get-Content $partitionFile
                        $partitionName = $partitionContent.Project.PropertyGroup.PartitionName
                        if ($partitionName.GetType() -eq [Object[]])
                        {
                            # Some partitions.settings.targets files have the partition name listed twice (such as env).
                            # These should be fixed up, but we should still account for that here if they are duplicated,
                            # since it's valid in msbuild to have the same property defined more than once.
                            $partitionName = $partitionName[0]
                        }

                        # Add the partition while replacing backslashes with forward slashes since git outputs paths with forward slashes
                        $partitions[$partitionName] = $partitionDir -replace '\\','/'
                    }
                }

                # Sort partition directories by the path in descending order so that subdirectories are checked before the parent directory.
                # This is needed so that nested partitions are found correctly.
                $partitions = $partitions.GetEnumerator() | Sort-Object Value -Descending

                # Get all changed files between a tag and the current HEAD
                [array]$files = git log --name-only --no-merges --pretty=format: "$officialBuildTag..HEAD"

                # Get all unstaged changes (modified/deleted/untracked) except those that are ignored
                $files += git ls-files --others --modified --deleted --exclude-standard --full-name

                # Get all staged changes that haven't been committed yet
                $files += git diff --name-only --cached

                $files = $files | Sort-Object -Unique

                Write-Verbose "$($files.Length) files have been changed from the cache baseline"
                $script:cachePartitionsToClean = @{}
                foreach ($file in $files)
                {
                    foreach ($partition in $partitions)
                    {
                        if ($file.StartsWith($partition.Value, "OrdinalIgnoreCase"))
                        {
                            $script:cachePartitionsToClean[$partition.Name] = $true
                            break
                        }
                    }
                }
            }

            Write-Output "$($script:cachePartitionsToClean.Count) partitions have stale exports cache"
            Write-Output "Done. $duration"
        }

        if ($SkipExportsPrune)
        {
            Write-Output "Skipping check for files changed since cache baseline"
            return
        }

        foreach ($partition in $script:cachePartitionsToClean.Keys)
        {
            $partitionCacheFolder = Join-Path (Join-Path $cacheRoot "Exports") $partition
            if (Test-Path $partitionCacheFolder)
            {
                Write-Output "Removing partition '$partition' from '$partitionCacheFolder'..."
                Remove-LocalPathWithWarning($partitionCacheFolder)
            }
        }
    }
}

function Remove-LocalPathWithWarning($localPath)
{
    try
    {
        [System.IO.Directory]::Delete($localPath, $true)
    }
    catch
    {
        if (Test-Path $localPath)
        {
            # When the local folder still exists, the drop will not be able to populate with new ExportsCache content. Let the user know.
            Write-Output "Could not delete contents of '$localPath'. Files may be locked by another process. Correct and retry the operation."
        }
        throw
    }
}

function Convert-ExportsPathToTypescriptApisPath ($cacheRoot, $source)
{
    # Change something like d:\git\vs\out\cache\x86chk\Exports\bptoob\Daytona.1.00\inc\plugin.js
    # into bptoob\inc\plugin.js

    $subPath = $source.Substring($cacheRoot.Length)
    $exportsFolder = "\Exports\"
    $exportsRootLocation = $subPath.IndexOf($exportsFolder, [StringComparison]::OrdinalIgnoreCase)

    if ($exportsRootLocation -eq -1)
    {
        throw "Exports file '$source' does not appear to be under an 'Exports' subdirectory"
    }

    $subPath = $subPath.Substring($exportsRootLocation + $exportsFolder.Length) -split "\\"

    if ($subPath.Length -lt 3)
    {
        throw "Exports file '$source' does not exist under the expected folder structure"
    }

    $subPath = ($subPath[0..0] + $subPath[2..($subPath.Length)]) -join "\"

    return $subPath
}

# Given an exports cache which has been downloaded, search for all *.typescriptapis files and populate the
# out\TypeScriptApis folder, overwriting any files which were there previously.
function Populate-TypeScriptApis($cacheRoot)
{
    $typeScriptApisRoot = Join-Path $env:BaseOutDir "TypeScriptApis"

    $files = Get-ChildItem -File -Recurse -Path $cacheRoot *.typescriptapis
    foreach ($file in $files)
    {
        # Trim off the .typescriptapis extension
        $source = Join-Path (Split-Path $file.FullName) $file.BaseName

        # Convert the path to the proper destination path format
        $subPath = Convert-ExportsPathToTypescriptApisPath $cacheRoot $source
        $destination = Join-Path $typeScriptApisRoot $subPath

        # Perform the copy. Always overwrite any existing files.
        New-Item -ItemType directory (Split-Path $destination) -Force | Out-Null
        Copy-Item $source $destination -Force
    }
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

    $needUpdates = Test-UpdatesAreNeeded $config (Get-VstsDropCacheFile)
    return $needUpdates
}

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
