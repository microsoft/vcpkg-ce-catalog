#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

#Requires -Version 3.0
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("chk", "ret")]
    [String[]] $BuildTypes = @("chk"),
    [Parameter(Mandatory=$false)]
    [ValidateSet("cmd", "ps1")]
    [String[]] $ShortcutTypes = @("cmd", "ps1"),
    [Parameter(Mandatory=$false)]
    [Switch] $TargetAllUsers = $false
)

. "$PSScriptRoot\Common\Environment.ps1"


function Get-ShortcutTargetPath([ValidateSet("cmd", "ps1")][String]$razzleType = "ps1")
{
    if ($razzleType -eq "ps1")
    {
        $wowPath = (Join-Path $PSHOME "powershell.exe") -replace "System32", "SysWOW64"
        if (Test-Path $wowPath)
        {
            return $wowPath
        }
        return Join-Path $PSHOME "powershell.exe"
    }

    $cmdPath = Get-SpecialFolder("SystemX86")#SysWOW64
    if (! (Test-Path $cmdPath))
    {
        $cmdPath = Get-SpecialFolder("System")
    }
    return Join-Path $cmdPath "cmd.exe"
}


function Get-ShortcutFile([ValidateSet("chk", "ret")][String]$buildType, [ValidateSet("cmd", "ps1")][String]$razzleType, [Boolean]$targetAllUsers = $false)
{
    if ($targetAllUsers)
    {
        $linkFolder = Get-SpecialFolder("CommonDesktopDirectory")
    }
    else
    {
        $linkFolder = Get-SpecialFolder("DesktopDirectory")
    }
    $linkNameParts = @(Split-Path (Get-SourceRoot) -Leaf)
    if ($razzleType -ne "ps1")
    {
        $linkNameParts += $razzleType
    }
    $linkNameParts += $buildType
    $linkName = $linkNameParts -join "-"
    $linkFile = Join-Path $linkFolder "$linkName.lnk"
    $instance = 1
    while (Test-Path $linkFile)
    {
        $instance++
        $linkFile = Join-Path $linkFolder "$linkName($instance).lnk"
    }
    return $linkFile
}


function Get-ShortcutArgs([ValidateSet("chk", "ret")][String]$buildType, [ValidateSet("cmd", "ps1")][String]$razzleType = "ps1")
{
    $razzleArgs = "$buildType no_oacr"
    if ($buildType -eq "chk")
    {
        $razzleArgs += " no_opt"
    }
    $razzlePath = Join-Path "tools" "razzle.$razzleType"
    if (! (Test-Path (Join-Path (Get-SourceRoot) $razzlePath)))
    {
        $razzlePath = Join-Path "src" $razzlePath
    }
    if ($razzleType -eq "cmd")
    {
        return "/k cd /d `"{0}`" && {1} {2}" -f (Get-SourceRoot), $razzlePath, $razzleArgs
    }
    return "-nologo -noexit -executionpolicy remotesigned -c . {{ cd `"{0}`";.\{1} {2} }}" -f (Get-SourceRoot), $razzlePath, $razzleArgs
}


function Set-RunAsAdmin([String]$shortcutFile)
{
    #set byte 21 bit 6 (0x20) ON (see http://stackoverflow.com/questions/9701840/how-to-create-a-shortcut-using-powershell)
    $bytes = [IO.File]::ReadAllBytes($shortcutFile)
    $bytes[21] = $bytes[21] -bor 0x20
    [IO.File]::WriteAllBytes($shortcutFile, $bytes)
}


if ($IsUnderTest)
{
    exit
}

if (! (Test-IsGitEnlistment))
{
    throw "Shortcut creation is not supported for TFS workspaces. Please use tfpt creatshortcut instead."
}

foreach ($buildType in $BuildTypes)
{
    foreach ($shortcutType in $ShortcutTypes)
    {
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcutFile = Get-ShortcutFile $buildType $shortcutType $TargetAllUsers
        $shortcut = $wshShell.CreateShortcut($shortcutFile)
        $shortcut.TargetPath = Get-ShortcutTargetPath $shortcutType
        $shortcut.Arguments = Get-ShortcutArgs $buildType $shortcutType
        $shortcut.Save()
        Set-RunAsAdmin $shortcutFile
        Write-Host "Created $shortcutFile"
    }
}
