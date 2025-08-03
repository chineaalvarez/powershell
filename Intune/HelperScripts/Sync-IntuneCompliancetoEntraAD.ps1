<#
.SYNOPSIS
Checks compliance mismatches between Intune and Azure AD devices and optionally updates compliance status in Azure AD.

.DESCRIPTION
This script compares the compliance state of Intune-managed devices with their corresponding Azure AD device records.
It identifies mismatches and allows the user to select which devices should have their Azure AD compliance state updated to reflect the Intune status.

Optionally, you can use the -LogToCsv switch to export three CSV reports:
1. ComplianceMismatchDevices.csv — All devices with mismatched compliance status
2. SelectedDevicesForUpdate.csv — Devices selected for update via Out-GridView
3. SuccessfullyUpdatedDevices.csv — Devices that were successfully patched via Microsoft Graph

The CSV files will be saved in the current working directory.

.PARAMETER LogToCsv
Optional switch. If used, the script will export the three CSV reports listed above to the current directory.
If not used, no logs will be written.

.EXAMPLE
.\Sync-ComplianceStatus.ps1

Runs the script interactively and shows mismatched devices in Out-GridView without writing any logs.

.EXAMPLE
.\Sync-ComplianceStatus.ps1 -LogToCsv

Runs the script interactively and saves 3 CSV files to the current folder:
- ComplianceMismatchDevices.csv
- SelectedDevicesForUpdate.csv
- SuccessfullyUpdatedDevices.csv

#>

param (
    [switch]$LogToCsv
)

#Requires -Module Microsoft.Graph.DeviceManagement
#Requires -Module Microsoft.Graph.Devices

# Connect if not already connected
if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes 'Device.Read.All', 'DeviceManagementManagedDevices.Read.All'
}

Write-Host "Fetching Intune-managed devices..."
$IntuneDevices = Get-MgDeviceManagementManagedDevice -All
$CandidateDevices = @()

foreach ($IntuneDevice in $IntuneDevices) {
    $AzureADDevice = Get-MgDevice -Filter "deviceId eq '$($IntuneDevice.AzureAdDeviceId)'" 2>$null
    if (-not $AzureADDevice) {
        Write-Host "No Azure AD device found for: $($IntuneDevice.DeviceName)" -ForegroundColor Red
        Write-Host "----------------------------------------"
        continue
    }

    Write-Host "Device: $($IntuneDevice.DeviceName)"
    Write-Host "Azure AD Device ID: $($AzureADDevice.Id)"
    Write-Host "Azure AD Compliance State: $($AzureADDevice.IsCompliant)"
    Write-Host "Intune Compliance State: $($IntuneDevice.ComplianceState)"

    $IntuneDevice | Add-Member -MemberType NoteProperty -Name AADObjectId -Value $AzureADDevice.Id -Force
    $IntuneDevice | Add-Member -MemberType NoteProperty -Name AADCompliance -Value $AzureADDevice.IsCompliant -Force

    $needsUpdate = $false
    switch ($IntuneDevice.ComplianceState) {
        "compliant"     { if ($AzureADDevice.IsCompliant -ne $true)  { $needsUpdate = $true } }
        "inGracePeriod" { if ($AzureADDevice.IsCompliant -ne $true)  { $needsUpdate = $true } }
        "noncompliant"  { if ($AzureADDevice.IsCompliant -ne $false) { $needsUpdate = $true } }
    }

    if ($needsUpdate) {
        Write-Host "Adding device to candidate list for compliance update." -ForegroundColor Yellow
        $CandidateDevices += $IntuneDevice
    } else {
        Write-Host "Device does not require compliance update." -ForegroundColor Green
    }
    Write-Host "----------------------------------------"
}

if ($LogToCsv -and $CandidateDevices.Count -gt 0) {
    $CandidateDevices | Select-Object `
        DeviceName,
        @{Name = "IntuneCompliance"; Expression = { $_.ComplianceState } },
        @{Name = "AzureADCompliance"; Expression = { $_.AADCompliance } },
        SerialNumber,
        Manufacturer,
        Model,
        UserDisplayName,
        EnrolledDateTime,
        LastSyncDateTime,
        @{Name = "AADObjectId"; Expression = { $_.AADObjectId } } |
        Export-Csv -Path ".\ComplianceMismatchDevices.csv" -NoTypeInformation
}

if ($CandidateDevices.Count -eq 0) {
    Write-Host "No devices found that require compliance status sync. This window will close in 10 seconds." -ForegroundColor Green
    Start-Sleep -Seconds 10
    exit 0
}

$DevicesToSync = $CandidateDevices | Select-Object `
    DeviceName,
    @{Name = "ComplianceState"; Expression = { $_.ComplianceState } },
    @{Name = "AADCompliance"; Expression = { $_.AADCompliance } },
    SerialNumber,
    Manufacturer,
    Model,
    UserDisplayName,
    EnrolledDateTime,
    LastSyncDateTime,
    @{Name = "AADObjectId"; Expression = { $_.AADObjectId } } |
Out-GridView -Title "Select devices to sync compliance status" -OutputMode Multiple

if (-not $DevicesToSync) {
    Write-Host "No devices selected for compliance sync. Exiting script." -ForegroundColor Yellow
    exit 0
}

if ($LogToCsv) {
    $DevicesToSync | Export-Csv -Path ".\SelectedDevicesForUpdate.csv" -NoTypeInformation
}

$SuccessfullyUpdated = @()

foreach ($Device in $DevicesToSync) {
    Write-Host "Processing device: $($Device.DeviceName) with AAD Object ID: $($Device.AADObjectId)"

    $isCompliant = if ($Device.ComplianceState -eq "compliant" -or $Device.ComplianceState -eq "inGracePeriod") { $true } else { $false }
    $body = @{ isCompliant = $isCompliant }

    try {
        Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/devices/$($Device.AADObjectId)" -Body ($body | ConvertTo-Json -Compress)
        Write-Host "Compliance status updated for: $($Device.DeviceName)" -ForegroundColor Green
        $SuccessfullyUpdated += $Device
    } catch {
        Write-Host "Failed to update device: $($Device.DeviceName). Error: $_" -ForegroundColor Red
    }
}

if ($LogToCsv -and $SuccessfullyUpdated.Count -gt 0) {
    $SuccessfullyUpdated | Export-Csv -Path ".\SuccessfullyUpdatedDevices.csv" -NoTypeInformation

    Write-Host "`nLog files created:" -ForegroundColor Cyan
    Write-Host " - ComplianceMismatchDevices.csv"
    Write-Host " - SelectedDevicesForUpdate.csv"
    Write-Host " - SuccessfullyUpdatedDevices.csv"
} elseif ($LogToCsv) {
    Write-Host "`nNo devices were successfully updated; no log file created for updates." -ForegroundColor Yellow
}

