# Check for elevation
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Restarting with elevated privileges..."
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Show folder browser dialog to select destination
Add-Type -AssemblyName System.Windows.Forms
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select the folder to export drivers to"
$folderBrowser.ShowNewFolderButton = $true

if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $destination = $folderBrowser.SelectedPath
    Write-Host "Exporting drivers to: $destination" -ForegroundColor Cyan

    # Run DISM export
    dism /online /export-driver /destination:"$destination"
} else {
    Write-Host "Operation cancelled by the user." -ForegroundColor Yellow
}