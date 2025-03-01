# Autopilot Device Registration Script

## Overview
This PowerShell script, **Add-AutopilotDevice.ps1**, automates the process of registering a Windows device with Windows Autopilot. It retrieves the device's serial number and hardware hash, imports the device into Microsoft Endpoint Manager using the Microsoft Graph API, and checks the import status.

## Prerequisites
Before running the script, ensure the following requirements are met:
- PowerShell 5.1 or later
- Microsoft Graph PowerShell SDK installed
- Required permissions to register devices in Microsoft Endpoint Manager
- Internet connectivity
- Windows device with administrative privileges

## Installation
1. Open PowerShell as an administrator.
2. Install the Microsoft Graph authentication module if not already installed:
   ```powershell
   Install-Module -Name microsoft.graph.authentication -Scope CurrentUser -Force
   ```

## Usage
To execute the script, run the following command in PowerShell:

```powershell
.\Add-AutopilotDevice.ps1
```

Optionally, you can specify a group tag:
```powershell
.\Add-AutopilotDevice.ps1 -GroupTag "YourGroupTag"
```

### Script Functions
- **`Ensure-Module`**: Ensures the required PowerShell module is installed.
- **`Get-SerialNumber`**: Retrieves the device's serial number.
- **`Get-HardwareHash`**: Retrieves the device's hardware hash.
- **`Add-AutopilotImportedDevice`**: Imports the device into Autopilot using the Microsoft Graph API.
- **`Check-ImportStatus`**: Monitors the registration process until completion.
- **`Register-AutopilotDevice`**: Orchestrates the entire process, connecting to Graph API, retrieving device info, and registering it.

## Logging & Error Handling
- The script logs key actions to the console.
- If errors occur, messages are displayed with relevant details.
- Timeout handling is implemented for checking the import status.

## Troubleshooting
1. **Graph API connection fails**:
   - Ensure you have the correct permissions.
   - Verify internet connectivity.
   - Try running `Connect-MgGraph -UseDeviceCode` separately.

2. **Hardware hash retrieval fails**:
   - Ensure your device supports retrieving the hash.
   - Run PowerShell as an administrator.

3. **Device import does not complete**:
   - Check if the device is already registered.
   - Review the error messages for troubleshooting steps.

## Disclaimer
Use this script at your own risk. Ensure proper permissions and backups before executing it in a production environment.

