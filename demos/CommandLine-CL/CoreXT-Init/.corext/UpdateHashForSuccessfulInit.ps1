#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

#Requires -Version 3.0

. "$PSScriptRoot\Common\GeneralUtilities.ps1"
. "$PSScriptRoot\Common\FastUpdateCheck.ps1"
. "$PSScriptRoot\Common\PackageCache.ps1"

function Set-HashSettings
{
    Save-Setting "UnfilteredPackagesStateHash" (Get-CurrentCoreXtHash -filteredPackagesHash $false)
    Save-Setting "FilteredPackagesStateHash" (Get-CurrentCoreXtHash -filteredPackagesHash $true)

    # TODO: Eventually, this should be its own plugin/provider for init. Right now, we are putting this
    # at the end up UpdateHashForSuccessfulInit.ps1 just to avoid the perf overhead of yet another PS
    # invocation from init.cmd (600ms)

    # TODO: We can probably stop setting these environment variables in init.cmd once we generate this
    # props file, because downstream consumers of these props (razzle/msbuild) can load them from the file.
    # This will require another way to input these settings into the init.cmd logic itself (requires the
    # init refactoring work).
    $propsToGenerate = @{
        # TODO: Is this really needed? Razzle probably needs it so that it can place binaries here by default,
        # but we don't really want end users to have access to this "root" out directory variable. They should
        # instead be referencing specific things under the out directory.
        CoreXTOutPath = $env:BaseOutDir
    
        # Props needed for non-msbuild use cases that want to import generated files in another format
        CoreXTGenPath = (Get-PackageAddressGenDir)
    
        # Props needed for msbuild
        # TODO: these file names should be queried directly from their respective providers.
        # This is difficult today due to the code structure, but should be easier with the init refactoring.
        CoreXTGenPackageListPropsPath = Get-OutFilePath "packageList.props"
        CoreXTGenTfsPropsPath = Get-OutFilePath "tfs.props"
        CoreXTGenGitPropsPath = Get-OutFilePath "git.props"
        CoreXTGenComponentsPropsPath = Get-OutFilePath "components.props"
    }

    # This file contains all of the pointers to init-generated content that we want consumers to use.
    # This is essentially the public interface into the init structure that is created. It should be found
    # by convention at the root of the enlistment so that all tools will be able to locate it.
    Create-MsbuildPropsFile (Join-Path (Get-SourceRoot) "init.props") $propsToGenerate
}

if ($IsUnderTest)
{
    exit 
}

Set-Environment
Set-HashSettings
