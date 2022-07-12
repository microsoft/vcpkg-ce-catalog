# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches

. "$PSScriptRoot\GeneralUtilities.ps1"
. "$PSScriptRoot\CoreXtConfig.ps1"

function Write-Telemetry($key, $value)
{
    Append-TelemetryFile "String" $key $value
}

function Write-TelemetryMetricStart($metricName)
{
    Append-TelemetryFile "Start" "$metricName Minutes" ([DateTime]::Now.ToString())
}

function Write-TelemetryMetricFinish($metricName)
{
    Append-TelemetryFile "Finish" "$metricName Minutes" ([DateTime]::Now.ToString())
}

function Write-TelemetryTimestamp($description)
{
    Append-TelemetryFile "String" $description ([DateTime]::Now.ToString())
}

function Write-TelemetryList($description, $value)
{
    Append-TelemetryFile "List" $description $value
}

# Writes out the free disk space for the drive of the given path. If no path is provided, default to the NugetMachineInstallRoot environment variable.
function Write-TelemetryDiskspaceFree($description, $path)
{
    if ([string]::IsNullOrWhitespace($path))
    {
        $path = $Env:NugetMachineInstallRoot
    }
    $drive = (Split-Path -Path $path -Qualifier -ErrorAction Stop)
    $freeSpace = (Get-WmiObject Win32_LogicalDisk -Filter ("DeviceID='" + $drive + "'") | Select-Object FreeSpace).FreeSpace
    Append-TelemetryFile "Bytes" "Disk GB $description" $freeSpace
}

function Write-TelemetryDiskFreeBefore($description, $path)
{
    Write-TelemetryDiskspaceFree "Before $description" $path
}

function Write-TelemetryDiskFreeAfter($description, $path)
{
    Write-TelemetryDiskspaceFree "After $description" $path
}

function Write-TelemetryError([System.Management.Automation.ErrorRecord]$errorRecord)
{
    Write-Telemetry 'Exception Type' $errorRecord.Exception.GetType()
    Write-Telemetry 'Exception Message' $errorRecord.Exception.Message
    foreach ($line in ($errorRecord.ScriptStackTrace -split "`r`n" | ?{ $_ }))
    {
        Write-TelemetryList 'Exception Script StackTrace' $line
    }
    foreach ($line in ($errorRecord.Exception.StackTrace -split "`r`n" | ?{ $_ }))
    {
        Write-TelemetryList 'Exception StackTrace' $line
    }
    foreach ($kvp in $errorRecord.Exception.Data.GetEnumerator())
    {
        Write-TelemetryList 'Exception Data' "$($kvp.Key) => $($kvp.Value)"
    }
}

# Writes an entry out to a telemetry arguments file.
#
# A .arguments file has the following format per line:
# [Event Type];[Key];[Value]
function Append-TelemetryFile($eventType, $key, $value)
{
    if (!(Test-ShouldCollectTelemetry))
    {
        return
    }

    if ([string]::IsNullOrWhitespace($TelemetryArgumentsFile)) 
    {
        Set-UniqueTelemetryFile
    }
    
    Add-Content $TelemetryArgumentsFile ($eventType + ";" + $key + ";" + $(($value -replace ';', '.') -replace "`r`n", "."))
}

function Test-ShouldCollectTelemetry
{
    return -not ((Get-Profile "CollectTelemetry") -eq $false)
}

function Get-TelemetryCachePath
{
    return "$env:LOCALAPPDATA\Telemetry\Cache"
}

function Set-UniqueTelemetryFile
{
    Set-Variable -Name "TelemetryFileGuid" -Value ([Guid]::NewGuid().ToString("D")) -Scope Global

    $path = ("{0}\Telemetry.{1}.arguments" -f (Get-TelemetryCachePath), $TelemetryFileGuid)
   
    Set-Variable -Name "TelemetryArgumentsFile" -Value $path -Scope Global
    $directory = [IO.Path]::GetDirectoryName($TelemetryArgumentsFile)
    [IO.Directory]::CreateDirectory($directory) | out-null
}

function Get-TelemetryKey()
{
    $env = Get-Profile "TelemetryEnvironment"

    switch($env)
    {
        "dev"
        {
            Write-Warning "Using the dev telemetry environment"
            "54057824-15fc-4e9b-ad66-bbaabc085eb9"
        }

        # Default to the production account
        default { "649718d0-a1dd-481f-a0e7-b3cce265347e" }
    }
}

function Upload-CachedTelemetry
{
    # Do not try to upload any data if telemetry collection is currently disabled
    if (Test-ShouldCollectTelemetry)
    {
        # Look for telemetry package
        $packageLocation = Get-PackageLocation Microsoft.DevDiv.Engineering.Telemetry
        if ($packageLocation)
        {
            $uploadTelemetryExePath = Join-Path $packageLocation "\lib\net45\UploadTelemetry.exe"
            Call-UploadTelemetryExe $uploadTelemetryExePath
        }
        else
        {
            throw [IO.FileNotFoundException] "The telemetry package Microsoft.DevDiv.Engineering.Telemetry is not in your CoreXT cache. Make sure default.config contains this package."
        }
    }
    else
    {
        Write-Warning "Telemetry upload is disabled"
    }
}

function Call-UploadTelemetryExe
{
    param(
        [string]$exePath
    )

    if(Test-Path($exePath))
    {
        # Configure telemetry to send to the desired resource
        Write-Telemetry 'InstrumentationKey' (Get-TelemetryKey)
        Write-Verbose "Sending telemetry"
        $arguments = "/file:""$TelemetryArgumentsFile"" /sources:""$(Get-SourceRoot)"" /delete"
        Start-Process -NoNewWindow $exePath $arguments
    }
    else
    {
        Write-Warning "$exePath doesn't exist"
    }
}
