function Get-SiteAllDocs {
    param (
        [Parameter(Mandatory = $true)]
        $SiteId
    )
        $SiteDocs = @()
    $Site = Get-MgSite -SiteId $SiteId
    Write-Host "Processing site: $($site.DisplayName)" -ForegroundColor Yellow
    #Get drive items for the site
    $AllDrives = Get-MgSiteDrive -SiteId $($site.Id)
    Write-Host "Found $($AllDrives.Count) drives" -ForegroundColor Cyan
    foreach($drive in $AllDrives){
        $AllDriveItems = Get-MgDriveListItem -DriveId $Drive.Id
        $AllDriveDocs = $AllDriveItems | Where-Object { $_.ContentType.Name -eq "Document" }
        if ($AllDriveDocs.Count -gt 0) {
            Write-Host "Found $($AllDriveDocs.Count) documents in drive: $($drive.Name)"
            foreach ($doc in $AllDriveDocs) {
                Write-Host "Document: $($doc.WebUrl) (ID: $($doc.Id))"
                $SiteDocs += $doc
            }
        } else {
            Write-Host "No documents found in drive: $($drive.Name)"
        }
    }
    return $SiteDocs
}

$Secret = ""
$appId = ""
$tenantid = ""


$SecureClientSecret = ConvertTo-SecureString -String $Secret -AsPlainText -Force

$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $appId, $SecureClientSecret

if(Get-MgContext) {
    Write-Host "Already connected to Microsoft Graph" -ForegroundColor Green
} else {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential
}


# Get all sites in the tenant
Write-Host "Retrieving all sites in the tenant..." -ForegroundColor Green
$AllSites = Get-MgAllSite 

if ($AllSites.Count -eq 0) {
    Write-Host "No sites found in the tenant." -ForegroundColor Red
    exit 1
}

# Prompt user to choose a site

Write-Host "Choose a site to process:" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow
$Counter = 0
foreach ($site in $AllSites) {
    $Counter++
    Write-Host "[$Counter] - $($site.DisplayName) - $($site.WebUrl)" -ForegroundColor Cyan
 }

[int]$ChoosenIndex = Read-Host "Choose the site to process (enter the index):" 
while ($ChoosenIndex -lt 1 -or $ChoosenIndex -gt $Counter) {
    Write-Host "Please choose a valid index between 1 and $Counter." -ForegroundColor Red
    $ChoosenIndex = Read-Host "Choose the site to process (enter the index):"
}
$ChoosenSite = $AllSites[$($ChoosenIndex - 1)]

# Get all documents from the chosen site

$ChoosenSiteDocs = Get-SiteAllDocs -SiteId $ChoosenSite.Id 








