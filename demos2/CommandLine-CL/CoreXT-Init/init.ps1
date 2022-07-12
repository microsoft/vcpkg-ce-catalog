#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

<#
.SYNOPSIS

Initializes a build environment
.DESCRIPTION

1. Performs operations required to get your enlistment into a state where a build can be successful, including downloading Nuget packages; setting up links to the cache for those packages; managing TFS workspaces for QA sources, Optimization Data, and InternalApis; associating other required Git repos, and setting up razzle arguments.

2. Creates razzle shortcut(s) for your enlistment.
.PARAMETER Force

Invoke all providers even if they would otherwise be skipped
.PARAMETER AuxOnly

Sync auxiliary tfs and git assets specified by the current profiles only; does not download and link packages

DO NOT USE THIS FOR PRODUCTION WORK. YOUR ENLISTMENT IS NOT GUARANTEED TO BE IN A VALID STATE

This option is to be used ONLY for gathering timing data
.PARAMETER PkgOnly

Download and link the packages specified by the current profile only; does not sync auxiliary tfs and git assets

DO NOT USE THIS FOR PRODUCTION WORK. YOUR ENLISTMENT IS NOT GUARANTEED TO BE IN A VALID STATE

This option is to be used ONLY for gathering timing data
.PARAMETER CleanCache

Remove the cache folder (%%NugetMachineInstallRoot%%) along with enlistment links to it
.PARAMETER CleanLinks

Remove enlistment links to the cache folder (%%NugetMachineInstallRoot%%)
.PARAMETER ScorchTfs

Scorches the tfs workspaces specified by the current profiles (with tfpt scorch) before syncing. Implies "-Force".
.PARAMETER BasicAuth

Prompts for credentials when connecting to the VSTS Drops Service. Do not attempt to use Azure AD. Use this option when working over DirectAccess or VPN.
.PARAMETER NoDownload

Set up environment but do not download packages
.PARAMETER FixCacheCorruption

Iterate through cache to check packages for missing files. Mark corrupted packages so CoreXT will download them again.
.PARAMETER NewShortcut

Create razzle shortcut(s)
.PARAMETER BuildTypes

Create razzle shortcut(s) for the specified build types (options are chk and ret; default is chk)
.PARAMETER ShortcutTypes

Create razzle shortcut(s) for the specified shortcut type(s) (options are ps1 and cmd; default is ps1)
.PARAMETER TargetAllUsers

Create razzle shortcut(s) for all users (default is current user)
.PARAMETER DownloadMetadata

Download metadata for packages in profile to Destination folder. Note this will delete all existing *.metadata files in the destination folder before downloading new metadata.
.PARAMETER Destination

Destination directory for DownloadMetadata. The official build uses %_NTTREE%\BuildInspect\metadata.

.PARAMETER RazzleArgsInfoPath 

Path to store razzle arguments
.PARAMETER x86

Set up razzle with x86 architecture
.PARAMETER amd64

Set up razzle with amd64 architecture
.PARAMETER ARM64

Set up razzle with ARM64 architecture
.PARAMETER ARM

Set up razzle with ARM architecture
.PARAMETER Chk

Set up razzle with Chk flavor
.PARAMETER Ret

Set up razzle with Ret flavor
.PARAMETER No_opt

Set up razzle with no_opt
.PARAMETER ForceComplus

Set up razzle with complus flag
.PARAMETER RazzleOptions

Set up razzle with given razzle options
.PARAMETER PrevRazzleArgs 

Skip syncing down packages and other enlistments
.PARAMETER NoSync

Razzle arugments of previous run
.EXAMPLE

init.ps1
.EXAMPLE

init.ps1 -force
.EXAMPLE

init.ps1 -cleancache
.EXAMPLE

init.ps1 -fixcachecorruption
.EXAMPLE

init.ps1 -newshortcut

Creates a chk Powershell razzle shortcut on the current user's desktop
.EXAMPLE

init.ps1 -newshortcut -shortcuttypes ps1,cmd -buildtypes chk,ret

Creates chk and ret Powershell and cmd.exe razzle shortcuts on the current user's desktop
.EXAMPLE

init.ps1 -newshortcut -targetallusers -buildtypes ret

Creates a ret Powershell razzle shortcut on the desktop for all users
.EXAMPLE

init.ps1 -downloadmetadata $env:_NTTREE\BuildInspect\metadata

Downloads package metadata to %_NTTREE%\BuildInspect\metadata

.NOTES

These environment variables effect the behavior of %0:
   [Deprecated]CoreXTProfile   - Affects package selection. Profiles are listed in %%CoreXTConfigFile%%. (Default is "Default")
                                 This environment variable now is deprecated. Use profile.cmd instead to change the CoreXT profile
   CoreXTConfigFile            - Defines packages and profiles. (Default is .corext\Configs\default.config.)
   NugetMachineInstallRoot     - Defines install folder for packages. Value is machine-wide. (Default is %~d0\NugetCache.)
.LINK

http://aka.ms/dd1es-help
.LINK

https://microsoft.sharepoint.com/teams/corext/LivingDocs/CorextInitialization.aspx
#>
[CmdletBinding(SupportsShouldProcess=$true, DefaultParametersetName="InitEnlistment")]
param (
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $Force,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $AuxOnly,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $PkgOnly,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $Cleancache,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $Cleanlinks,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $ScorchTfs,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $NoDownload,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $HaltOnFailure,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $FixCacheCorruption,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $BasicAuth,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $SkipExportsPrune,
    [Parameter(Mandatory, ParameterSetName="CreateShortcut")]
    [Alias("CreateShortcut")]
    [Switch] $NewShortcut,
    [Parameter(ParameterSetName="CreateShortcut")]
    [ValidateSet("chk", "ret")]
    [String[]] $BuildTypes = @("chk"),
    [Parameter(ParameterSetName="CreateShortcut")]
    [ValidateSet("cmd", "ps1")]
    [String[]] $ShortcutTypes = @("cmd", "ps1"),
    [Parameter(ParameterSetName="CreateShortcut")]
    [Switch] $TargetAllUsers,
    [Parameter(Mandatory=$false, ParameterSetName="InitEnlistment")]
    [Switch] $CloudBuild = $false,
    [Parameter(Mandatory, ParameterSetName="DownloadMetadata")]
    [Switch] $DownloadMetadata,
    [Parameter(Mandatory, ParameterSetName="DownloadMetadata")]
    [String] $Destination,
    [Parameter(ParameterSetName="InitEnlistment")]
    [String] $RazzleArgsInfoPath,
    [Parameter(ParameterSetName="InitEnlistment")]
    [Switch] $X86,
    [Parameter(ParameterSetName="InitEnlistment")]
    [Switch] $Amd64,
    [Parameter(ParameterSetName="InitEnlistment")]
    [Switch] $ARM64,
    [Parameter(ParameterSetName="InitEnlistment")]
    [Switch] $ARM,
    [Parameter(ParameterSetName="InitEnlistment")]
    [Switch] $Chk,
    [Parameter(ParameterSetName="InitEnlistment")]
    [Switch] $Ret,
    [Parameter(ParameterSetName="InitEnlistment")]
    [Switch] $No_opt,
    [Parameter(ParameterSetName="InitEnlistment")]
    [Switch] $ForceComplus,
    [Parameter(ParameterSetName="InitEnlistment")]
    [String] $RazzleOptions,
    [Parameter(ParameterSetName="InitEnlistment")]
    [String] $PrevRazzleArgs,
    [Parameter(ParameterSetName="InitEnlistment")]
    [Switch] $NoSync
)

function Test-ShouldSelfElevate()
{
    return -not (Test-HardLinkCapability) -and -not (Get-IsAdmin)
}

function Write-CoreXtProgress($o, $eventArgs)
{
    try
    {
        if ($EventSubscriber.EventName -eq "ErrorDataReceived")
        {
            $global:corextErrors.Add($EventArgs.Data)
        }

        if ($EventArgs.Data -match "Installing (\d+) packages")
        {
            $totalPackagesToInstall = [int]$Matches[1]
        }
        elseif ($EventArgs.Data -match "Cleaning (\d+) package folders \(install prep\)")
        {
            # Suppress as CoreXT currently says that it is cleaning all packages it is downloading which is confusing for users
        }
        elseif ($EventArgs.Data -match "Installing '(.*) .*'")
        {
            $currentlyInstalling.Add($Matches[1])
            if ($totalPackagesToInstall -lt $currentlyInstalling.Count)
            {
                # Special case for a small number of packages being installed where CoreXT doesn't tell us how many will be installed
                $totalPackagesToInstall = $currentlyInstalling.Count
            }
        }
        elseif ($EventArgs.Data -match "Restoring NuGet package (.*)\.$")
        {
            $currentlyInstalling.Add($Matches[1])
        }
        elseif ($EventArgs.Data -match "Successfully installed '(.*) .*'")
        {
            $successfullyInstalled.Add($Matches[1]);
            $currentlyInstalling.RemoveAll( { param($n) $n -eq $Matches[1] } )
        }
        elseif ($EventArgs.Data -match "Added package '([^']*)'.*")
        {
            $successfullyInstalled.Add($Matches[1]);
            $currentlyInstalling.RemoveAll( { param($n) $n -eq $Matches[1] } )
        }
        elseif ($EventArgs.Data -match "MSBuild auto-detection: .*")
        {
            # Suppress this warning
        }
        elseif ($EventArgs.Data -match "Adding package '(.*)' .*")
        {
            # Nothing to do
        }
        elseif ($EventArgs.Data -match "GET: .*")
        {
            # Nothing to do
        }
        elseif ($EventArgs.Data -match "Missing \d+ package dependencies")
        {
            # The config file filtered on the selected profile(s) is at $env:CoreXtConfigFile--
            # this is what corext knows about. But if there's a missing package dependency, we
            # want to tell the user to edit the unfiltered config file so the changes will stick
            Write-Host $EventArgs.Data.Replace($env:CoreXtConfigFile, $CoreXtConfigFile)
        }
        elseif ($EventArgs.Data -match "Installing .*")
        {
            # Nothing to do
        }
        elseif ($EventArgs.Data -match "Completed installation of .*")
        {
            # Nothing to do
        }
        elseif ($EventArgs.Data -match "Acquir(?:ing|ed) lock for the installation of .*")
        {
            # Nothing to do
        }
        elseif ($EventArgs.Data -match "\*\* Warning \*\* Issue uploading pingback data")
        {
            # Nothing to do
        }
        elseif ($EventArgs.Data)
        {
            # Write out anything else, since that's where error messages, etc will go
            Write-Host $EventArgs.Data
        }

        $numberPackagesInstalled = $successfullyInstalled.Count
        if ($currentlyInstalling.Count -gt 0)
        {
            if ($totalPackagesToInstall -gt 0)
            {
                if ($numberPackagesInstalled -gt $totalPackagesToInstall)
                {
                    $totalPackagesToInstall = $numberPackagesInstalled
                }
                $percent = ($numberPackagesInstalled / $totalPackagesToInstall)
            }
            else
            {
                $percent = 0
            }
            Write-Progress -Activity "Downloading Nuget packages to your local cache" -Status ("{0:P1} complete" -f $percent) -CurrentOperation ($currentlyInstalling -join ", ") -PercentComplete ([int]($percent * 100))
        }
        elseif ($numberPackagesInstalled -gt 0 -and $numberPackagesInstalled -eq $totalPackagesToInstall)
        {
            Write-Progress -Activity "Downloading Nuget packages to your local cache" -Completed
        }
    }
    catch
    {
        # Do nothing here since it's not worth crashing over a problem with Write-Progress,
        # but if we don't catch the exception, there is no further feedback for the user
    }
}

function Invoke-CoreXt()
{
    Write-Host "Using CoreXT to populate Nuget package cache under $(Get-NugetCachePath)"
    # Variables that will be used for Write-Progress
    $global:totalPackagesToInstall = 1
    $global:successfullyInstalled = New-Object System.Collections.Generic.HashSet[String]
    $global:currentlyInstalling = New-Object System.Collections.Generic.List[String]
    $global:corextErrors = New-Object System.Collections.Generic.List[String]

    $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo("$env:Root\.CoreXt\corextBoot.exe")
    $processStartInfo.Arguments = "init -bootstrap"
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.CreateNoWindow = $true
    $processStartInfo.RedirectStandardOutput = $true
    $processStartInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $processStartInfo
    $eventScriptblock = ${function:Write-CoreXtProgress}
    $outEvent = Register-ObjectEvent -InputObject $process -Action $eventScriptblock -EventName "OutputDataReceived"
    $errEvent = Register-ObjectEvent -InputObject $process -Action $eventScriptblock -EventName "ErrorDataReceived"
    $process.Start() | Out-Null
    $process.BeginErrorReadLine()
    $process.BeginOutputReadLine()
    # If we use WaitForExit, all of the output is dumped at the end, so we must
    # instead poll for the exited status to allow the events to be processed as they happen
    do { } while (-not $process.HasExited)
    Unregister-Event -SourceIdentifier $outEvent.Name
    Unregister-Event -SourceIdentifier $errEvent.Name
    return $process.ExitCode, $global:corextErrors
}

function Overwrite-EventName
{
    param(
        [string]$currentEventName,
        [string]$newEventName
    )

    Write-Telemetry 'Event Context' $currentEventName
    Write-Telemetry EventName $newEventName
}

function Find-ErrorPattern($errorMessage)
{
    $eventName = $null
    $errorPattern = @{
        # User Error
        '*unable to find version* of package*' = 'User Error';
        '*is not a valid version string*' = 'User Error';
        '*workspace cannot be created or used*' = 'User Error';
        '*failure(s) occurred during the Get operation*'= 'User Error';
        'cannot convert value * to type *' = 'User Error';
        '*unsatisfied dependencies for package*' = 'User Error';
        '*please author the missing package versions*' = 'User Error';
        '*network path was not found*' = 'User Error';
        '*failed to find git.exe*please ensure*contains path to git.exe*' = 'User Error';
        '*error deleting one or more files*may be locked*' = 'User Error';
        '*missing from cache*not enough space on the disk*' = 'User Error';
        '*duplicate package and version detected*' = 'User Error';
        '*cannot create a file when that file already exists*' = 'User Error';
        # External Error
        '*unexpected network error occurred*' = 'External Error';
        # Out Of Disk Space
        '*not enough space on the disk*' = 'Out Of Disk Space'
    }

    foreach ($pattern in $errorPattern.Keys)
    {
        if($errorMessage -like $pattern)
        {
           $eventName = $errorPattern[$pattern]
           break
        }
    }

    return $eventName
}

function Report-FinalResult
{
    param(
        [string]$telemetryEventName,
        [string]$detailedConsoleErrorMessage = $null,
        [System.Management.Automation.ErrorRecord]$errorRecord = $null,
        [string[]]$errorDetails = $null
    )

    $eventName = $null

    if ($errorRecord)
    {
        Write-Error -ErrorRecord $errorRecord -ErrorAction Continue 
        $errorRecord.Exception.Data.GetEnumerator() | % {
            Write-Host '========== EXCEPTION DATA =========='
            Write-Host "$($_.Key) => $($_.Value)"
            Write-Host '========== EXCEPTION DATA =========='
        }

        Write-Host $errorRecord.ScriptStackTrace
        Write-TelemetryError $errorRecord
        $errorRecord | Format-List * -Force | Out-File (Get-LocalLogFile) -Encoding utf8
        $eventName = Find-ErrorPattern $errorRecord.Exception.Message
    }

    if (($eventName -eq $null) -and $errorDetails -and $errorDetails.Length -gt 0)
    {
        foreach ($line in ($errorDetails | ?{ $_.Length -gt 0 }))
        {
            Write-TelemetryList "Error Details" $line
            if ($eventName -eq $null)
            {
                $eventName = Find-ErrorPattern $line
            }
        }
    }

    if($eventName -ne $null)
    {
        Overwrite-EventName $telemetryEventName $eventName
    }
    else
    {
        Write-Telemetry EventName $telemetryEventName
    }

    Write-TelemetryMetricFinish "Total"
    Upload-CachedTelemetry

    if ($detailedConsoleErrorMessage)
    {
        Write-Host -NoNewline -Foreground Red "[Error]"
        Write-Host -NoNewline $detailedConsoleErrorMessage
        Write-Host -NoNewline " "
        Write-Host "This enlistment window will not work."
        if($HaltOnFailure)
        {
            Pause
        }
    }
}

function Initialize-Telemetry()
{
    Set-UniqueTelemetryFile

    Write-TelemetryMetricStart "Total"
    Write-Telemetry "CoreXT Profile" (Get-CoreXTProfileNames -join ',')

    # RI/FI process sets env var PiPkgId (per DavBurk) so use that to set context
    Write-Telemetry "RI/FI Context" (Test-Path 'env:PiPkgId')

    if ($args)
    {
        Write-Telemetry "Argument" ($args -join ",")
    }

    if ($env:CoreXTRepoName)
    {
        Write-Telemetry "CoreXT Repo Name" $env:CoreXTRepoName
    }

    Write-TelemetryTimestamp "Log Time"
}

function Get-CorextCommandlinePath()
{
  $workingDirectory = "$env:LocalAppData\devconsole"
  $packageCachePath = "pkgs","packages"

  $corextBootConfigFile = "$env:Root\.CoreXt\corextBoot.exe.config"
  if(Test-Path $corextBootConfigFile)
  {
      [xml]$xml = Get-Content $corextBootConfigFile
      $tempWorkingDirectory = $xml.configuration.appSettings.add | ? { $_.key -eq 'WorkingDirectory'}
      if($tempWorkingDirectory -ne $null)
      {
          $workingDirectory = $tempWorkingDirectory.value
      }

      $tempPackageCachePath = $xml.configuration.appSettings.add | ? { $_.key -eq 'PackageCachePath'}
      if($tempPackageCachePath -ne $null)
      {
          $packageCachePath = $tempPackageCachePath.value
      }
  }
  $CorextCommandlinePath = @()
  foreach($pkg in $packageCachePath)
  {
    $CorextCommandlinePath += Join-Path $workingDirectory (Join-Path $pkg "DevConsole.Commandline")
  }

  return $CorextCommandlinePath
}

function Initialize-Enlistment()
{
    $retVal = 0
    if(-not $NoSync) {Initialize-Telemetry}
    if($RazzleArgsInfoPath) { Process-RazzleArgs }

    if($NoSync) 
    {
        exit 0
    }

    if (-not $AuxOnly)
    {
        try
        {
            if ($Cleanlinks)
            {
                & $PSScriptRoot\.coreXT\Clean.ps1 -Links
                Report-FinalResult "Clean Links Success"
                return
            }
            if($Cleancache)
            {
                & $PSScriptRoot\.coreXT\Clean.ps1 -Cache
            }
        }
        catch
        {
            Report-FinalResult "Clean Error" "Could not clean packages." $_
            exit 1
        }

        if($Force -eq $false -and $ScorchTfs -eq $false)
        {
            try
            {
                & $PSScriptRoot\.coreXT\DetermineIfUpdatesAreRequired.ps1
                if($LASTEXITCODE -eq 0)
                {
                    $corextCommandlinePathExists = $false
                    foreach($path in Get-CorextCommandlinePath)
                    {
                        if(Test-Path $path)
                        {
                            $corextCommandlinePathExists = $true
                            break
                        }
                    }

                    if($corextCommandlinePathExists)
                    {
                        Report-FinalResult "Init No Updates"
                        Set-PathWithGitAdded
                        Save-BuildInfo
                        exit 0
                    }
                }
            }
            catch [System.Management.Automation.RuntimeException]
            {
                if ($_ -like '*does not contain any profile data for*')
                {
                    Report-FinalResult "User Error" $consoleErrMessage $_
                    exit 1
                }

                throw
            }
        }

        if($NoDownload)
        {
            Report-FinalResult "Init No Download"
            Set-PathWithGitAdded
            Save-BuildInfo
            exit 0
        }

        #region CoreXt provider
        & $PSScriptRoot\.coreXT\GenerateProfileConfig.ps1
        if ($LASTEXITCODE -gt 0)
        {
            Report-FinalResult "Package Config Init Error" "Could not create package config profile."
        }

        $file = Get-CoreXtProfileConfigFile
        if (Test-Path $file)
        {
            # Save this value for later when we'll restore the variable to it
            $coreXtConfigFileSource = $env:CoreXtConfigFile
            $env:CoreXtConfigFile = $file
        }
        else
        {
            $coreXtConfigFileSource = $null
        }

        Write-TelemetryDiskFreeBefore "CoreXT"
        Write-TelemetryMetricStart "CoreXT"

        if($FixCacheCorruption)
        {
            try
            {
                & $PSScriptRoot\.coreXt\FixCacheCorruption.ps1
            }
            catch [System.IO.IOException]
            {
                Report-FinalResult "User Error" "Error fixing cache corruption" $_
                exit 1
            }
        }

        # Call CoreXT with retries if running in non-interactive mode
        $retry = 0
        $retryTimeouts = @( 5, 25, 90, 180 )
        Do
        {
            Invoke-CommandWithGlobalGac { $script:coreXtExitCode, $script:coreXtErrors = Invoke-CoreXt }
            $terminationCondition = $script:coreXtExitCode -eq 0 -or $retry -ge $retryTimeouts.Count -or -not (Get-NonInteractive)
            if (-not $terminationCondition)
            {
                Write-Host -Foreground Yellow "Retry attempt $retry in $($retryTimeouts[$retry]) seconds"
                Start-Sleep $retryTimeouts[$retry]
                $retry++
            }
        }
        Until ( $terminationCondition )

        if($FixCacheCorruption)
        {
            & $PSScriptRoot\.coreXt\GenerateExpectedFileLists.ps1
        }
        Write-TelemetryMetricFinish "CoreXT"
        Write-TelemetryDiskFreeAfter  "CoreXT"

        if ($coreXtConfigFileSource)
        {
            # Restore the config file to the original source file instead of the generated profile config
            $env:CoreXtConfigFile = $coreXtConfigFileSource
        }

        if($script:coreXtExitCode -gt 0)
        {
            Report-FinalResult "CoreXT Init Error" "CoreXT could not be properly initialized." -errorDetails $script:coreXtErrors.ToArray()
            exit 1
        }

        try
        {
            Write-TelemetryMetricStart "Link Packages"
            & $PSScriptRoot\.coreXT\LinkPackagesIntoSourceTree.ps1
            $packageLinkingExitCode = $LASTEXITCODE
            Write-TelemetryMetricFinish "Link Packages"
        }
        catch [NotSupportedException]
        {
            Report-FinalResult "User Error" "Could not link packages into source." $_
            exit 1
        }

        if ($packageLinkingExitCode -gt 0)
        {
            Report-FinalResult "Package Linking Error" "Could not link packages into source."
            exit 1
        }
        #endregion
    }

    Set-PathWithGitAdded
    Save-BuildInfo

    # Temporary hack to get init working in CloudBuild datacenters. TFS is clearly forbidden due to the corpnet dependency, but it's not
    # clear if Git/VSTS Drops auth would work out of the box. Debugging enlistment prep issues in CB is slow, so for now just turn all of
    # the aux enlistments off. For PR builds, these should not be needed. For official builds, we will need VSTS Drops at a minimum to
    # produce optimized binaries.
    if (-not $env:QBUILD_DISTRIBUTED -and -not $PkgOnly)
    {
        #region TFS and Git providers
        $auxiliaryEnlistmentConfig = (Get-AuxConfigPath)
        if (Test-Path $auxiliaryEnlistmentConfig)
        {
            $consoleErrMessage = "Could not update TFS Auxiliary enlistment(s): Mappings in $AuxiliaryEnlistmentConfig will be missing or not in sync."
            $internalApiDeletionMessage = "InternalAPIs in auxsrc(TFS Enlisment) will be deleted (For details visit http://aka.ms/removeinternalapi). Any related failure(s) will require manual intervention. "

            try
            {
                Write-TelemetryMetricStart "Update Aux Workspaces"
                & $PSScriptRoot\.coreXT\TfsEnlistmentProvider.ps1 $auxiliaryEnlistmentConfig -Scorch:$ScorchTfs
                Write-TelemetryMetricFinish "Update Aux Workspaces"
            }
            catch [System.IO.FileNotFoundException]
            {
                Report-FinalResult "User Error" $consoleErrMessage $_
                exit 1
            }
            catch [System.Management.Automation.MethodInvocationException]
            {
                if ($_ -like '*you are not authorized to access*' -or
                    $_ -like '*workspace* does not reside on this computer*' -or
                    $_ -like '*requested mapping matches an existing mapping on server path*')
                {
                    Report-FinalResult "User Error" $consoleErrMessage $_
                    exit 1
                }

                if($_ -like '*http request operation timed out*')
                {
                    Report-FinalResult "External Error" $consoleErrMessage $_
                    exit 1
                }
                 
                Report-FinalResult "Update TFS Hybrid Enlistment Error" $consoleErrMessage $_
                exit 1
            }
            catch
            {
                $exceptionMessage = $_
                $cleanMessage = $_ -replace("'","");
                if($cleanMessage -like 'The directory is not empty*' -or
                    $cleanMessage -like 'The process cannot access the file *InternalApis*')
                {
                    $exceptionMessage = $internalApiDeletionMessage + $_
                }

                Report-FinalResult "Update TFS Hybrid Enlistment Error" $consoleErrMessage $exceptionMessage
                exit 1
            }

            try
            {
                Write-TelemetryMetricStart "Update Aux Repos"
                & $PSScriptRoot\.coreXT\GitEnlistmentProvider.ps1 $auxiliaryEnlistmentConfig
                Write-TelemetryMetricFinish "Update Aux Repos"
            }
            catch [System.IO.FileNotFoundException]
            {
                Report-FinalResult "User Error" $consoleErrMessage $_
                exit 1
            }
            catch
            {
                Report-FinalResult "Update Git Hybrid Enlistment Error" "Could not update Git Auxiliary enlistment(s): Repos in $AuxiliaryEnlistmentConfig will be missing or not in sync." $_
                exit 1
            }

            try
            {
                Write-TelemetryMetricStart "Update Aux Drops"
                & $PSScriptRoot\.coreXT\VstsDropProvider.ps1 $auxiliaryEnlistmentConfig -BasicAuth:$BasicAuth -SkipExportsPrune:$SkipExportsPrune
                Write-TelemetryMetricFinish "Update Aux Drops"
            }
            catch [System.IO.IOException]
            {
                Report-FinalResult "User Error" "Could not update Auxiliary VSTS Drop(s): VstsDropProvider was unable to delete a directory, likely because it is being used by another process." $_
                exit 1
            }
            catch
            {
                # Failure to download from VSTS drop should not block init.
                # Init should continue but exit with a non-zero value to indicate this failure.
                Write-Host -ForegroundColor Red "ERROR: Update VSTS Drop failed: $_"
                Write-Telemetry "Update VSTS Drop Error" $_
                $retVal = 5
            }

            try
            {
                $componentsConfig = Get-ComponentConfigPath
                Write-TelemetryMetricStart "Update Components"
                & $PSScriptRoot\.coreXT\ComponentsProvider.ps1 $componentsConfig
                Write-TelemetryMetricFinish "Update Components"
            }
            catch
            {
                Report-FinalResult "Update Components Error" "Could not update Components: Component manifests required for installer build may be missing or out of date." $_
                exit 1
            }
        }
        #endregion
    }

    if (-not $AuxOnly -and -not (Test-Path $PSScriptRoot\cloudbuild.sem)) 
    {
        $corextOutputtedInitCmd = Join-Path (Get-PackageAddressGenDir) init.cmd
        if (Test-Path $corextOutputtedInitCmd)
        {
            # Send output to null
            & $corextOutputtedInitCmd -recurse | Out-Null
        }
    }

    if ($PkgOnly)
    {
        Report-FinalResult "Update Packages"
    }
    elseif ($AuxOnly)
    {
        Report-FinalResult "Update Aux Assets"
    }
    else
    {
        Report-FinalResult "Init Updates Required"
    }

    if (-not $AuxOnly)
    {
        & $PSScriptRoot\.coreXT\UpdateHashForSuccessfulInit.ps1
    }

    return $retVal
}

function New-Shortcut()
{
    Set-RequiredEnvironmentVariables
    $providerArgs = @{
        BuildTypes=$BuildTypes
        ShortcutTypes=$ShortcutTypes
        TargetAllUsers=$TargetAllUsers
    }
    & $PSScriptRoot\.coreXT\ShortcutProvider.ps1 @providerArgs
}

function Download-Metadata()
{
    Set-RequiredEnvironmentVariables
    $providerArgs = @{
        Destination=$Destination
    }
    Initialize-Telemetry
    Write-TelemetryMetricStart "Download Metadata"
    & $PSScriptRoot\.coreXT\MetadataProvider.ps1 @providerArgs
    Write-TelemetryMetricFinish "Download Metadata"
    Write-Telemetry EventName "Download Metadata"
    Upload-CachedTelemetry
}

function Set-PathWithGitAdded()
{
    if($CloudBuild)
    {
        # Temporary hack to get init working in CloudBuild. We need to add git to the path for TfVcTool.
        $gitExe = Get-GitExePath
        # Remove quotes or we'll get an exception from GetDirectoryName
        $gitExe = $gitExe -replace "`""
        $gitPath = [IO.Path]::GetDirectoryName($gitExe)
        Write-Verbose "Putting git at $gitPath on the path" 
        $env:Path = "$env:Path;$gitPath"
        Set-OutputEnvironment
    }
}

function Save-BuildInfo
{
    # For backwards compatibility with TFS branches we only attempt if branches.json exists
    if (Test-ConfigFileExists)
    {
        # Look up build number in git tags from TfvcTool
        $cachedPackageLocation = Get-RequiredPackageLocationOrExit "VS.Tools.TfvcToolFiles"
        $tfvcModulePath = Join-Path $cachedPackageLocation "TfvcTool.PowerShell.psm1"
        Import-Module $tfvcModulePath
        $buildNumber = (Get-BuildInfo $PSScriptRoot).BuildNumber

        # Get current saved build number
        $buildNumberOutputPath = Get-OutFilePath "BuildNumberOutput.txt"
        if (Test-Path -PathType Leaf $buildNumberOutputPath)
        {
            $currentBuildNumber = Get-Content $buildNumberOutputPath
        }

        # Save new build number if they differ
        if ($currentBuildNumber -ne $buildNumber)
        {
            Write-Host "Generated build number $buildNumber"
            Set-Content -Path $buildNumberOutputPath $buildNumber
        }
    }
}

function Process-RazzleArgs
{
     $RazzleArgs=""
     if($X86) { $RazzleArgs += " x86 " }
     if($Amd64) { $RazzleArgs += " amd64 " }
     if($ARM) { $RazzleArgs += " ARM " }
     if($ARM64) { $RazzleArgs += " ARM64 " }
     if($Chk) { $RazzleArgs += " chk " }
     if($Ret) { $RazzleArgs += " ret " }
     if($No_opt) { $RazzleArgs += " no_opt " }
     if($ForceComplus) { $RazzleArgs += " forcecomplus " }
     if($RazzleOptions) { $RazzleArgs += $RazzleOptions}
     if(-not $RazzleArgs -and $PrevRazzleArgs) { $RazzleArgs = $PrevRazzleArgs }
     $RazzleArgs | Out-File -FilePath $RazzleArgsInfoPath -Encoding Ascii
 
     if($RazzleArgs)
     {
         # skip the next razzle input arguments for each switch in the following list
         $SkipList=@('Binaries_dir','FullBinaries_dir','Postbld_dir','sepchar','Setups_dir','offlinebranch','Temp','Title','ProductCue_Pub','BFDCue_Pub','RemoteCue_Pub')
         $skip=$false;
         foreach($arg in (-split $RazzleArgs)){            
             if(-not $skip)
             { 
                Write-Telemetry "R_$arg" 1               
                #ignore the rest of arguments after exec switch
                if($arg -contains 'exec')
                {
                    break;
                }
                $SkipList |ForEach {
                    if ($arg -contains $_)
                    {
                        $skip=$true;
                    }
                }
             }
             else
             {
                  $skip=$false;
             }
         }
     }
     else
     {
         Write-Telemetry "R_Default" 1
     }
}

try
{
    . $PSScriptRoot\.corext\Common\Environment.ps1
    . $PSScriptRoot\.corext\Common\GeneralUtilities.ps1
    . $PSScriptRoot\.corext\Common\Telemetry.ps1
    . $PSScriptRoot\.corext\Common\AuxiliaryEnlistment.ps1
    . $PSScriptRoot\.corext\Common\Components.ps1
    . $PSScriptRoot\.corext\Common\LinkUtilities.ps1
    . $PSScriptRoot\.corext\Common\GitUtilities.ps1
        
    $retVal = 0
    if (Get-NonInteractive)
    {
        Write-Host "Build agent detected - running non-interactive"
    }
    Set-Environment
    
    switch($PSCmdlet.ParameterSetName)
    {
        "InitEnlistment"
        {
            if(Test-ShouldSelfElevate)
            {
                Write-Host "Init requires elevation. This will launch in a separate window."

                $line = $PSCmdlet.MyInvocation.Line
                if($line -ne "")
                {
                    # replace the (potentially) relative path with the absolute path to the script
                    $invName = [Regex]::Escape($PSCmdlet.MyInvocation.InvocationName)
                    $scriptCommand = $PSCmdlet.MyInvocation.Line -replace $invName, $PSCmdlet.MyInvocation.MyCommand.Definition
                }
                else
                {
                    # This happens in the ISE, for example
                    $scriptCommand = $PSCmdlet.MyInvocation.MyCommand.Definition
                }

                if(!(Invoke-ElevatedCommand "$scriptCommand -HaltOnFailure"))
                {
                    exit 1
                }
                Write-Host "Elevated init completed successfully."
                exit 0
            }
            else
            {
                $duration = Measure-Command { $retVal = Initialize-Enlistment }
                Write-Host "Total execution time for initializing enlistment: $duration"
            }
        }
        "CreateShortcut"
        {
            New-Shortcut
        }
        "DownloadMetadata"
        {
            Download-Metadata
        }
    }

    exit $retVal
}
catch
{
    Report-FinalResult "Init Exception" "Init encountered a fatal error." $_
    exit 1
}
