param (
    [Parameter(Mandatory = $true)]
    [string]$ISOPath,

    [Parameter(Mandatory = $true)]
    [string]$PPKGPath,

    [string]$MountPath = "C:\ISOMount",
    [string]$ImagePath = "C:\WinImage",
    [string]$NewISOPath = "C:\ModifiedWindows.iso"
)

function Mount-ISO {
    param([string]$ISO)
    $mountResult = Mount-DiskImage -ImagePath $ISO -PassThru
    Start-Sleep -Seconds 5
    $DriveLetter = ($mountResult | Get-Volume).DriveLetter
    if (-not $DriveLetter) {
        throw "Failed to mount ISO"
    }
    return "$DriveLetter`:"
}

function Unmount-ISO {
    param([string]$ISO)
    Dismount-DiskImage -ImagePath $ISO
}

function Extract-WIM {
    param([string]$ISOPath, [string]$Destination)
    Write-Host "Copying ISO contents to $Destination..."
    robocopy "$ISOPath" "$Destination" /E > $null
    if (!(Test-Path "$Destination\sources\install.wim") -and (Test-Path "$Destination\sources\install.esd")) {
        Write-Host "Converting install.esd to install.wim..."
        dism /Export-Image /SourceImageFile:"$Destination\sources\install.esd" /SourceIndex:1 /DestinationImageFile:"$Destination\sources\install.wim" /Compress:max
        Remove-Item "$Destination\sources\install.esd" -Force
    }
}

function Mount-WIM {
    param([string]$WIMPath, [string]$MountDir)
    dism /Mount-Image /ImageFile:$WIMPath /Index:1 /MountDir:$MountDir
}

function Inject-PPKG {
    param([string]$MountDir, [string]$PPKG)
    dism /Image:$MountDir /Add-ProvisioningPackage /PackagePath:$PPKG
}

function Unmount-WIM {
    param([string]$MountDir, [string]$WIMPath)
    dism /Unmount-Image /MountDir:$MountDir /Commit
}

function Create-ISO {
    param([string]$SourcePath, [string]$OutputISO)
    $oscdimg = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    if (!(Test-Path $oscdimg)) {
        throw "Oscdimg.exe not found! Install Windows ADK."
    }
    & $oscdimg -m -o -u2 -bootdata:2#p0,e,b"$SourcePath\boot\etfsboot.com"#pEF,e,b"$SourcePath\efi\microsoft\boot\efisys.bin" "$SourcePath" "$OutputISO"
}

# MAIN PROCESS
try {
    Write-Host "Mounting ISO..."
    $isoDrive = Mount-ISO -ISO $ISOPath

    Write-Host "Extracting install.wim..."
    Extract-WIM -ISOPath $isoDrive -Destination $ImagePath

    Write-Host "Mounting install.wim..."
    Mount-WIM -WIMPath "$ImagePath\sources\install.wim" -MountDir $MountPath

    Write-Host "Injecting provisioning package..."
    Inject-PPKG -MountDir $MountPath -PPKG $PPKGPath

    Write-Host "Unmounting install.wim..."
    Unmount-WIM -MountDir $MountPath -WIMPath "$ImagePath\sources\install.wim"

    Write-Host "Creating new ISO..."
    Create-ISO -SourcePath $ImagePath -OutputISO $NewISOPath

    Write-Host "Unmounting ISO..."
    Unmount-ISO -ISO $ISOPath

    Write-Host "New ISO created at: $NewISOPath"
} catch {
    Write-Host "Error: $_"
} finally {
    if (Test-Path $MountPath) { Remove-Item -Path $MountPath -Recurse -Force }
    if (Test-Path $ImagePath) { Remove-Item -Path $ImagePath -Recurse -Force }
}