<#
.SYNOPSIS
    This script modifies a Windows ISO by injecting drivers and creating a new ISO file.

.DESCRIPTION
    The script mounts a Windows ISO, extracts its install.wim file, optionally injects drivers,
    and rebuilds the ISO with the modifications. It supports splitting large install.wim files for FAT32 compatibility.
    This script works for both Windows 10 and Windows 11 ISOs.

.PARAMETER IsoPath
    The path to the original Windows ISO file.

.PARAMETER NewIso
    The path where the new modified ISO should be saved.

.PARAMETER WorkingDirectory
    (Optional) The directory used for temporary operations. Default: C:\TEMP_WorkingDirectory

.PARAMETER MountFolder
    (Optional) The directory where the install.wim image will be mounted. Default: C:\TEMP_MountFolder

.PARAMETER IsoFolder
    (Optional) The directory where ISO files will be extracted before rebuilding. Default: C:\TEMP_IsoFolder

.PARAMETER Bitness
    The architecture of the Windows ISO. Accepted values: arm64, amd64, x86.

.PARAMETER InjectLocalDrivers
    (Optional) If specified, local drivers from the current system will be extracted and injected into the image.

.PARAMETER DriversPath
    (Optional) If Path to a folder containing drivers (.inf files) is specified those drivers will be to inject into the Windows image.

.PARAMETER Fat32
    (Optional) If specified, the script ensures compatibility with FAT32 by splitting large install.wim files into .swm files.

.PARAMETER NoCleanup
    (Optional) If specified, the script does not remove temporary working directories after execution.

.EXAMPLE
    .\InjectDriversToISO.ps1 -IsoPath "C:\WindowsISO\Win10.iso" -NewIso "C:\NewISO\Win10_Modified.iso" -Bitness amd64 -InjectLocalDrivers

    This command takes an existing Windows 10 ISO, injects the system's local drivers, and saves a new modified ISO.

.EXAMPLE
    .\InjectDriversToISO.ps1 -IsoPath "C:\WindowsISO\Win10.iso" -NewIso "C:\NewISO\Win10_Modified.iso" -Bitness amd64 -DriversPath "C:\Drivers"

    This command takes an existing Windows 10 ISO, injects drivers from the specified folder, and saves a new modified ISO.

.EXAMPLE
    .\InjectDriversToISO.ps1 -IsoPath "C:\WindowsISO\Win11.iso" -NewIso "C:\NewISO\Win11_Modified.iso" -Bitness amd64 -DriversPath "C:\Drivers"

    This command takes an existing Windows 11 ISO, injects drivers from the specified folder, and saves a new modified ISO.

.NOTES
    - Ensure the Windows ADK Deployment Tools are installed before running the script.
    - Administrator privileges are required.
    - Large install.wim files may require splitting for FAT32 compatibility.
    - This script is compatible with both Windows 10 and Windows 11 ISOs.
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$IsoPath,

    [Parameter(Mandatory = $true)]
    [string]$NewIso,

    [Parameter(Mandatory = $false)]
    [string]$WorkingDirectory = "C:\TEMP_WorkingDirectory",

    [Parameter(Mandatory = $false)]
    [string]$MountFolder = "C:\TEMP_MountFolder",

    [Parameter(Mandatory = $false)]
    [string]$IsoFolder = "C:\TEMP_IsoFolder",

    [Parameter(Mandatory = $true)]
    [ValidateSet("arm64", "amd64", "x86")]
    [string]$Bitness,

    [Parameter(Mandatory = $false)]
    [switch]$InjectLocalDrivers,

    [Parameter(Mandatory = $false)]
    [string]$DriversPath,

    [Parameter(Mandatory = $false)]
    [switch]$Fat32,

    [Parameter(Mandatory = $false)]
    [switch]$NoCleanup
)

function Recreate-Folder {
    param (
        [string]$FolderPath,
        [switch]$ExitonFail
    )
    
    if (Test-Path $FolderPath) {
        Write-Host "The folder already exists: $FolderPath. Cleaning it up."
        Remove-Item -Path $FolderPath -Recurse -Force
    }
    
    Write-Host "Creating the folder: $FolderPath"
    $newFolder = New-Item -ItemType Directory -Path $FolderPath -Force -ErrorAction SilentlyContinue
    
    if (!($null -ne $newFolder) -and $ExitonFail) {
        exit 1
    }
}

function Test-AdminRights {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host "This script requires administrator privileges. Please run as Administrator." -ForegroundColor Red
        exit 1
    }
}

# Check if the script is running with elevated privileges
Test-AdminRights

# Checking if the drivers path is specified
if (!$InjectLocalDrivers -and -not $DriversPath) {
    Write-Host "Please specify a driver injection method. [-InjectLocalDrivers] or [-DriversPath] Exiting..."
    exit 0
}

# Check if ADK is installed
$BasePath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools"
$ToolsPath = "$BasePath\$Bitness\oscdimg"
$oscdimg = "$ToolsPath\oscdimg.exe"

if (-not (Test-Path $oscdimg)) {
    Write-Error "Windows ADK is not installed or the installed version does not support the selected bitness. Please install it and try again. Exiting..."
    exit 1
}

# Handle etfsboot path separately based on Bitness
if ($Bitness -eq "arm64") {
    $etfsboot = "$BasePath\amd64\oscdimg\etfsboot.com"
}
else {
    $etfsboot = "$ToolsPath\etfsboot.com"
}

$efisys = "$ToolsPath\efisys.bin"



# Creating the working directory
Write-Host "Creating the working directory" -ForegroundColor Blue
Recreate-Folder -FolderPath $WorkingDirectory

# Creating the mount folder
Write-Host "Creating the mount directory" -ForegroundColor Blue
Recreate-Folder -FolderPath $MountFolder

# Creating the ISO folder
Write-Host "Creating the ISO folder" -ForegroundColor Blue
Recreate-Folder -FolderPath $IsoFolder

# Handle the new ISO path
if (Test-Path $NewIso -PathType Container) {
    $NewIso = Join-Path $NewIso "newiso.iso"
}
elseif (!(Test-Path $NewIso)) {
    Write-Host "The location '$NewIso' does not exist."
}
elseif (Test-Path $NewIso -PathType Leaf) {
    $response = Read-Host "There is already a file called '$NewIso'. Should it be removed? (Y/N)"
    if ($response -match '^[Yy]$') {
        Remove-Item $NewIso -Force
        Write-Host "The file '$NewIso' has been removed."
    }
    else {
        Write-Host "The file '$NewIso' was not removed."
        exit 1
    }
}

# Mounting the ISO
Write-Host "Mounting the ISO file: $IsoPath" -ForegroundColor Blue
if (Test-Path $IsoPath -PathType Leaf) {
    if ($IsoPath -match "\.iso$") {
        try {
            $MountedDrive = Get-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
            if ($MountedDrive.Attached) {
                $MountedDriveLetter = (Get-Volume -DiskImage $MountedDrive).DriveLetter
            }
            else {
                Mount-DiskImage -ImagePath $IsoPath | Out-Null
                Start-Sleep -Seconds 2
                $MountedDriveLetter = (Get-DiskImage -ImagePath $IsoPath | Get-Volume).DriveLetter
            }
            Write-Host "The ISO file has been mounted to drive: $MountedDriveLetter" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to mount the ISO file."
            exit 1
        }
    }
    else {
        Write-Host "Please pass a valid ISO file path."
        exit 1
    }
}
else {
    Write-Host "The file does not exist."
    exit 1
}


# Copying the install file of the ISO to the working directory
Write-Host "Copying the install file of the ISO to the working directory" -ForegroundColor Blue

If (Test-Path "$($MountedDriveLetter):/sources/install.wim") {
    try {
        Copy-Item -Path "$($MountedDriveLetter):\sources\install.wim" -Destination $WorkingDirectory
        Write-Host "install.wim file copied successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to copy the install file of the ISO to the working directory."
        $_.Exception.Message
        exit 1
    }

}
elseif (Test-Path "$($MountedDriveLetter):/sources/install.esd") {
    dism /Export-Image /SourceImageFile:$($MountedDriveLetter):\sources\install.esd /DestinationImageFile:$WorkingDirectory\install.wim /Compress:max /CheckIntegrity
    if ($LASTEXITCODE -eq 0) {
        Write-Host "install.wim file copied successfully" -ForegroundColor Green
    }
    else {
        Write-Host "Failed to copy the install file of the ISO to the working directory."
        exit 1
    }
}
else {
    Write-Error "The ISO does not contain a WIM or ESD file."
    exit 1
}

#Getting the image index
Write-Host "Getting the image index of the WIM file"-ForegroundColor Blue
dism /Get-WimInfo /WimFile:$WorkingDirectory\install.wim
$EditionIndex = Read-Host "Please enter the index of the image you want to work with."

# Mounting the image
Write-Host "Mounting the image" -ForegroundColor Blue
attrib -r $WorkingDirectory\install.wim
dism /Mount-Image /ImageFile:$WorkingDirectory\install.wim /Index:$EditionIndex /MountDir:$MountFolder
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to mount the image."
    exit 1
}

# Collecting the drivers

Write-Host "Collecting the drivers" -ForegroundColor Blue
if ($InjectLocalDrivers) {
    $ExportedDrivers = Export-WindowsDriver -Online -Destination $WorkingDirectory\Drivers
}
elseif ($DriversPath) {
    Copy-Item -Path $DriversPath -Destination $WorkingDirectory\Drivers -Recurse
}

$CollectedDrivers = Get-ChildItem -Path "$WorkingDirectory\Drivers" -Recurse | Where-Object { -not $_.PSIsContainer -and $_.Extension -in (".inf") }
Write-Host "Collected $($CollectedDrivers.Count) drivers" -ForegroundColor Yellow


Write-Host "Injecting the drivers..." -ForegroundColor Blue
$DISMOutput = Join-Path $WorkingDirectory "DISMOutput.txt"
$DISM = Start-Process DISM.EXE -ArgumentList "/Image:$($MountFolder) /Add-Driver /Driver:$WorkingDirectory\Drivers /Recurse " -NoNewWindow -RedirectStandardOutput $DISMOutput -PassThru
$SameLastLine = $null
Start-sleep -Milliseconds 100
# Parsing the DISM output to show the progress
do {
    $Content = Get-Content $DISMOutput
    $Lastline = $Content[-1]
    if ($Lastline -ne $SameLastLine) {
        $SameLastLine = $Lastline

        if ($Lastline -match "Searching for driver packages to install...") {
            $ProgressParameters = @{
                Activity         = 'Injecting drivers'
                Status           = 'Progress->'
                PercentComplete  = 0
                CurrentOperation = 'Searching for driver packages to install...'
            }
            Write-Progress @ProgressParameters
        }
        elseif ($Lastline -match "Found") {
            $ProgressParameters = @{
                Activity         = 'Injecting drivers'
                Status           = 'Progress->'
                PercentComplete  = 0
                CurrentOperation = "$Lastline"
            }
            Write-Progress @ProgressParameters
        }
        elseif ($Lastline -match "Installing") {
            $ToRemove = $LastLine.split(':') | Select-Object -Last 1
            #remove message
            $LastLine = $LastLine -replace $ToRemove, ""
            #remove "Installing"
            $Lastline = $Lastline -replace "Installing", ""
            #get Drive name
            $Driver = (($Lastline.split('-') | Select-Object -Last 1)).Replace(':', '').trim()
            #get progress
            $Completed = ((($Lastline.split('-') | Select-Object -First 1).trim()).split('of')[0]).trim()
            $Total = ((($Lastline.split('-') | Select-Object -First 1).trim()).split('of')[2]).trim()
            $CompletedPercentage = [math]::Round(($Completed / $Total) * 100)
            $ProgressParameters = @{
                Activity         = 'Injecting drivers'
                Status           = "Progress-> [$Completed/$Total - $CompletedPercentage%]"
                PercentComplete  = $CompletedPercentage
                CurrentOperation = "Installing $Driver"
            }
            Write-Progress @ProgressParameters
        }
        elseif ($Lastline -match "The operation completed successfully") {
            $ProgressParameters = @{
                Activity         = 'Injecting drivers'
                Status           = 'Progress->'
                PercentComplete  = 100
                CurrentOperation = "$Lastline"
            }
            Write-Progress @ProgressParameters
        }
        else {
            $ProgressParameters = @{
                Activity         = 'Injecting drivers'
                Status           = 'Progress->'
                PercentComplete  = 0
                CurrentOperation = "$Lastline"
            }
            Write-Progress @ProgressParameters
        }
    }
} until (
    $DISM.HasExited
)
if ($Lastline -match "The operation completed successfully") {
    Write-Host "Drivers injected successfully" -ForegroundColor Green
    <# Action to perform if the condition is true #>
}
else {
    Write-Host "Failed to inject drivers Check log at the working directory" -ForegroundColor Red
    Exit 1
}

# Unmounting the modified image and committing the changes

Write-Host "Unmounting the modified image and commiting the changes" -ForegroundColor Blue
dism /Unmount-Image /MountDir:$MountFolder /Commit

# Copying the files to the new ISO folder
Write-Host "Creating the updated ISO" -ForegroundColor Blue
robocopy "$($MountedDriveLetter):\" $IsoFolder /E /NFL /NDL /NJH /nc /ns
Copy-Item -Path $WorkingDirectory\install.wim -Destination "$IsoFolder\sources\install.wim" -Force

# Prepare for FAT 32
Write-Host "Preparing for FAT32" -ForegroundColor Blue
### Check if any files are larger than 4GB that that is not install.wim (Most probably wont be needed checking just in case)
$largeFiles = Get-ChildItem -Path $IsoFolder -Recurse -File -ErrorAction SilentlyContinue |
Where-Object { $_.Length -gt 4GB -and $_.Name -ne "install.wim" }
if ($largeFiles) {
    Write-Host "Apart from install.wim The following files are larger than 4GB and may cause issues with FAT32:"
    $largeFiles | Select-Object FullName, Length | Format-Table -AutoSize
    $response = Read-Host "Do you want to continue? (Y/N)"
    if ($response -notmatch '^[Yy]$') {
        Write-Host "Exiting..."
        exit 1
    }
}

### Define the path to the install.wim file
$WimFilePath = "$IsoFolder\sources\install.wim"
$DestinationFolder = "$IsoFolder\sources\"

### Check if the file exists
if (Test-Path $WimFilePath) {
    # Get the file size in bytes
    $FileSize = (Get-Item $WimFilePath).Length
    $FileSizeGB = $FileSize / 1GB

    Write-Host "install.wim size: $FileSizeGB GB"

    # If FAT32 is enabled and the file is larger than 4GB, split it
    if ($Fat32 -and $FileSize -gt 4GB) {
        Write-Host "install.wim is larger than 4GB. Splitting into .swm files..."

        # Run DISM to split the WIM file
        $SplitSizeMB = 3800 # Slightly below 4GB to be safe
        $SwmOutput = Join-Path $DestinationFolder "install.swm"

        dism /Split-Image /ImageFile:$WimFilePath /SWMFile:$SwmOutput /FileSize:$SplitSizeMB

        if ($LASTEXITCODE -eq 0) {
            Write-Host "install.wim successfully split into .swm files."
            Remove-item -Path $WimFilePath -Force -ErrorAction Stop
        }
        else {
            Write-Host "Failed to split install.wim. Check DISM logs for details."
            Exit 1
        }
    }
    else {
        Write-Host "install.wim does not need splitting or FAT32 is not enabled."
    }
}
else {
    Write-Host "install.wim not found at the specified path!"
}



# Creating updated ISO
Write-Host "Builidng the updated ISO" -ForegroundColor Blue
Start-Process -FilePath $oscdimg -ArgumentList @("-bootdata:2#p0,e,b`"$etfsboot`"#pEF,e,b`"$efisys`"", '-u2', '-udfver102', "`"$IsoFolder`"", "`"$NewIso`"") -Wait -NoNewWindow

Dismount-DiskImage -ImagePath $IsoPath | Out-Null
if (!$NoCleanup) {
    Write-Host "Cleaning up..." -ForegroundColor Blue
    Remove-Item -Path $WorkingDirectory -Recurse -Force
    Remove-Item -Path $MountFolder -Recurse -Force
    Remove-Item -Path $IsoFolder -Recurse -Force
}

Write-Host "ISO file updated successfully: $NewIso" -ForegroundColor Green





