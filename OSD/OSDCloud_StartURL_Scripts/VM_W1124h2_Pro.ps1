Write-Host -ForegroundColor Yellow "Starting VM Setup"
Start-Sleep -Seconds 10
Start-OSDCloud -OSName 'Windows 11 24H2 x64' -OSLanguage en-us -OSEdition Pro -OSActivation Retail -Restart -ZTI