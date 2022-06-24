# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches

# This script is used to manage a hybrid enlistment with some folders living in TFS (TFVC).
# The script will create a new workspace if necessary and then map in folders based on
# a configuration file. It will then sync the files to some point in time (default to tip).

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
    [Switch] $Scorch,
    [Parameter(ParameterSetName="checkForUpdates")]
    [Switch] $CheckIfUpdatesAreNeeded
)

. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\FastUpdateCheck.ps1"
. "$PSScriptRoot\Common\PackageCache.ps1"
. "$PSScriptRoot\Common\Telemetry.ps1"
. "$PSScriptRoot\Common\AuxiliaryEnlistment.ps1"

function Get-DependentPackagePath()
{
    # check for the newer v4.6 managed tools package, default to v4.5 if not found
    $packageNamePrefix = "VS.Tools.X86.Managed.V"
    $packageVer45 = "4_5"
    $packageVer46 = "4_6"
    $packageLocation = Get-PackageLocation $packageNamePrefix$packageVer46
    if ($packageLocation -eq $null)
    {
        $packageLocation = Get-PackageLocation $packageNamePrefix$packageVer45
        if ($packageLocation -eq $null)
        {
            Write-Error "A required managed tools package '$packageNamePrefix$packageVer46'or'$packageNamePrefix$packageVer45' could not be found in the cache."
            exit -1;
        }
    }
    return $packageLocation
}

function LoadFromPackage-TfsAssemblies()
{
    $cachedPackageLocation = Get-DependentPackagePath
    $assemblyFiles = @("tf14\Microsoft.TeamFoundation.Client.dll",
                       "tf14\Microsoft.TeamFoundation.Common.dll",
                       "tf14\Microsoft.TeamFoundation.VersionControl.Client.dll",
                       "tf14\Microsoft.TeamFoundation.VersionControl.Common.dll",
                       "tf14\Microsoft.TeamFoundation.WorkItemTracking.Client.dll",
                       "tf14\Microsoft.VisualStudio.Services.Client.dll",
                       "tf14\Microsoft.VisualStudio.Services.Common.dll",
                       "tf14\Microsoft.VisualStudio.Services.WebApi.dll")

    foreach ($file in $assemblyFiles)
    {
        $fullPath = Join-Path $cachedPackageLocation $file
        if (Test-Path $fullPath)
        {
            [Reflection.Assembly]::LoadFile($fullPath) | Out-Null
        }
        else
        {
            throw [IO.FileNotFoundException] "Assembly '$fullPath' does not exist in '$cachedPackageLocation'. This assembly is needed to manage the TFS enlistment."
        }
    }
}

function Get-WorkspaceFromPath($path, $versionControlServer)
{
    # Try the fast check first to see if this path is directly within a workspace
    $workspace = $versionControlServer.TryGetWorkspace($path)

    if ($workspace -eq $null)
    {
        # The fast check did not find any hits, so try the slower method.
        # This path is not mapped in a workspace, but there might be other workspaces
        # that map a subdirectory of this path. Perform the more expensive check of looping
        # through all other workspaces on this machine to check for any mapped subdirectories
        $allWorkspaces = $versionControlServer.QueryWorkspaces(
            # PS is weird -- $null is not the same as .NET null, so to pass null to .NET methods,
            # you must use [System.Management.Automation.Language.NullString]::Value instead...
            [System.Management.Automation.Language.NullString]::Value, # workspaceName
            [System.Management.Automation.Language.NullString]::Value, # workspaceOwner
            $env:COMPUTERNAME
        )

        foreach ($computerWorkspace in $allWorkspaces)
        {
            foreach ($folder in $computerWorkspace.Folders | ?{ $_.LocalItem -ne $null })
            {
                if ($folder.LocalItem.StartsWith($path.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, "OrdinalIgnoreCase"))
                {
                    return $computerWorkspace
                }
            }
        }
    }

    return $workspace
}

function Find-ExistingWorkspace($profileMappings, $versionControlServer)
{
    # Check all mapping local paths and ensure that we do have have mappings that span two existing workspaces
    $existingWorkspace = $null
    foreach ($mapping in $profileMappings)
    {
        $mappedWorkspace = Get-WorkspaceFromPath $mapping.LocalPath $versionControlServer

        if ($mappedWorkspace -ne $null)
        {
            if ($existingWorkspace -eq $null)
            {
                $existingWorkspace = $mappedWorkspace
            } elseif ($existingWorkspace -ne $mappedWorkspace)
            {
                throw "Some, but not all, of your local workspace mappings already exist in another workspace. This is not a supported scenario."
            }
        }
    }

    return $existingWorkspace
}

function Create-Workspace($namePrefix, $mappings, $versionControlServer)
{
    $workspaceName = $namePrefix + "-" + (Get-Date -format yyyyMMdd.HHmmss) + "-" + $env:COMPUTERNAME
    $params = New-Object Microsoft.TeamFoundation.VersionControl.Client.CreateWorkspaceParameters($workspaceName)
    $params.Comment = "Auto-generated workspace for hybrid TFS/Git enlistments"
    $params.Folders = New-Object Microsoft.TeamFoundation.VersionControl.Client.WorkingFolder[]($mappings.length)

    for ($i = 0; $i -lt $mappings.length; $i++)
    {
        $local = $mappings[$i].LocalPath
        $server = $mappings[$i].ServerPath

        $recursion = "Full"
        if ($server.EndsWith('*'))
        {
            # You cannot create a working folder with a wildcard server path. You should instead
            # create the server path for the directory above and set the depth to "OneLevel"
            $server = $server.TrimEnd('*').TrimEnd('/')
            $recursion = "OneLevel"
        }

        $params.Folders[$i] = New-Object Microsoft.TeamFoundation.VersionControl.Client.WorkingFolder($server, $local, "Map", $recursion)
    }

    return $versionControlServer.CreateWorkspace($params)
}

function Scorch-Workspace($workspace)
{
    $packageRootPath = Get-DependentPackagePath
    $tfpt = Join-Path $packageRootPath "tfpt12_.exe"

    # Take all local paths that are not cloaked in the workspace and format them properly (wrapped in quotes)
    # for command line execution
    $fileSpecs = ($workspace.Folders.LocalItem | ?{ $_ -ne $null } | %{"`"$_`""}) -join " "
    Invoke-Expression "& `"$tfpt`" scorch /noprompt /r $fileSpecs"

    if ($LastExitCode -gt 1)
    {
        # 0 is success and 1 is partial success (usually means nothing to do). Anything else we should
        # consider an error.
        throw "Scorch failed with exit code $LastExitCode"
    }
}

# Given a server path that we plan on mapping in the workspace, remove any mappings of child paths
# that already exist in the workspace so that we can successfully remap this full folder.
function Remove-ChildFolders ($mapping, $workspace)
{
    # If there are any child folders mapped/cloaked already, we should remove them
    foreach ($folder in $workspace.Folders)
    {
        if ($folder.ServerItem.StartsWith($mapping.ServerPath.TrimEnd('*').TrimEnd('/') + '/', "OrdinalIgnoreCase") -or
           ($folder.ServerItem -eq $mapping.ServerPath -and $folder.Depth -eq 'OneLevel'))
        {
            # There is an existing mapping for a child of the folder we want to map to
            # a new location, or we have a non-recursive mapping that is now recursive.
            # In order to fully map the parent folder to the new location,
            # we need to remove the existing child/non-recursive mapping.
            Write-Output "Removing old mapping $($folder.ServerItem)"
            try
            {
                $workspace.DeleteMapping($folder)
            }
            catch [Microsoft.TeamFoundation.VersionControl.Client.ItemNotMappedException]
            {
                # This mapping might have been removed somewhere higher up the tree. No problem, since
                # we wanted to get rid of it anyway
            }
        }
    }
}

# Add/remap server folders based on the configuration.
# If there are any local folders which were previously mapped that
# are no longer mapped after this operation, they will be deleted.
function Update-Mappings($workspace, $mappings)
{
    $foldersToCleanup = @()

    # Sort the mappings in ascending order by the server path so that
    # when we are cleaning up existing mappings we go from top-down through
    # the tree.
    foreach ($mapping in ($mappings | Sort-Object ServerPath))
    {
        $newLocalMapping = $mapping.LocalPath

        try
        {
            $currentMapping = $workspace.GetWorkingFolderForServerItem($mapping.ServerPath)
        }
        catch
        {
            # If this is a new mapping, it will not be present in the workspace yet, so GetWorkingFolderForServerItem
            # will throw because the workspace can't get the local path of the mapping. In this case,
            # $oldLocalMapping will equal $null, which we check for below.
        }

        if ($currentMapping -eq $null -or $currentMapping.LocalItem -eq $null -or $currentMapping.LocalItem.TrimEnd('*').TrimEnd('\') -ne $newLocalMapping)
        {
            Write-Output "Updating mapping $($mapping.ServerPath) -> $newLocalMapping"

            Remove-ChildFolders $mapping $workspace
            $workspace.Map($mapping.ServerPath, $newLocalMapping)

            if ($currentMapping -ne $null -and $currentMapping.LocalItem -ne $null -and $currentMapping.Depth -ne 'None')
            {
                $foldersToCleanup += $currentMapping.LocalItem.TrimEnd('*').TrimEnd('\')
            }
        }
        elseif ($mapping.ServerPath -ne $currentMapping.ServerItem -or
               (-not $mapping.ServerPath.EndsWith('*') -and $currentMapping.Depth -ne 'Full')
               )
        {
            # If the old local path matches the new local path, there still could be a change in the recursive value of the mapping.
            # For instance, we currently have it mapped non-recursive, but we want to make it a recursive mapping, or vice-versa.
            Write-Output "Updating mapping $($mapping.ServerPath) -> $newLocalMapping"

            Remove-ChildFolders $mapping $workspace
            $workspace.Map($mapping.ServerPath, $newLocalMapping)
        }
    }

    if ($Scorch)
    {
        # We have just finished adjusting the mappings for the workspace, so before we do any syncing
        # (both to potentially remove stale workspace folders and to sync the workspace for real), we
        # want to scorch the workspace so that it is in a good state for the sync.
        Scorch-Workspace $workspace
    }

    # Sync and delete all of the local folders which were previously mapped but have now changed.
    # This should clean them up from the workspace and from disk.
    # Example: $/foo was mapped to \foo, but it is now mapped to \bar. \foo needs to be cleaned up.
    # Note: Currently, if the change in mappings cause a new workspace to be created, the old workspace
    # will NOT be cleaned up. We only operate on the current workspace without searching for other
    # workspaces which might contain the stale folders.
    if ($foldersToCleanup.length -gt 0)
    {
        $uniq = [string[]]($foldersToCleanup | select -uniq)

        Write-Output "Refreshing stale folders:"
        foreach ($folder in $uniq)
        {
            Write-Output $folder
        }

        Sync-WorkspaceFolders $workspace $uniq
    }
}

function Sync-WorkspaceFolders($workspace, $localFolders, $syncTime, [string[]]$syncVersions)
{
    $versionSpec = [Microsoft.TeamFoundation.VersionControl.Client.VersionSpec]::Latest

    if (![string]::IsNullOrWhiteSpace($syncTime))
        {
        # $null on ParseSingleSpec is for the user account
        $versionSpec = [Microsoft.TeamFoundation.VersionControl.Client.VersionSpec]::ParseSingleSpec($syncTime, $null)
    }

    # Split the syncing into two parts: ones which should be force synced (if the path doesn't exist), and ones
    # which should be synced regularly (incremental in the workspace that TFS tracks). This force sync logic is
    # added as a heuristic to determine if someone previously deleted the entire workspace folder (such as during
    # a "clean repo" build) and did not tell TFS to delete the workspace. We will try to recover gracefully for
    # this specific use case.
    $pathsToForceSync = $localFolders | ?{ !(Test-Path $_) }
    $pathsToIncrementalSync = $localFolders | ?{ Test-Path $_ }

    # Sync to the proper sync time
    if ($pathsToForceSync.count -gt 0)
    {
        $workspace.Get($pathsToForceSync,
            $versionSpec,
            [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::Full,
            [Microsoft.TeamFoundation.VersionControl.Client.GetOptions] "GetAll, Overwrite") | Process-GetResults
    }

    if ($pathsToIncrementalSync.count -gt 0)
    {
        $workspace.Get($pathsToIncrementalSync,
            $versionSpec,
            [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::Full,
            [Microsoft.TeamFoundation.VersionControl.Client.GetOptions]::Overwrite) | Process-GetResults
    }

    # This is to avoid the potential product issue as in https://devdiv.visualstudio.com/DefaultCollection/DevDiv/_workitems?id=359815&_a=edit
    # It looks the "GetAll" option would bypass the check if there is file path over 259 chars
    if ($localFolders.count -gt 0)
    {
        Write-Host "Sync again in case there is invalid long path"
        $workspace.Get($localFolders,
            $versionSpec,
            [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::Full,
            [Microsoft.TeamFoundation.VersionControl.Client.GetOptions]::None) | Process-GetResults
    }

    # Sync individual changesets
    foreach ($changesetVersion in $syncVersions)
    {
        try
        {
            $changeset = $workspace.VersionControlServer.GetChangeset([int]$changesetVersion)
        }
        catch
        {
            Write-Warning("Failed to find the changeset: $changesetVersion")
            continue
        }

        # Not using an array here because we could be doing lots of adds, and we need dynamic resizing without copying over and over
        $itemsToSync = New-Object System.Collections.Generic.List[System.String]
        foreach ($change in $changeset.Changes)
        {
            if ($workspace.IsServerPathMapped($change.Item.ServerItem))
            {
                # The path is mapped in the overall workspace, but we need to be sure that it is also mapped under
                # the subset of $localFolders that we are syncing. We don't want to sync files that are part of this
                # changeset which fall outside of $localFolders

                foreach ($folder in $localFolders)
                {
                    $serverFolder = $workspace.GetServerItemForLocalItem($folder)
                    if ($change.Item.ServerItem.StartsWith($serverFolder.TrimEnd('*'), 'OrdinalIgnoreCase'))
                    {
                        $itemsToSync.Add($change.Item.ServerItem)
                        break
                    }
                }
            }
        }

        if ($itemsToSync.Count -gt 0)
        {
            Write-Output "Syncing hotfix CS $($changesetVersion): $($itemsToSync.Count) files"
            $workspace.Get($itemsToSync.ToArray(),
                (New-Object Microsoft.TeamFoundation.VersionControl.Client.ChangesetVersionSpec $changeset.ChangesetId),
                [Microsoft.TeamFoundation.VersionControl.Client.RecursionType]::None,
                [Microsoft.TeamFoundation.VersionControl.Client.GetOptions] "GetAll, Overwrite" ) | Process-GetResults
        }
    }
}

function Sync-MappedFolders($existingWorkspace, $workspace)
{
    if ($workspace.SyncPolicy -eq 'MapOnly')
    {
        Write-Output "[$($existingWorkspace.Name)] Sync policy is set to 'MapOnly'; Skipping syncing for this workspace"
        return
    }

    if ($workspace.SyncPolicy -eq 'BuildLabel' -and [string]::IsNullOrWhiteSpace($workspace.SyncTime))
    {
        throw "You must specify a SyncTime when using the 'BuildLabel' sync policy. The tag contents are invalid."
    }

    Write-Output "[$($existingWorkspace.Name)] Syncing mappings to $($workspace.SyncPolicy): $($workspace.SyncTime)"
    foreach ($mapping in $workspace.LocalMappings)
    {
        $server = $mapping.ServerPath
        $local = $mapping.LocalPath
        Write-Output "$server -> $local"
    }

    Write-TelemetryMetricStart "$($workspace.Name) Sync"
    $duration = Measure-Command {
        Sync-WorkspaceFolders $existingWorkspace $workspace.LocalMappings.LocalPath $workspace.SyncTime $workspace.SyncVersions
    }
    Write-Host "Total execution time for $($workspace.Name) sync: $duration"
    Write-TelemetryMetricFinish "$($workspace.Name) Sync"
}

function Get-VersionControlServer($url)
{
    # Instantiate the VCS object that communicates with TFS with retries enabled for 30 seconds per request
    $retryFactory = New-Object Microsoft.TeamFoundation.Client.Channels.TfsHttpRetryChannelFactory([timespan]"00:00:30")
    $defaultCredentials = New-Object Microsoft.TeamFoundation.Client.TfsClientCredentials
    $identityToImpersonate = $null
    $tfs = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection([Uri] $url, $defaultCredentials, $identityToImpersonate, $retryFactory)
    return $tfs.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
}

function Update-LocalCache($versionControlServer)
{
    $workstation = [Microsoft.TeamFoundation.VersionControl.Client.Workstation]::Current
    $ownerName = $versionControlServer.AuthorizedUser
    Write-Output "Updating local TFS cache for user '$ownerName' on workstation '$($workstation.Name)'"
    $workstation.UpdateWorkspaceInfoCache($versionControlServer, $ownerName)
}

function Process-GetResults
{
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline)]
        $getStatus
    )

    Process
    {
        # Check the returned GetStatus object for any conflicts/errors
        $remainingConflicts = $getStatus.NumConflicts - $getStatus.NumResolvedConflicts
        if ($remainingConflicts -gt 0)
        {
            Write-Host -ForegroundColor Yellow "$remainingConflicts unresolved conflict(s) occurred during the Get operation"
        }

        if ($getStatus.NumWarnings -gt 0)
        {
            Write-Host -ForegroundColor Yellow "$($getStatus.NumWarnings) warning(s) occurred during the Get operation"
        }

        if ($getStatus.NumFailures -gt 0)
        {
            foreach ($failure in $getStatus.GetFailures())
            {
                Write-Host -ForegroundColor Red "$($failure.Message)"
            }

            throw "$($getStatus.NumFailures) failure(s) occurred during the Get operation"
        }

        # Also poll the event queue of non-fatal errors to see if there are any other errors not contained in the GetStatus object
        $events = Get-Event -SourceIdentifier "NonFatalErrors" -ErrorAction ignore
        if ($events -ne $null -and $events.Length -gt 0)
        {
            $fatalErrorsEncountered = 0
            foreach ($event in $events)
            {
                # Report failures if they exist, otherwise report the exception
                if ($event.SourceEventArgs.Failure.Message)
                {
                    if ($event.SourceEventArgs.Failure.Message -match "source control proxy .* is not responding")
                    {
                        # Treat proxy errors as warnings
                        Write-Host -ForegroundColor Yellow $event.SourceEventArgs.Failure.Message
                    }
                    else
                    {
                        Write-Host -ForegroundColor Red $event.SourceEventArgs.Failure.Message
                        $fatalErrorsEncountered++
                    }
                }
                else
                {
                    # Treat all other errors as fatal
                    Write-Host -ForegroundColor Red $event.SourceEventArgs.Exception.Message
                    $fatalErrorsEncountered++
                }

                Remove-Event $event.EventIdentifier
            }

            if ($fatalErrorsEncountered -gt 0)
            {
                throw "$fatalErrorsEncountered failure(s) occurred during the Get operation"
            }
        }
    }
}

function Register-Events($versionControlServer)
{
    # Clean up old events that might be lingering from a previous failed invocation in this session
    Unregister-Event "NonFatalErrors" -ErrorAction Ignore
    Remove-Event "NonFatalErrors" -ErrorAction Ignore

    # Catch non-fatal errors from TFS so that we can report them (and potentially re-interpret them as fatal)
    Register-ObjectEvent $versionControlServer "NonFatalError" -SourceIdentifier "NonFatalErrors"

    # Subscribe to all notifications about files that we are downloading so that we can display them to the user.
    # We cannot used the preferred Register-ObjectEvent here due to a PowerShell threading issue: everything in
    # PS runs in a single thread, including the event processing. Since the TFS API forces a blocking get operation,
    # this means that if we use the built in event pipeline, the events will be processed after the Get operation
    # finishes. Background jobs are not ideal for this work either since the loaded TFS API assemblies would not be visible
    # from the new scope. For these reasons, we will set the underlying delegate directly so that the TFS APIs will invoke
    # our handler in real-time as the events occur.
    $gettingEventHandler = {
        # Code for displaying output from the TFS Getting event handler adapted from tf.exe code
        # http://index/#TF/Tfvc/VersionControlCommand.cs,9766f248cf06900d,references
        $shortFileName = [string]$null
        if ($_.TargetLocalItem -ne $null)
        {
            if ($_.TargetLocalItem -eq [Microsoft.TeamFoundation.Common.FileSpec]::GetDirectoryName($_.TargetLocalItem))
            {
                $shortFileName = $_.TargetLocalItem
            }
            else
            {
                $folder = [string]$null
                [Microsoft.TeamFoundation.Common.FileSpec]::Parse($_.TargetLocalItem, [ref]$folder, [ref]$shortFileName);

                if ($script:lastFolderDisplayed -eq $null -or -not ([Microsoft.TeamFoundation.Common.FileSpec]::Equals($script:lastFolderDisplayed, $folder)))
                {
                    if ($script:lastFolderDisplayed -ne $null)
                    {
                        Write-Host ""
                    }

                    Write-Host "$($folder):"
                    $script:lastFolderDisplayed = $folder
                }
            }
        }

        $errorMessage = [string]$null
        $message = $_.GetMessage($shortFileName, [ref]$errorMessage)

        $warningStates = @('Conflict', 'SourceWritable', 'TargetLocalPending', 'TargetWritable',
            'SourceDirectoryNotEmpty', 'TargetIsDirectory', 'UnableToRefresh')
        $normalStates = @('Getting', 'Replacing', 'Deleting')

        switch ($_.Status)
        {
            { $warningStates -contains $_ } { Write-Host -ForegroundColor Yellow $errorMessage }
            { $normalStates -contains $_ } { Write-Host $message }
        }
    }

    $versionControlServer.add_Getting($gettingEventHandler)
    return $gettingEventHandler
}

function Unregister-Events($versionControlServer, $gettingEventHandler)
{
    Unregister-Event -SourceIdentifier "NonFatalErrors" -ErrorAction Ignore
    $versionControlServer.remove_Getting($gettingEventHandler)
}

function Manage-Workspace($workspace)
{
    $profile = $workspace.ProfileName
    $profileMappings = $workspace.LocalMappings

    if ($profileMappings -eq $null)
    {
        throw "Workspace '$($workspace.Name)' does not define a profile called '$profile'."
    }

    if ($profileMappings.count -eq 0)
    {
        # This profile does not have any mappings defined, so we should not create/manipulate this workspace
        return
    }

    Write-Telemetry "$($workspace.Name) Profile" $profile

    # All mappings should exist on the same drive, so grab the first folder for disk usage telemetry
    $localFolder = $profileMappings[0].LocalPath

    Write-TelemetryDiskFreeBefore $workspace.Name $localFolder
    try
    {
        
        Write-TelemetryMetricStart "$($workspace.Name) Mapping"
        $duration = Measure-Command {
            $versionControlServer = Get-VersionControlServer $workspace.CollectionUri
            $gettingEventHandler = Register-Events $versionControlServer
            $existingWorkspace = Find-ExistingWorkspace $profileMappings $versionControlServer

            if($workspace.SyncPolicy -ne 'NoneOrDelete')
            {
                Write-Output "Using the '$profile' profile for the '$($workspace.Name)' workspace"
                # all mappings match an existing workspace or no workspace at all, so let's create/update the workspace and then sync
                if ($existingWorkspace -eq $null)
                {
                    try
                    {
                        $existingWorkspace = Create-Workspace $workspace.Name $profileMappings $versionControlServer
                    }
                    catch [Microsoft.TeamFoundation.VersionControl.Client.WorkingFolderInUseException]
                    {
                        Write-Output "The workspace '$($workspace.Name)' has already been created, but does not exist in the local cache."
                        Update-LocalCache $versionControlServer
                        $existingWorkspace = Find-ExistingWorkspace $profileMappings $versionControlServer

                        if ($existingWorkspace -eq $null)
                        {
                            throw "The '$($workspace.Name)' workspace cannot be created or used because the TFS server is already tracking another workspace which is owned by a different user at the same location on disk. Please delete or move the workspace which the current account does not have access to use before rerunning init. Try running 'tf workspaces /collection:$($workspace.CollectionUri) /owner:*' to see all workspaces on this machine."
                        }
                        else
                        {
                            Update-Mappings $existingWorkspace $profileMappings
                        }
                    }
                }
                else
                {
                    # Even though these local paths are already mapped in a workspace, they might be pointing to the wrong server locations.
                    # Update them to point to the correct locations specified in the config file
                    try
                    {
                        Update-Mappings $existingWorkspace $profileMappings
                    }
                    catch [Microsoft.TeamFoundation.VersionControl.Client.WorkspaceNotFoundException]
                    {
                        Write-Output "The workspace '$($existingWorkspace.Name)' exists in the local cache, but not on the server. Retrying with a different workspace..."
                        # Note: We do not need to explicitly update the cache here. The TFS OM does this implicitly before it throws this exception,
                        # so we just need to retry at this point...

                        # Most likely this will be null now, because there should not be a workspace mapped at this path anymore
                        $existingWorkspace = Find-ExistingWorkspace $profileMappings $versionControlServer

                        if ($existingWorkspace -eq $null)
                        {
                            $existingWorkspace = Create-Workspace $workspace.Name $profileMappings $versionControlServer
                        }
                        else
                        {
                            Update-Mappings $existingWorkspace $profileMappings
                        }
                    }
                }

                if (!$IsUnderTest)
                {
                    Write-Host "Total execution time for $($workspace.Name) mapping: $duration"
                }
            }
        }
        
        Write-TelemetryMetricFinish "$($workspace.Name) Mapping"

        if($workspace.SyncPolicy -eq 'NoneOrDelete')
        {
            if ($existingWorkspace)
            {
                Write-Output "Deleting workspace '$($workspace.Name)' as SyncPolicy is NoneOrDelete"
                $result = $existingWorkspace.Delete()
            }
            if (Test-Path $workspace.LocalRoot)
            {
                # Remove workspace folder (used for removing InternalAPIs and OptimizationData folders)
                Write-Output "Deleting files from '$($workspace.LocalRoot)' as SyncPolicy is NoneOrDelete"
                Invoke-Command { cmd /c rmdir /s /q $workspace.LocalRoot }

                # Validate that folder was successfully removed
                if (Test-Path $workspace.LocalRoot)
                {
                    Write-Output "The folder '$($workspace.LocalRoot)' was not successfully removed. Close any program that has a lock on the folder (can check via Process Explorer) and run Init."
                }
                else
                {
                    Write-Output "The folder '$($workspace.LocalRoot)' was successfully removed"
                }
            }
        }
        else
        {
            Sync-MappedFolders $existingWorkspace $workspace
        }
    }
    finally
    {
        # Even if Manage-Workspace fails, record the disk usage telemetry
        Write-TelemetryDiskFreeAfter $workspace.Name $localFolder
        Unregister-Events $versionControlServer $gettingEventHandler
    }
}

function Generate-TfsOutFiles($config)
{
    $properties = @{}
    foreach ($workspace in $config.workspaces.Values)
    {
        $properties[$workspace.Name + "Path"] = $workspace.LocalRoot
    }

    Create-MsbuildPropsFile (Get-OutFilePath "tfs.props")  $properties
    Create-BatchCmdFiles $properties
    Create-BuildIncFiles $properties

    # return the created hash mainly for unit testing purposes
    return $properties
}

function Get-TfsEnlistmentCacheFile
{
    return "workspaces.txt"
}

#main interface for the future provider

#$state is not being used right now
function Invoke-Provider([string]$state)
{
    $config = Load-Config
    if ($config -eq $null)
    {
        #if the branch does not have branch.json, it means we have to do nothing
        return
    }

    # Prep the environment for using TFS Object Model APIs
    LoadFromPackage-TfsAssemblies

    foreach ($workspace in $config.workspaces.Values)
    {
        Manage-Workspace $workspace
    }

    Generate-TfsOutFiles $config | Out-Null

    # Remove the repos section of the TFS enlistment status content, since we do not want to consider git repos in the TFS fast up-to-date check.
    # TODO: scope down even more
    $propertiesToRemove = @("repos")
    $content = Generate-EnlistmentStatusFileContent $config $propertiesToRemove
    Save-EnlistmentStatusFileContent (Get-EnlistmentStatusFileLocation (Get-TfsEnlistmentCacheFile)) $content

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

    $propertiesToRemove = @("repos")
    $needUpdates = Test-UpdatesAreNeeded $config (Get-TfsEnlistmentCacheFile) $propertiesToRemove
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
        exit 0

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
