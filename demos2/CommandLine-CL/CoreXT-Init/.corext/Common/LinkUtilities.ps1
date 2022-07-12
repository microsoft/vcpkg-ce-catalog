#This script lives in https://devdiv.visualstudio.com/DefaultCollection/Engineering/_git/InitScripts
#Please check into Engineering location first before checkin to Product branches

. "$PSScriptRoot\GeneralUtilities.ps1"

$ReparsePointTargetFinderTypeName = "ReparsePointTargetFinder"

Invoke-CommandWithGlobalGac {
    if (!($ReparsePointTargetFinderTypeName -as [type]))
    {
        Add-Type -TypeDefinition @"
using Microsoft.Win32.SafeHandles;
using System;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using ComTypes = System.Runtime.InteropServices.ComTypes;

public class $ReparsePointTargetFinderTypeName
{
    [Flags]
    private enum EFileAccess : uint
    {
        GenericRead = 0x80000000,
        GenericWrite = 0x40000000,
        GenericExecute = 0x20000000,
        GenericAll = 0x10000000,
    }

    private struct ByHandleFileInfo
    {
        public FileAttributes FileAttributes;
        public ComTypes.FILETIME CreationTime;
        public ComTypes.FILETIME LastAccessTime;
        public ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    private const int ERROR_INSUFFICIENT_BUFFER = 122;
    private const int FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, ref ByHandleFileInfo info);

    [DllImport("Kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern int GetFinalPathNameByHandle(SafeFileHandle handle, [In, Out]StringBuilder filePath, int cchFilePath, int dwFlags);

    [DllImport("Kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string target,
        [MarshalAs(UnmanagedType.U4)] EFileAccess fileAccess,
        [MarshalAs(UnmanagedType.U4)] FileShare fileShare,
        IntPtr securityAttributes,
        [MarshalAs(UnmanagedType.U4)] FileMode fileMode,
        int fileAttributesAndFlags,
        IntPtr templateFileHandle
    );

    [DllImport("Kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern uint QueryDosDevice(string deviceName, StringBuilder buffer, int maxSize);

    private static readonly string DirectorySeparatorString = Path.DirectorySeparatorChar.ToString();

    private string GetDriveTarget(string driveSource)
    {
        for (var buffer = new StringBuilder(100); buffer.Length == 0; buffer.Capacity *= 10)
        {
            if (QueryDosDevice(driveSource, buffer, buffer.Capacity) != 0)
            {
                //path comes back prefixed with \\?\, so get rid of that
                var result = buffer.ToString().TrimStart(Path.DirectorySeparatorChar, '?');
                if (result.StartsWith("Device"))
                {
                    break;
                }
                return result;
            }
            var error = Marshal.GetLastWin32Error();
            if (error != ERROR_INSUFFICIENT_BUFFER)//else continue and increase buffer size
            {
                throw new Win32Exception(error);
            }
        }
        return driveSource;
    }

    private ByHandleFileInfo GetFileInfo(string target)
    {
        ByHandleFileInfo info = new ByHandleFileInfo();
        using (SafeFileHandle handle = OpenExistingFile(target))
            if (!GetFileInformationByHandle(handle, ref info))
                throw new Win32Exception();
        return info;
    }

    private SafeFileHandle OpenExistingFile(string target)
    {
        SafeFileHandle handle = CreateFile(target, EFileAccess.GenericRead, FileShare.Read, IntPtr.Zero, FileMode.Open, 0, IntPtr.Zero);
        if (handle.IsInvalid)
            throw new Win32Exception();
        return handle;
    }

    public bool AreFilesLinked(string source, string target)
    {
        try
        {
            if (File.Exists(target) && File.Exists(source))
            {
                ByHandleFileInfo targetInfo = GetFileInfo(target);
                ByHandleFileInfo sourceInfo = GetFileInfo(source);
                if (sourceInfo.VolumeSerialNumber == targetInfo.VolumeSerialNumber)
                    if (sourceInfo.FileIndexHigh == targetInfo.FileIndexHigh)
                        return sourceInfo.FileIndexLow == targetInfo.FileIndexLow;
            }
            return false;
        }
        catch(Exception)
        {
            return false;
        }
    }

    public string GetLinkTarget(string fileOrFolderPath)
    {
        var fileInfo = new FileInfo(fileOrFolderPath);
        if (!(fileInfo.Exists || Directory.Exists(fileOrFolderPath)))
        {
            throw new InvalidOperationException(String.Format("{0} is missing", fileOrFolderPath));
        }
        if (fileInfo.Attributes.HasFlag(FileAttributes.ReparsePoint))   //fileInfo has correct attributes even if it's a folder
        {
            using (var handle = CreateFile(fileOrFolderPath, EFileAccess.GenericRead, FileShare.ReadWrite, IntPtr.Zero, FileMode.Open, FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero))
            {
                if (handle.IsInvalid)
                {
                    throw new Win32Exception();
                }
                var length = GetFinalPathNameByHandle(handle, null, 0, 0);
                if (length == 0)
                {
                    throw new Win32Exception();
                }
                var path = new StringBuilder(length);
                if (GetFinalPathNameByHandle(handle, path, path.Capacity, 0) == 0)
                {
                    throw new Win32Exception();
                }
                //path comes back prefixed with \\?\ (long filename) and possibly postfixed with \, so get rid of those
                var result = path.ToString().Trim(Path.DirectorySeparatorChar, '?');

                //If fileOrFolderPath is a folder mount point and there's no drive letter for the volume, we get the same path back.
                //If that's the case, don't return that--we want the path only if it resolves to a different location.
                if (!result.Equals(fileOrFolderPath, StringComparison.OrdinalIgnoreCase))
                {
                    return result;
                }
            }
        }
        return String.Empty;
    }

    public string ResolveLinksInPath(string fileOrFolderPath)
    {
        var result = new StringBuilder(Path.GetFullPath(fileOrFolderPath));
        var folderInfo = new DirectoryInfo(result.ToString());
        if (!folderInfo.Exists)
        {
            var fileInfo = new FileInfo(result.ToString());
            if (fileInfo.Exists)
            {
                folderInfo = fileInfo.Directory;
            }
        }
        if (folderInfo.Exists)
        {
            //if drive is a subst drive, resolve that to the actual path
            var driveSource = folderInfo.Root.Name.TrimEnd(Path.DirectorySeparatorChar);
            var driveTarget = GetDriveTarget(driveSource);
            if (driveTarget != driveSource)
            {
                result.Replace(driveSource, driveTarget);
                if (result[result.Length - 1] == Path.DirectorySeparatorChar)
                {
                    var index = result.Length - 2;
                    while (result[index] == Path.DirectorySeparatorChar)
                        index--;
                    result.Length = index + 1;
                }
            }
            //now resolve any other links (e.g. hard links, reparse points and mount points)
            var length = result.Length;
            while (length > 2)  //stop when only the drive is left; already handled that above
            {
                var nextPath = result.ToString(0, length);
                var linkPath = GetLinkTarget(nextPath);
                if (String.IsNullOrWhiteSpace(linkPath))
                {
                    length = nextPath.LastIndexOf(Path.DirectorySeparatorChar);
                }
                else
                {
                    result.Replace(nextPath, linkPath);
                    length = result.Length;
                }
            }
        }
        return result.ToString();
    }
}
"@
    }
}

function Create-FileLink
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        $link, 
        [Parameter(Mandatory=$true)]
        $target, 
        [Parameter(Mandatory=$true)]
        $useHardLinks)
    process
    {
        if($PSVersionTable.PSVersion.Major -ge 5)
        {
            try
            {
                if($useHardLinks -eq $true)
                {
                    if ($pscmdlet.shouldprocess("New-Item -ItemType HardLink -Path $link -Value $target"))
                    {
                        $output = New-Item -ItemType HardLink -Path $link -Value $target -ErrorAction Stop
                        $success = $true
                    }
                }
                else
                {
                    if ($pscmdlet.shouldprocess("New-Item -ItemType SymbolicLink -Path $link -Value $target"))
                    {
                        $output = New-Item -ItemType SymbolicLink -Path $link -Value $target -ErrorAction Stop
                        $success = $true
                    }
                }
            }
            catch
            {
                $output = $_
                $success = $false
            }
        }
        else
        {
            if($useHardLinks -eq $true)
            {
                if ($pscmdlet.shouldprocess("mklink /H $link $target"))
                {
                    $output = cmd /c mklink /H $link $target 2>&1
                    $success = $LASTEXITCODE -eq 0
                }
            }
            else
            {
                if ($pscmdlet.shouldprocess("mklink $link $target"))
                {
                    $output = cmd /c mklink $link $target 2>&1
                    $success = $LASTEXITCODE -eq 0
                }
            }
        }
        return @{"Success" = $success; "Output" = $output}
    }
}

function Should-UseNewItemToCreateFolderLink()
{
    if ($env:UseNewItemToCreateFolderLink -and ($env:UseNewItemToCreateFolderLink -eq "false"))
    {
        return $false
    }
    return ($PSVersionTable.PSVersion.Major -ge 5)
}

function Create-FolderLink
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        $link, 
        [Parameter(Mandatory=$true)]
        $target)
    process
    {
        if ($pscmdlet.shouldprocess("mklink /J $link $target"))
        {
            if(Should-UseNewItemToCreateFolderLink)
            {
                try
                {
                    $output = New-Item -ItemType Junction -Path $link -Value $target -ErrorAction Stop
                    $success = $true
                }
                catch
                {
                    $output = $_
                    $success = $false
                }
            }
            else
            {
                $output = cmd /c mklink /J $link $target 2>&1
                $success = $LASTEXITCODE -eq 0
            } 
            return @{"Success" = $success; "Output" = $output}
        }
    }
}

function Remove-Link
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($path)
    process
    {
        if($path -eq $null)
        {
            return @{"Success" = $false; "Output" = $null }
        }
        try
        {
            if(Test-Path -PathType Container $path)
            {
                if ($pscmdlet.shouldprocess("rmdir /s /q $path")) 
                { 
                    $output = Invoke-Command { cmd /c rmdir /s /q $path 2>&1 }
                    return @{"Success" = !(Test-Path -PathType Container $path); "Output" = $output}
                }
            }
            elseif(Test-Path -PathType Leaf $path)
            {
                if ($pscmdlet.shouldprocess("del $path")) 
                { 
                    try
                    {
                        $output = Remove-Item -Path $path -ErrorAction Stop
                    }
                    catch
                    {
                        $output = $_
                    }
                    $result = !(Test-Path -PathType Leaf $path)

                    # If we can't remove most likely problem is file in use so try to rename it instead.
                    # If that works the file will be left on disk until the process using it is done and
                    # be removed the next time init runs
                    if (!$result -and ($output.CategoryInfo.Category -eq [System.Management.Automation.ErrorCategory]::PermissionDenied))
                    {
                        $headText = 'init-rename'
                        $filename = Split-Path $path -Leaf
                        if ($filename -like "$headText-*") # Only rename if we haven't tried yet
                        {
                            Write-Verbose "Cannot remove $path"
                        }
                        else
                        {
                            $rename = "$headText-$(Get-Random)-$filename"
                            $output = Invoke-Command { cmd /c rename $path $rename 2>&1 }
                            $result = !(Test-Path -PathType Leaf $path)
                            Write-Verbose "Rename $path to $rename : $result"
                        }
                    }

                    return @{"Success" = $result; "Output" = $output}
                }
            }
            else
            {
                return @{"Success" = $true; "Output" = ("{0} is missing" -f $path) }
            }
        }
        catch
        {
            return @{"Success" = $false; "Output" = $_.Exception.Message }
        }
    }
}

function Remove-AnyLinkedParentFolders($path)
{
    if([String]::IsNullOrWhitespace($path) -or ($path -eq $SourceRoot))
    {
        return @{"Success" = $true; "Output" = ""}
    }

    if(Test-Path -Type Container $path)
    {
        $info = [IO.DirectoryInfo]$path
        if($info.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint))
        {
            $result = Remove-Link $path
            if(!($result['Success']))
            {
                return $result
            }
        }
    }

    $upOneFolder = [IO.Path]::GetFullPath("$path\..")
    if ($upOneFolder -eq $path)
    {
        return @{"Success" = $true; "Output" = ""}
    }
    return Remove-AnyLinkedParentFolders($upOneFolder)    
}

function Get-LinkTarget($path)
{
    try
    {
        return $ReparsePointTargetFinder.GetLinkTarget($path)
    }
    catch
    {
        return $null
    }
}

function Get-LinkRoots()
{
    [xml]$links = Get-Content $CoreXtConfigFile
    return $links | % { $_.corext.allowedLinkDestinations.directory }
}

function Get-ExistingLinks()
{
    return Get-LinkRoots | % { Get-FilesAndFolderLinks("$SourceRoot\$_") }
}

function Get-FilesAndFolderLinks($folder)
{
    if (Test-Path $folder)
    {
        $files =  dir -File $folder
        $folders = dir -Directory $folder
        $folderLinks = $folders | ? { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)  }
        if ($files.Count -ne 0) { echo $files }
        if ($folderLinks.Count -ne 0) { echo $folderLinks }
        $folders | ? { !($_.Attributes -band [IO.FileAttributes]::ReparsePoint)  } | % { Get-FilesAndFolderLinks($_.FullName) }
    }
}

function Get-AreFilesLinked($link, $target)
{
    $ReparsePointTargetFinder.AreFilesLinked($link, $target)
}

function Resolve-PathLinks($fileOrFolder)
{
    return $ReparsePointTargetFinder.ResolveLinksInPath($fileOrFolder)
}

function Test-HardLinkCapability()
{
    try
    {
        #Get the folder and volume GUID for all mount points (which includes drive letters)

        $roots = Get-WmiObject 'Win32_MountPoint' | % {

            if (!($_.Directory -match '[a-zA-Z]:\\\\[^"]*')) {
                #Expect a value like 'Win32_Directory.Name="C:\\"' or 'Win32_Directory.Name="C:\\Projects"'
                throw "Cannot extract folder from '{0}'" -f $_.Directory
            }
            $folder = $Matches[0].TrimEnd('\').Replace('\\', '\')    #WMI doubles the backslashes

            if (!$_.Volume) {
                #Expect a value like 'Win32_Volume.DeviceID="\\\\?\\Volume{1cbc2433-acde-44d1-8ed2-c4ddc9b07922}\\"'
                throw "Cannot extract volume from '{0}'" -f $_.Volume
            }
            @{Folder = $folder; Volume = $_.Volume}
        }

        #Find the mount point folders that host $NugetCache and $SourceRoot

        $root1Path = Resolve-PathLinks($NugetCache)
        $root1 = $roots | ? { $root1Path -eq $_.Folder -or $root1Path -like $_.Folder + "\*" } `
                        | sort @{Expression={$_.Folder.Length};Descending=$true} `
                        | select -First 1
        if (!$root1) {
            throw "Cannot find root folder for {0}" -f $NugetCache
        }

        $root2Path = Resolve-PathLinks($SourceRoot)
        $root2 = $roots | ? { $root2Path -eq $_.Folder -or $root2Path -like $_.Folder + "\*" } `
                        | sort @{Expression={$_.Folder.Length};Descending=$true} `
                        | select -First 1
        if (!$root2) {
            throw "Cannot find root folder for {0}" -f $SourceRoot
        }

        return ($root1.Volume -eq $root2.Volume)
    }
    catch
    {
        Write-Warning ("Cannot resolve path links: {0}; falling back to v1 linking behavior" -f $_)
        return ((Get-Item $NugetCache).Root.Name -eq (Get-Item $SourceRoot).Root.Name)
    }
}

$ReparsePointTargetFinder = New-Object $ReparsePointTargetFinderTypeName
