#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

<#
.SYNOPSIS 
Cleans links from the enlistment to %NugetMachineInstallRoot% and/or deletes the contents of %NugetMachineInstallRoot%.

.DESCRIPTION
The Clean.ps1 removes links (hard links, symbols links, and directory junctions) between an enlistment and %NugetMachineInstallRoot%
 
.PARAMETER Links
Whether to delete links (default is $false).

.PARAMETER Cache
Whether to delete %NugetMachineInstallRoot% (default is $false).

.INPUTS
None. You cannot pipe objects to Clean.ps1.

.OUTPUTS
None. Clean.ps1 does not generate any output.

.NOTES
If Cache is specified that implies Links as well.

.EXAMPLE
C:\PS> .\Clean.ps1 -Links -WhatIf

Shows what will happen if -Links is used without -WhatIf

.EXAMPLE
C:\PS> .\Clean.ps1 -Cache -WhatIf

Shows what will happen if -Cache is used without -WhatIf

.EXAMPLE
C:\PS> .\Clean.ps1 -Links

Removes links between enlistment and %NugetMachineInstallRoot%

.EXAMPLE
C:\PS> .\Clean.ps1 -Cache

Removes links between enlistment and %NugetMachineInstallRoot% and then removes %NugetMachineInstallRoot%
#>

#Requires -Version 3.0

[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory=$false)]
    [Switch] $Links,
    [Parameter(Mandatory=$false)]
    [Switch] $Cache
)

. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\FastUpdateCheck.ps1"
. "$PSScriptRoot\Common\LinkUtilities.ps1"

Set-Environment

$Folders = @()

if ($Links -or $Cache)
{
    $Folders = Get-LinkRoots | % { Join-Path (Get-SourceRoot) $_ } | ? { Test-Path $_ }
}

if ($Cache)
{
    $Folders += dir -Directory $NugetCache | % { Join-Path $NugetCache $_ }
}

if ($Folders.Count -gt 0)
{
    if ($PSCmdlet.ShouldProcess("Package state hash settings", "Save-Setting"))
    {
        Save-Setting "UnfilteredPackagesStateHash" ""
        Save-Setting "FilteredPackagesStateHash" ""
    }

    $results = @()

    $Folders | % {
        if ($PSCmdlet.ShouldProcess($_, "Remove-Link"))
        {
            Write-Host "Removing $_"
            $result = Remove-Link $_
            $results += @{ Path = $_; Success = $result.Success; Output = $result.Output }
        }
    }

    if ($results.Count -gt 0)
    {
        $errors = @($results | ? { ! $_.Success })
        if ($errors.Count -gt 0)
        {
            $result = New-Object Exception -ArgumentList "Cannot remove $($errors.Count) folder(s): $(($errors).Path -join ',')"
            $errors | % { $result.Data[$_.Path] = -join $_.Output }
            throw $result
        }
    }
}
