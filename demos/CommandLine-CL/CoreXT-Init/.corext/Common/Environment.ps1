# This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
# Please check into Engineering location first before checkin to Product branches

function Load-InitProps()
{
    $directory = [IO.Path]::GetFullPath($PSScriptRoot)
    do
    {
        $file = Join-Path $directory "init.props"
        if (Test-Path $file)
        {
            [xml]$props = Get-Content $file
            foreach ($property in $props.Project.PropertyGroup.ChildNodes)
            {
                Set-Variable -Name $property.Name -Value $property.InnerText -Scope Global
            }
            return
        }
        else
        {
            $directory = Split-Path $directory
        }
    } while ($directory -ne "")
}

function Get-SourceRoot 
{
    if("$env:CoreXTRepoRoot")
    {
        return $env:CoreXTRepoRoot
    }
    else
    {
        return (Resolve-Path (Join-Path (Join-Path $PSScriptRoot "..") ".."))
    }
}

function Get-NugetCachePath
{
    if($env:NugetMachineInstallRoot)
    {
        return $env:NugetMachineInstallRoot
    }

    throw "Could not determine nuget cache location. Was the script run from an environment where init.cmd hasn't been run?"
}

function Get-CoreXtConfigFile
{
    if($env:CoreXtConfigFile)
    {
        $file = $env:CoreXtConfigFile
    }
    else
    {
        $file = Join-Path (Get-ConfigsFolder) "default.config"
    }

    if(!(Test-Path $file))
    {
        throw "Could not find config file at $file. Did init.cmd run successfully?"
    }
    return $file
}

function Get-PackageLinkerOutDir
{
    if($env:PackageLinkerOutDir)
    {
       return $env:PackageLinkerOutDir
    }

    return Join-Path (Get-SourceRoot) "out\pkg"
}

function Get-CoreXtProfileConfigFile
{
    if($env:CoreXtProfileConfigFile)
    {
        return $env:CoreXtProfileConfigFile
    }

    return Join-Path (Get-PackageLinkerOutDir) "Profile.config"
}

function Get-ConfigsFolder 
{
    Join-Path (Get-SourceRoot) ".corext\Configs"
}

function Get-LocalLogFolder
{
    return "$(Get-SpecialFolder('LocalApplicationData'))\devconsole\logs"
}

function Get-LocalLogFile
{
    $guid = [guid]::NewGuid()
    "$(Get-LocalLogFolder)\Init_{0:yyyyMMdd.HHmmssFFF}_$guid.log" -f (Get-Date)
}

function Get-SpecialFolder($specialFolder)
{
    return [Environment]::GetFolderPath($specialFolder)
}

function Set-GlobalVariable($name, $value)
{
    if (!(Test-Path "Variable:$name"))
    {
        Set-Variable -Name $name -Value $value -Scope Global
    }
}

function Set-GlobalVariables()
{
    Set-GlobalVariable "NugetCache" (Get-NugetCachePath)
    Set-GlobalVariable "SourceRoot" (Get-SourceRoot) 
    Set-GlobalVariable "CoreXtConfigFile" (Get-CoreXtConfigFile)
}

function Set-OutputEnvironment()
{
    if (! (Test-Path $env:PackageAddressGenDir))
    {
        mkdir $env:PackageAddressGenDir | Out-Null
    }
    if ($env:InitScope)
    {
        $outputVarSetFile = Join-Path (Get-PackageAddressGenDir) "InitOutputEnvironment_$env:InitScope.cmd"
    }
    else
    {
        $outputVarSetFile = Join-Path (Get-PackageAddressGenDir) "InitOutputEnvironment.cmd"
    }

    if (Test-Path $outputVarSetFile)
    {
        # Remove read-only attribute on file if present
        $file = Get-ChildItem $outputVarSetFile
        if($file.IsReadOnly)
        {
            Write-Host "Removing read-only attribute on'$outputVarSetFile'"
            try
            {
                $file.IsReadOnly = $false
            }
            catch
            {
                # If file is read-only and user doesn't have permission to remove that attribute
                throw "Exception removing read-only attribute on '$file'. $_"
            }
        }
    }

    $code = {
        $outputVarNames = @("CoreXtConfigFile", "NugetMachineInstallRoot", "PackageAddressGenDir", "BaseDir", "BaseOutDir", "CloudBuildToolsFlavor", "COREXT_SKIP_VERSION_FILES_UPDATE")
        if ($CloudBuild)
        {
            $outputVarNames += "Path"
        }
        $outputVarNames | % { "Set {0}={1}" -f $_, (Get-Item env:$_).Value} | Set-Content $outputVarSetFile
    }

   # Bug 182685 results in access denied error. Adding retry to remove intermittent issues if present
   $retry = 0
   $retryTimeouts = @(0.1,2,3)

   do
   {
       try
       {
            Invoke-SynchronizedAccess $outputVarSetFile $code
            $result = $true
       }
       catch
       {
            $result = $false;
            $exception = $_
       }

       $terminationCondition = ($retry -ge $retryTimeouts.Count) -or $result
       if(-not $terminationCondition)
       {
           Write-Host "Retry attempt $retry in $($retryTimeouts[$retry]) seconds"
           Start-Sleep $retryTimeouts[$retry]
           $retry++
       }
   }
   until ($terminationCondition)

   if(-not $result)
   {
        # Exception if user doesn't have write permission for file or if file is locked by another process
        throw "User '$env:USERNAME' cannot write to file '$outputVarSetFile'. $exception"
    }
}

function Get-DefaultNugetMachineInstallRoot()
{
    Join-Path ([IO.Path]::GetPathRoot((Get-SourceRoot))) "NugetCache"
}

function Get-NonInteractive()
{
    # Use OFFICIAL_BUILD_MACHINE or OfficialBuildProfile to detect Build Lab agent
    # Use BUILD_DEFINITIONNAME to detect VSTS Build agent
    # Use TF_BUILD to detect XAML Build agent
    # Use QBUILD_DISTRIBUTED to detect cloud build agent
    return $env:OFFICIAL_BUILD_MACHINE -or ($env:OfficialBuildProfile -eq "true") -or $env:BUILD_DEFINITIONNAME -or $env:TF_BUILD -or $env:QBUILD_DISTRIBUTED
}

function Set-RequiredEnvironmentVariables()
{
    $env:Root = Get-SourceRoot
    $env:BaseDir = $env:Root
    $env:BaseOutDir = Join-Path $env:Root out
    $env:CoreXTConfig = Join-Path $env:Root .corext
    $env:PackageAddressGenDir = Join-Path $env:BaseOutDir gen
    $env:PackageLinkerOutDir = Join-Path $env:BaseOutDir pkg
    if ($CloudBuild)
    {
        $env:BaseDir = Get-SourceRoot
    }

    $env:CloudBuildToolsFlavor = "Dogfood"
    $env:COREXT_SKIP_VERSION_FILES_UPDATE = "true";

    if($env:CoreXTConfigFile -eq $null -or -not (Test-Path $env:CoreXTConfigFile))
    {
        $env:CoreXTConfigFile = Join-Path (Join-Path $env:CoreXTConfig Configs) default.config
    }

    if($env:NugetMachineInstallRoot -eq $null) 
    {
        $env:NugetMachineInstallRoot = Get-DefaultNugetMachineInstallRoot
        & setx NugetMachineInstallRoot $env:NugetMachineInstallRoot /M | Out-Null
        if(Test-Path $env:NugetMachineInstallRoot -PathType Leaf)
        {
            throw "Specified Nuget cache directory at $env:NugetMachineInstallRoot already exists as a file"
        }
        if(!(Test-Path $env:NugetMachineInstallRoot))
        {
            mkdir -Force $env:NugetMachineInstallRoot | Out-Null
        }
        Write-Host "Set NugetMachineInstallRoot to $env:NugetMachineInstallRoot"
    }

    if(Get-NonInteractive)
    {
        $env:Corext_NonInteractive = "1"
    }
}

function Initialize-RequiredFolders
{
    if (!(Test-Path (Get-NugetCachePath)))
    {
        mkdir -Force (Get-NugetCachePath) | Out-Null
    }
    if (!(Test-Path (Get-LocalLogFolder)))
    {
        mkdir -Force (Get-LocalLogFolder) | Out-Null
    }
}

function Test-IsGitEnlistment()
{
    return Test-Path (Join-Path (Get-SourceRoot) ".git")
}

function Set-Environment()
{
    # When we are unit testing outside of a CoreXT environment, these environment variables will not be set.
    # Instead, we should set/mock them as needed for the tests.
    if (-not $global:IsUnderTest)
    {
        Load-InitProps
        Set-RequiredEnvironmentVariables
        Set-OutputEnvironment
        Set-GlobalVariables
        Initialize-RequiredFolders
    }
}
