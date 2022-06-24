#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

. "$PSScriptRoot\Environment.ps1"
. "$PSScriptRoot\GeneralUtilities.ps1"

#
# Test-PackageLinks is designed to test the output from Get-PackageLinks--it depends on the package sorting that function performs.
# This function should only be invoked AFTER $packages have been downloaded to the nuget cache--it queries the cache for the contents
# of any content-linked $packages.
#
function Test-PackageLinks($packages, $locations)
{
    $contentItems = @{}; $contentFolders = @{}; $contentLinked = @{}; $directLinked = @{}
    # Square brackets must be escaped as they are used for range globbing in powershell
    $excludeFiles = @('.tracker', 'ExpectedFileList.txt','`[Content_Types`].xml','.devconsole.*', '.tracker.backup')
    
    foreach ($package in $packages)
    {
        # Cannot link 2 packages at the same location when one is direct-linked--the 2nd one will replace the 1st one at package link time
        if ($directLinked[$package.link])
        {
            throw [NotSupportedException] "Cannot link $($package.id) to $($package.link) because $($directLinked[$package.link]) is direct-linked at $($package.link)"
        }

        if ($contentLinked[$package.link])
        {
            # Cannot link 2 packages at the same location when one is direct-linked--the 2nd one will replace the 1st one at package link time
            if (-not $package.mode -or $package.mode -eq 'direct')
            {
                throw [NotSupportedException] "Cannot link $($contentLinked[$package.link] -join ',') to $($package.link) because $($package.id) is direct-linked at $($package.link)"
            }
            # Cannot content-link 2 packages at the same location if there is any overlapping content--the 2nd will replace the 1st at package link time
            # Note that we don't need to recurse here because top-level subfolders are direct-linked to the cache--we don't recursively link those
            $packageContent = (dir (Get-PackageLocation $package.id $locations) -Exclude $excludeFiles).Name
            if ($packageContent)
            {
                foreach ($packageId in $contentLinked[$package.link])
                {
                    if (-not $contentItems.ContainsKey($packageId))
                    {
                        $contentItems[$packageId] = (dir (Get-PackageLocation $packageId $locations) -Exclude $excludeFiles).Name
                    }
                    if ($contentItems[$packageId])
                    {
                        $overlap = Compare-Object $packageContent $contentItems[$packageId] -IncludeEqual -ExcludeDifferent
                        if ($overlap)
                        {
                            throw [NotSupportedException] "Cannot link $($package.id) to $($package.link) because $packageId links to $($package.link) and both have item(s) $($overlap.InputObject -join ',')"
                        }
                    }
                }
            }
        }

        for ($path = Split-Path $package.link -Parent; $path.Length -gt 0; $path = Split-Path $path -Parent)
        {
            # Cannot link a package under a direct-linked package--the outer package will be unlinked before the inner package is linked
            if ($directLinked[$path])
            {
                throw [NotSupportedException] "Cannot link $($package.id) to $($package.link) because $($directLinked[$path]) is direct-linked at $path"
            }
            # Cannot link a package under a subfolder in a content-linked package--subfolder is direct-linked to the cache and
            # will be unlinked before the inner package is linked
            foreach ($packageId in $contentLinked[$path])
            {
                if (-not $contentFolders.ContainsKey($packageId))
                {
                    $contentFolders[$packageId] = (dir (Get-PackageLocation $packageId $locations) -Directory).Name
                }
                $folderLink = $contentFolders[$packageId] | % { Join-Path $path $_ } | ? { $package.link -eq $_ -or $package.link -like "$_\*" }
                if ($folderLink)
                {
                    throw [NotSupportedException] "Cannot link $($package.id) to $($package.link) because $packageId has direct-linked subfolder $folderLink"
                }
            }
        }

        if (-not $package.mode -or $package.mode -eq 'direct')
        {
            $directLinked[$package.link] = $package.id
        }
        elseif ($package.mode -eq 'contents')
        {
            if ($contentLinked.ContainsKey($package.link))
            {
                $contentLinked[$package.link] += $package.id
            }
            else
            {
                $contentLinked[$package.link] = @($package.id)
            }
        }
        elseif ($package.mode -ne 'skip')
        {
            throw [NotSupportedException] "Cannot link $($package.id) to $($package.link) because link mode '$($package.mode)' is unsupported"
        }
    }
}

function Get-PackageLinkPath($packageId)
{
    [xml]$xml = Get-Content $CoreXtConfigFile
    $linkPath = ($xml.corext.packages.package | ? { $_.id -eq $packageId }).link
    return Join-Path (Get-SourceRoot) $linkPath
}

function Get-PackageLinks
{
    [xml]$xml = Get-Content $CoreXtConfigFile
    $profiles = Get-CoreXTProfiles (Get-CoreXTRawProfiles $xml)
    return Select-PackageLinks $xml $profiles
}

function Get-CoreXTProfiles($profiles)
{
    return $profiles | % { Get-CoreXTProfile $_ }
}

function Get-CoreXTProfile($profileXmlElement)
{
    if (Test-CoreXTProfileV3Schema $profileXmlElement)
    {
        return @{
            IncludeIds = $profileXmlElement.include.id | Skip-Null | % { $_.Trim() }
            IncludeTags = $profileXmlElement.include.tag | Skip-Null | % { $_.Trim() }
            ExcludeIds = $profileXmlElement.exclude.id | Skip-Null | % { $_.Trim() }
            ExcludeTags = $profileXmlElement.exclude.tag | Skip-Null | % { $_.Trim() }
        }
    }
    return @{
        IncludeIds = $profileXmlElement.includeIds -split ",\s*"
        IncludeTags = (($profileXmlElement.includeTags -split ",\s*") + ($profileXmlElement.include -split ",\s*"))
        ExcludeIds = $profileXmlElement.excludeIds -split ",\s*"
        ExcludeTags = (($profileXmlElement.excludeTags -split ",\s*") + ($profileXmlElement.exclude -split ",\s*"))
    }
}

function Test-CoreXTProfileV3Schema($profileXmlElement)
{
    $guidance = "profile data must be defined using only elements (preferred) or only attributes"
    if ($profileXmlElement.include -is [Xml.XmlElement] -or $profileXmlElement.exclude -is [Xml.XmlElement])
    {
        if ($profileXmlElement.include -and $profileXmlElement.include -isnot [Xml.XmlElement])
        {
            throw "The $($profileXmlElement.name) profile contains an exclude element and an include attribute: $guidance"
        }
        if ($profileXmlElement.exclude -and $profileXmlElement.exclude -isnot [Xml.XmlElement])
        {
            throw "The $($profileXmlElement.name) profile contains an include element and an exclude attribute: $guidance"
        }
        if ($profileXmlElement.includeIds)
        {
            throw "The $($profileXmlElement.name) profile contains an include or exclude element and an includeIds attribute: $guidance"
        }
        if ($profileXmlElement.includeTags)
        {
            throw "The $($profileXmlElement.name) profile contains an include or exclude element and an includeTags attribute: $guidance"
        }
        if ($profileXmlElement.excludeIds)
        {
            throw "The $($profileXmlElement.name) profile contains an include or exclude element and an excludeIds attribute: $guidance"
        }
        if ($profileXmlElement.excludeTags)
        {
            throw "The $($profileXmlElement.name) profile contains an include or exclude element and an excludeTags attribute: $guidance"
        }
        return $true
    }
    return $false
}

function Get-CoreXTRawProfiles([xml]$xml)
{
    $profileNames = Get-CoreXTProfileNames
    $profiles = @($xml.corext.profiles.profile | ? { $profileNames -contains $_.name })
    if (!$profiles)
    {
        if ($xml.corext.profiles.profile)
        {
            $currentProfile = $profileNames -join ","
            $lines = @( "$CoreXtConfigFile does not contain any profile data for the '$currentProfile' profile(s).",
                        "These are the profiles that can be selected:"
                        )
            $xml.corext.profiles.profile | % { $lines += "`t" + $_.name }
            throw $lines -join [Environment]::NewLine
        }
        throw "$CoreXtConfigFile does not contain any profiles."
    }
    return $profiles
}

function Select-PackageLinks([xml]$xml, $profiles)
{
    # The XML format here looks like 
    # <corext>
    #  <packages>
    #    <package id="name" version="version" link="subfolder\subfolder" mode="contents" tags="tag1,tag2"/>
    #
    #   ...
    #   </packages>
    # </corext>
    # So we want to return a list of the requested links which will have the xml
    # attributes as properties

    # Unlinked packages are valid, but we are only processing linked packages
    $linkedPackages = $xml.corext.packages.package | ? { $_.link }

    # Sorting by link so we can prevent cache corruption later by preventing bad links
    return Select-Packages $linkedPackages $profiles | sort @{Expression={$_.link}}
}

function Select-Packages($packages, $filteringBehaviors)
{
    foreach ($package in $packages)
    {
        if (Select-Package $package $filteringBehaviors)
        {
            Write-Output $package
        }
    }
}

function Select-Package($package, $filteringBehaviors)
{
    foreach ($filteringBehavior in $filteringBehaviors)
    {
        if ((Filter-PackageByProfile $package $filteringBehavior) -eq $true)
        {
            return $true
        }
    }
    return $false
}

function Filter-PackageByProfile($package, $filteringBehavior)
{

    foreach ($id in $filteringBehavior.ExcludeIds)
    {
        if($package.id -like $id) 
        {
            return $false
        }
    }
    if ($package.tags)
    {
        $tags = $package.tags -split ",\s*"
        foreach ($tag in $filteringBehavior.ExcludeTags)
        {
            if ($tags -contains $tag)
            {
                return $false
            }
        }
        foreach ($tag in $filteringBehavior.IncludeTags)
        {
            if ($tags -contains $tag)
            {
                return $true
            }
        }
    }
    foreach ($id in $filteringBehavior.IncludeIds)
    {
        if ($package.id -like $id)
        {
            return $true
        }
    }
    return $false
}

function Remove-PackagesNotUsedByCoreXTProfileInXmlElement([xml]$xml)
{
    $valid = @{}
    $profiles = Get-CoreXTProfiles (Get-CoreXTRawProfiles $xml)

    Select-Packages $xml.corext.packages.package $profiles | % { $valid[$_.id] = 1 }

    #Find package nodes that weren't selected and remove them from the packages node (We don't have the ReplaceAll XElement method on XmlElement class)
    $exclude = $xml.corext.packages.package | ? { !$valid[$_.id] }
    $exclude | % { $xml.corext.packages.RemoveChild($_) } | Out-Null
}

function Update-RepositoryForLocation([xml]$xml, $xmlFileName)
{
    if ($xml.corext.repositories.default -or $xml.corext.repositories.buildagent)
    {
        if ($xml.corext.repositories.buildagent -and (Get-NonInteractive))
        {
            $default = $xml.corext.repositories.buildagent
            $source = 'buildagent'
        }
        else
        {
            $default = $xml.corext.repositories.default
            $source = 'default'
        }
        if ($env:CoreXTRepoName)
        {
            $repo = $xml.corext.repositories.repo | ? { $_.name -eq $env:CoreXTRepoName } | select -First 1
            if (!$repo)
            {
                $warning = "Cannot find a repo element with name '{0}' (from %CoreXTRepoName%) in {1}--defaulting to '{2}'"
                Write-Warning ($warning -f $env:CoreXTRepoName, $xmlFileName, $default)
            }
        }
        if (!$repo)
        {
            $repo = $xml.corext.repositories.repo | ? { $_.name -eq $default } | select -First 1
        }
        if (!$repo)
        {
            $warning = "Cannot find a repo element with name '{0}' (from $source) in {1} --package download times may suffer until this is fixed"
            Write-Warning ($warning -f $default, $xmlFileName)
        }
        else
        {
            $xml.corext.repositories.repo | ? { $_.name -ne $repo.name } | % { $xml.corext.repositories.RemoveChild($_) } | Out-Null
            $xml.corext.repositories.RemoveAttribute("default")
            $xml.corext.repositories.RemoveAttribute("buildagent")
        }
    }
}
