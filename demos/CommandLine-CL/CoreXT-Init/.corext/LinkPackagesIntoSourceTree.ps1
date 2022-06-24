#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

#Requires -Version 3.0

. "$PSScriptRoot\Common\CoreXtConfig.ps1"
. "$PSScriptRoot\Common\Environment.ps1"
. "$PSScriptRoot\Common\FastUpdateCheck.ps1"
. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\LinkUtilities.ps1"
. "$PSScriptRoot\Common\PackageCache.ps1"
. "$PSScriptRoot\Common\Telemetry.ps1"


# Static variable recording when Test-IntervalPassed last returned True
[DateTime] $script:lastIntervalStartTime = 0
# Returns True only if specified number of milliseconds has passed since the last time True was returned
function Test-IntervalPassed($milliseconds)
{
    $now = [System.DateTime]::Now
    $result = $now -gt $script:lastIntervalStartTime.AddMilliseconds($milliseconds)
    if ($result)
    {
        $script:lastIntervalStartTime = $now
    }
    return $result
}

function Get-LinkResultObject($packageName, $packageDestinationPath, $cachedPackageLocation, $mode, $result, $resultDetails, [DateTime]$startOperationTime)
{
    if($startOperationTime)
    {
        $duration = ((Get-Date) - $startOperationTime).ToString()
    }
    $linkResult = New-Object PSObject
    $linkResult | Add-Member "PackageName" $packageName
    $linkResult | Add-Member "PackageDestinationPath" $packageDestinationPath
    $linkResult | Add-Member "CachedPackageLocation" $cachedPackageLocation
    $linkResult | Add-Member "Mode" $mode
    $linkResult | Add-Member "Result" $result
    $linkResult | Add-Member "ResultDetails" $resultDetails
    $linkResult | Add-Member "Duration" $duration
    return $linkResult
}

function Write-ResultToHost($linkResult)
{
    switch($linkResult.Result)
    {
        Success
        {
            $showStatus = $true
            $color = "Green"

            switch($linkResult.Mode)
            {
                Direct { $status = "Linked directly" }
                Contents { $status = "Linked contents" }
            }
        }
        Skipped
        {
            if($VerbosePreference -ne "SilentlyContinue")
            {
                $showStatus = $true
                $color = "Cyan"
                $status = "Skipped"
            }
            else
            {
                $showStatus = $false
            }
        }
        Error
        {
            $showStatus = $true
            $color = "Red"
            $status = "Failed - " + $linkResult.ResultDetails
        }
    }

    if ($showStatus)
    {
        Write-Host -NoNewline "$($linkResult.PackageName): "
        Write-Host -ForegroundColor $color $status
    }
}

function Link-PackagesToSource()
{
    $linkResults = $null
    $useHardLinks = Test-HardLinkCapability
    if (!$useHardLinks -and !(Get-IsAdmin))
    {
        throw "You must be running with Administrator privileges when %NugetMachineInstallRoot% and enlistment are on different drives"
    }
    $LinkRoots = Get-LinkRoots
    $CachedPackageLocations = Get-InstalledPackagesFromIncFile 
    $packageLinks = Get-PackageLinks
    if ($packageLinks)
    {
        Write-Verbose "Starting Test-PackageLinks"
        $duration = Measure-Command { Test-PackageLinks $packageLinks $CachedPackageLocations }
        Write-Verbose "Finished Test-PackageLinks in $($duration.TotalSeconds) seconds"

        $Count = 1 # Starting with one makes the progress bar end at 100%
        if ($packageLinks -is [Xml.XmlElement])
        {
            $Total = 1
        }
        else
        {
            $Total = $packageLinks.Count
        }
        $linkResults = $packageLinks | % { Link-PackageToSourceDestination $_.id $_.link $_.mode $useHardLinks $Count $Total; $Count++}
        Write-Progress -Activity "Creating and updating links" -Completed -Id $ProgressId
        $linkResults | % { Write-ResultToHost $_ }
    }
    else
    {
        $profileNames = Get-CoreXTProfileNames
        if ($profileNames.Count -eq 1)
        {
            Write-Warning "The CoreXT profile $profileNames does not contain any links"
        }
        else
        {
            Write-Warning "The CoreXT profiles $($profileNames -join ',') do not contain any links"
        }
    }
    return $linkResults
}

function Link-PackageToSourceDestination($packageName, $sourceDestination, $mode, $useHardLinks, $count, $total)
{
    $startPackageTime = Get-Date
    if (!$sourceDestination)
    {
        throw "The parameter sourceDestination is required"
    }

    if (Test-IntervalPassed($ProgressInterval))
    {  
        Write-Progress -PercentComplete ($count/$total*100) -CurrentOperation $_.package -Activity "Creating and updating links" -Status ("{0:P1} complete" -f ($count/$total)) -Id $ProgressId
    }
    $cachedPackageLocation = Get-PackageLocation $packageName $CachedPackageLocations
 
    if($cachedPackageLocation -eq $null)
    {
        Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation $null "Error" "Missing from cache" $startPackageTime)
    }
    else
    {
        $packageDestinationPath = "$SourceRoot\$sourceDestination"
        if(!(Get-IsDestinationAllowed $sourceDestination))
        {
            # Exception will be caught in Init.ps1 and error will be categorized as User Error (Bug 183950)
            $error = "Link destination not listed under allowed destinations"
            Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation $mode "Error" $error)
            throw [NotSupportedException] $error
        }

        switch ($mode)
        {
            skip      { Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation $null "Skipped" "" $startPackageTime) }
            contents  { Link-PackageContentsToSourceDestination $packageName $packageDestinationPath $cachedPackageLocation $useHardLinks }
            direct    { Link-PackageRootToSourceDestination $packageName $packageDestinationPath $cachedPackageLocation }
            default   { Link-PackageRootToSourceDestination $packageName $packageDestinationPath $cachedPackageLocation }
        }
    }
}

function Link-PackageContentsToSourceDestination($packageName, $packageDestinationPath, $cachedPackageLocation, $useHardLinks)
{
    $failure = $null
    $linkedAnything = $false
    $startPackageTime = Get-Date

    $result = Remove-AnyLinkedParentFolders $packageDestinationPath
    if(!($result['Success']))
    {
        $failure = "Could not remove folder link for {0} - {1}" -f $packageDestinationPath, [string]$result['Output']
        Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Contents" "Error" "$failure" $startPackageTime)
        return
    }

    if(!(Test-Path -PathType Container $packageDestinationPath))
    {
        mkdir $packageDestinationPath | Out-Null
    }

    if(!(Test-Path -PathType Container $cachedPackageLocation))
    {
        $failure = "Cached package location {0} is missing. Is your corext cache corrupt?" -f $cachedPackageLocation
        Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Contents" "Error" "$failure" $startPackageTime)
        return
    }

    try
    {
        # Exclude .tracker files created by corext--see http://co1vmtfsat01a:8080/web/wi.aspx?pcguid=22f9acc9-569a-41ff-b6ac-fac1b6370209&id=1173002 for details
        # Exclude [Content_Types].xml created by nuget v3
        # Exclude any .devconsole.* files added by CoreXT
        $files = (dir -File $cachedPackageLocation | ? Name -notmatch '^(\.tracker|\.tracker\.backup|\[Content_Types\]\.xml|ExpectedFileList\.txt|\.devconsole\..*)$' )
    }
    catch
    {
        $failure = "Could not enumerate files for {0} - {1}. Is your corext cache corrupt?" -f $cachedPackageLocation, $_.Exception.ToString()
        Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Contents" "Error" "$failure" $startPackageTime)
        return
    }
    $count = 0
    $filesLength = $files.Length
    foreach($file in $files)
    {
        $count++
        
        $link = "$packageDestinationPath\$file"
        $target = "$cachedPackageLocation\$file"
        if(!(Get-AreFilesLinked $link $target))
        {
            if (Test-IntervalPassed($ProgressInterval)) 
            {
                Write-Progress -Activity "Linking files" -PercentComplete (($count/$filesLength)*100) -CurrentOperation $file -Status ("{0:P1} complete" -f ($count/$filesLength)) -ParentId $ProgressId 
            }
            if(Test-Path -PathType Leaf $link)
            {
                $result = Remove-Link $link
                if(!($result['Success']))
                {
                    $failure = "Could not remove file link for {0} - {1}" -f $file, [string]$result['Output']
                    break
                }
            }
            try
            {
                $result = Create-FileLink $link $target $useHardLinks
                if(!($result.Success))
                {
                    $failure = "Could not create file link for {0} - {1}" -f $file, [string]$result['Output']
                    break
                }
                else
                {
                    $linkedAnything = $true
                }
            }
            catch
            {
                $failure = "Could not create file link for {0} - {1}" -f $file, $_.Exception.ToString()
                break
            }
        }
    }
    Write-Progress -Activity "Linking files" -Completed -ParentId $ProgressId
    if($failure -eq $null)
    {
        $count = 0;
        try
        {
            $folders = (dir -Directory $cachedPackageLocation)
        }
        catch 
        {
            $failure = "Could not enumerate folders for {0} - {1}. Is your corext cache corrupt?" -f $cachedPackageLocation, $_.Exception.ToString()
            break
        }
        $foldersLength = $folders.Length
        foreach($folder in $folders)
        {
            $count++
    
            if((Get-LinkTarget "$packageDestinationPath\$folder") -ne "$cachedPackageLocation\$folder")
            {
                if (Test-IntervalPassed($ProgressInterval))
                {
                    Write-Progress -Activity "Linking folders" -PercentComplete (($count/$foldersLength)*100) -CurrentOperation $folder -Status ("{0:P1} complete" -f ($count/$foldersLength)) -ParentId $ProgressId
                }
                if(Test-Path -PathType Container $packageDestinationPath\$folder)
                {
                    $result = (Remove-Link $packageDestinationPath\$folder)
                    if(!($result['Success']))
                    {
                        $failure = "Could not remove folder link for {0} - {1}" -f $folder, [string]$result['Output']
                        break
                    }
                }
                try
                {
                    $result = Create-FolderLink $packageDestinationPath\$folder $cachedPackageLocation\$folder
                    if(!($result.Success))
                    {
                        $failure = "Could not create folder link for {0} - {1}" -f $folder, [string]$result['Output']
                        break
                    }
                    else
                    {
                        $linkedAnything = $true
                    }
                }
                catch
                {
                    $failure = "Could not create folder link for {0} - {1}" -f $folder, $_.Exception.ToString()
                    break
                }
            }
        }
        Write-Progress -Activity "Linking folders" -Completed -ParentId $ProgressId
    }
    
    if($failure -ne $null)
    {
        Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Contents" "Error" "$failure" $startPackageTime)
    }
    elseif($linkedAnything -eq $false)
    {
        Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Contents" "Skipped" "" $startPackageTime)
    }
    else
    {
        Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Contents" "Success" "" $startPackageTime)
    }
}

function Link-PackageRootToSourceDestination($packageName, $packageDestinationPath, $cachedPackageLocation)
{
    $startPackageTime = Get-Date
    $linkTarget = Get-LinkTarget $packageDestinationPath

    if((Test-Path $packageDestinationPath) -and $linkTarget -eq $cachedPackageLocation)
    {
        Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Direct" "Skipped" "" $startPackageTime)
    }
    else
    {
        $failure = $null
        $result = Remove-AnyLinkedParentFolders $packageDestinationPath
        if(!($result['Success']))
        {
            Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Direct" "Error" ("Could not remove folder link for {0} - {1}" -f $packageDestinationPath, [string]$result['Output']) $startPackageTime)
            return
        }

        # If the parent folder of the destination does not exist, make 
        # sure to create it, otherwise the subsequent call to mklink will not work.
        if(!(Test-Path -PathType Container $packageDestinationPath\..))
        {
            mkdir $packageDestinationPath\.. | Out-Null
        }
        elseif (Test-Path -PathType Container $packageDestinationPath)
        {
            $result = Remove-Link $packageDestinationPath
            if(!($result['Success']))
            {
                Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Direct" "Error" ("Could not remove folder link for {0} - {1}" -f $packageDestinationPath, [string]$result['Output']) $startPackageTime)
                return
            }
        }

        $result = Create-FolderLink $packageDestinationPath $cachedPackageLocation
        if($result.Success -eq $true)
        {
            Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Direct" "Success" "" $startPackageTime)
        }
        else
        {
            Write-Output (Get-LinkResultObject $packageName $packageDestinationPath $cachedPackageLocation "Direct" "Error" ("Could not create folder link for {0} - {1}" -f $packageDestinationPath, [string]$result['Output']) $startPackageTime)
        }
    }
}

function Get-IsPathUnderFolder($folder, $pathToCheck)
{
    if(!$folder)
    {
        throw "Folder parameter is required"
    }
    if(!$pathToCheck)
    {
        throw "Path to check parameter is required"
    }
    $folderFullPath = [IO.Path]::GetFullPath($folder)
    $pathToCheckFullPath = [IO.Path]::GetFullPath($pathToCheck)

    return $pathToCheckFullPath.StartsWith($folderFullPath, [StringComparison]::InvariantCultureIgnoreCase)
}

function Get-IsDestinationAllowed($path)
{
    foreach ($directory in $LinkRoots)
    {
        if((Get-IsPathUnderFolder "$SourceRoot\$directory" "$SourceRoot\$path"))
        {
            return $true
        }
    }
    return $false
}

function Clean-UnexpectedLinks($previousResults)
{
    Write-TelemetryMetricStart "Clean Links"
    Write-Host "Finding and removing links to unused packages"
    $expectedLinks = Get-ExpectedLinks $previousResults
    foreach ($link in (Get-ExistingLinks).FullName | ? { $expectedLinks -notcontains $_ })
    {
        Remove-Link $link | Out-Null
        $parentDirectory = Split-Path $link
        while ((Get-ChildItem $parentDirectory).Count -eq 0)
        {
            Remove-Item $parentDirectory
            $parentDirectory = Split-Path $parentDirectory
        }
    }
    Write-TelemetryMetricFinish "Clean Links"
}

function Get-LinksFromPreviousResult($result)
{
    if($result.Result -ne "Error")
    {
        if($result.Mode -eq "Contents")
        {
            return dir $result.CachedPackageLocation | % { "{0}\{1}" -f $result.PackageDestinationPath, $_.Name }
        }
        else
        {
            return $result.PackageDestinationPath
        }
    }
}

function Get-ExpectedLinks($previousResults)
{
    if ($previousResults)
    {
        $previousResults | % { Get-LinksFromPreviousResult $_ }
    }
    else
    {
        ,@() #leading comma is intended--see http://stackoverflow.com/questions/18476634/powershell-doesnt-return-an-empty-array-as-an-array
    }
}

function Get-ExitCode($linkResults)
{
    if ($LinkResults | ? { $_.Result -eq "Error" })
    {
        return 1
    }
    return 0
}

function Write-LinkPackagesTelemetry($linkResults)
{
    try
    {
        if ($linkResults)
        {
            $errorResults = @($linkResults | ? { $_.Result -eq "Error" })
            $skippedCount = @($linkResults | ? { $_.Result -eq "Skipped" } ).Count
            $linkedCount = @($linkResults | ? { $_.Result -eq "Success" } ).Count
            $errorCount = $errorResults.Count

            Write-Telemetry "Packages Linked" $linkedCount
            Write-Telemetry "Packages Skipped" $skippedCount
            Write-Telemetry "Packages Failed" $errorCount
            Write-Telemetry "Packages Processed" ($linkedCount + $skippedCount + $errorCount)

            $errorDetails = $errorResults | Group-Object 'ResultDetails' | % { @{Error=$_.Name;Packages=$($_.Group.PackageName -join ',')} }
            $errorDetails | % {  Write-TelemetryList 'Package Linking Errors' "$($_.Error) ($($_.Packages))" }
        }
        else
        {
            Write-Telemetry "Packages Processed" 0
        }
        Write-Telemetry "Init Version" "1.1"
    }
    catch
    {
        echo $_ | Format-List * -Force | Out-File (Get-LocalLogFile)
    }
}

function Generate-PkgOutFiles()
{
    $packages = Get-InstalledPackagesFromIncFile

    # Get all the unversioned aliases for packages. Since the unversioned alias will be the
    # shortest name for each package, sorting by name will cause each unversioned alias
    # to appear before the versioned aliases during enumeration. Then we simply capture
    # each alias the first time we see its value
    $properties = @{}
    foreach ($entry in $packages.GetEnumerator() | sort Key)
    {
        if (!$properties.ContainsValue($entry.Value))
        {
            $properties[$entry.Key] = $entry.Value
        }
    }
    Create-BatchCmdFiles $properties
}

if ($IsUnderTest)
{
    exit 
}

$ScriptTotalTime = Measure-Command {

    # The function calls below aren't needed when this script is invoked by init.ps1 because that script
    # does this (and more) for you. However, when the script is invoked directly (when debugging for example)
    # that hasn't been done so these calls ensure that state is configured.
    Set-RequiredEnvironmentVariables
    Set-GlobalVariables
    Initialize-RequiredFolders

    $ProgressId = 1
    $ProgressInterval = 150    # Milliseconds between progress updates
    
    $LogFile = Get-LocalLogFile

    $LinkResults = Link-PackagesToSource

    Clean-UnexpectedLinks $LinkResults

    $LinkResults | Out-File $LogFile -Encoding utf8

    Generate-PkgOutFiles

    Write-LinkPackagesTelemetry $LinkResults
}

Write-Host "Total execution time for linking: $ScriptTotalTime"
if ($LinkResults)
{
    Write-Host "See detailed log at $LogFile"
}
exit (Get-ExitCode $LinkResults)
