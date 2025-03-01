# Inject Drivers into Windows ISO

## Overview

This PowerShell script allows you to modify a Windows ISO by injecting drivers and creating a new ISO file. It mounts a Windows ISO, extracts its `install.wim` file, optionally injects drivers, and rebuilds the ISO with the modifications. The script supports splitting large `install.wim` files for FAT32 compatibility and works for both Windows 10 and Windows 11 ISOs.

## Prerequisites

- Windows ADK Deployment Tools must be installed.
- The script must be run with Administrator privileges.
- Ensure sufficient disk space for temporary files and the modified ISO.

## Usage

```powershell
.\InjectDriversToISO.ps1 -IsoPath "C:\WindowsISO\Win10.iso" -NewIso "C:\NewISO\Win10_Modified.iso" -Bitness amd64 -InjectLocalDrivers
```

## Parameters

| Parameter                          | Description                                                                                   |
| ---------------------------------- | --------------------------------------------------------------------------------------------- |
| `-IsoPath` *(Required)*            | Path to the original Windows ISO file.                                                        |
| `-NewIso` *(Required)*             | Path where the new modified ISO should be saved.                                              |
| `-WorkingDirectory` *(Optional)*   | Directory used for temporary operations (Default: `C:\TEMP_WorkingDirectory`).                |
| `-MountFolder` *(Optional)*        | Directory where the `install.wim` image will be mounted (Default: `C:\TEMP_MountFolder`).     |
| `-IsoFolder` *(Optional)*          | Directory where ISO files will be extracted before rebuilding (Default: `C:\TEMP_IsoFolder`). |
| `-Bitness` *(Required)*            | Architecture of the Windows ISO (`arm64`, `amd64`, `x86`).                                    |
| `-InjectLocalDrivers` *(Optional)* | Extracts and injects local drivers from the current system.                                   |
| `-DriversPath` *(Optional)*        | Path to a folder containing `.inf` driver files to inject.                                    |
| `-Fat32` *(Optional)*              | Ensures compatibility with FAT32 by splitting large `install.wim` files.                      |
| `-NoCleanup` *(Optional)*          | Prevents the removal of temporary working directories after execution.                        |

## Examples

### Inject Local Drivers

```powershell
.\InjectDriversToISO.ps1 -IsoPath "C:\WindowsISO\Win10.iso" -NewIso "C:\NewISO\Win10_Modified.iso" -Bitness amd64 -InjectLocalDrivers
```

This command injects the system's local drivers into a Windows 10 ISO.

### Inject Drivers from a Folder

```powershell
.\InjectDriversToISO.ps1 -IsoPath "C:\WindowsISO\Win10.iso" -NewIso "C:\NewISO\Win10_Modified.iso" -Bitness amd64 -DriversPath "C:\Drivers"
```

This command injects drivers from a specified folder into the Windows 10 ISO.

### Ensure FAT32 Compatibility

```powershell
.\InjectDriversToISO.ps1 -IsoPath "C:\WindowsISO\Win11.iso" -NewIso "C:\NewISO\Win11_Modified.iso" -Bitness amd64 -DriversPath "C:\Drivers" -Fat32
```

This command ensures FAT32 compatibility by splitting the `install.wim` file.

## Notes

- The script verifies if the Windows ADK Deployment Tools are installed.
- Requires administrator privileges.
- Large `install.wim` files may need splitting for FAT32 compatibility.
- Compatible with both Windows 10 and Windows 11 ISOs.

## License

This script is provided as-is, without warranty of any kind. Use at your own risk.

