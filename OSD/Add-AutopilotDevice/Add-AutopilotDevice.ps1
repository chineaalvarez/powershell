
Function Add-AutopilotImportedDevice() {
    param
    (
        [Parameter(Mandatory = $true)] $serialNumber,
        [Parameter(Mandatory = $true)] $hardwareIdentifier,
        [Parameter(Mandatory = $false)] [Alias("orderIdentifier")] $groupTag = "",
        [Parameter(Mandatory = $false)] [Alias("UPN")] $assignedUser = ""
    )

    # Defining Variables
    $graphApiVersion = "beta"
    $Resource = "deviceManagement/importedWindowsAutopilotDeviceIdentities"
    $uri = "https://graph.microsoft.com/$graphApiVersion/$Resource"
    $json = @"
{
    "@odata.type": "#microsoft.graph.importedWindowsAutopilotDeviceIdentity",
    "groupTag": "$groupTag",
    "serialNumber": "$serialNumber",
    "productKey": "",
    "hardwareIdentifier": "$hardwareIdentifier",
    "assignedUserPrincipalName": "$assignedUser",
    "state": {
        "@odata.type": "microsoft.graph.importedWindowsAutopilotDeviceIdentityState",
        "deviceImportStatus": "pending",
        "deviceRegistrationId": "",
        "deviceErrorCode": 0,
        "deviceErrorName": ""
    }
}
"@

    Write-Verbose "POST $uri`n$json"

    try {
        $request = Invoke-MgGraphRequest -Uri $uri -Method Post -Body $json -ContentType "application/json"
        Write-Host "Device import request submitted" -ForegroundColor Green
        return $request
    }
    catch {
        Write-Error $_.Exception
        break
    }
}

Function Check-ImportStatus() {
    param (
        [Parameter(Mandatory = $true)]
        [String]
        $ImportId,
        [Parameter(Mandatory = $false)]
        [Int]
        $CheckInterval = 5,
        [Parameter(Mandatory = $false)]
        [Int]
        $TimeOut = 720
    )
    $TimeoutCounter = 0
    do {
        $uri = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities/$ImportId"
        $request = Invoke-MgGraphRequest -Uri $uri -Method Get
        $status = $request.state.deviceImportStatus
        if ($status -eq "error") {
            Write-Error "Error importing device: $($request.state.deviceErrorName)"
            break
        }
        elseif ($status -eq "complete") {
            Write-Host "Device import completed" -ForegroundColor Green
            break
        }
        elseif ($status -eq "unknown") {
            Start-Sleep -Seconds $CheckInterval
            if ($TimeoutCounter -ge $TimeOut) {
                Write-Error "Timeout waiting for import to complete after $Timeout seconds, Please try again later"
                break
            }
            Write-Host "Status: $status - Waiting for status update, checking again in $CheckInterval seconds [$($($TimeoutCounter/$CheckInterval)+1)/$($TimeOut/$CheckInterval)]" -ForegroundColor Yellow
            $TimeoutCounter += $CheckInterval
        }else {
            Write-Error "Unhandled Status of the Import request Status: $status"
            break
        }

    } until (
        $false
    )
}

Function Get-SerialNumber {
    try {
        $SN = Get-CimInstance Win32_BIOS -ErrorAction Stop | Select-Object SerialNumber
        if ($null -ne $SN.SerialNumber) {
            return $SN.SerialNumber
        }
        else {
            Write-error "No Serial Number found"
        }
    }
    catch {
        Write-Error "Error getting Serial Number: $_"
    }
}

Function Get-HardwareHash {
    # Get the hash (if available)
    try {
        $devDetail = (Get-CimInstance -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -ErrorAction Stop)
        if ($null -ne $devDetail.DeviceHardwareData) {
            return $devDetail.DeviceHardwareData
        }
        else {
            Write-Error "Hardware Hash not found"
        }
    }
    catch {
        Write-Error "Error getting Hardware Hash: $_"
    }


}

function Ensure-Module {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
	Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "$ModuleName is not installed. Installing..."
        try {
            Install-Module -Name $ModuleName -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "$ModuleName has been installed successfully."
        }
        catch {
            Write-Host "Failed to install $ModuleName. Error: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "$ModuleName is already installed." -ForegroundColor Green
    }
}



function Register-AutopilotDevice {
    param (
    [Parameter(Mandatory = $false)]
    [String]
    $GroupTag
)
    Write-Host "Checing requiring modules..." -ForegroundColor Blue
    Ensure-Module -ModuleName "microsoft.graph.authentication"
    
    Write-Host "Getting Serial Number and Hardware Hash..." -ForegroundColor Blue
    
    
    $Sn = Get-SerialNumber
    
    if($Sn){
        Write-Host "Serial Number Obtained" -ForegroundColor Green
    }else{
        Write-Error "Failed to get Serial Number"
        return
    }
    $HH = Get-HardwareHash
    if($HH){
        Write-Host "Hardware Hash Obtained" -ForegroundColor Green
    }else{
        Write-Error "Failed to get Hardware Hash"
        return
    }
    
    
    Write-Host "Connection to Graph API..." -ForegroundColor Blue
    Connect-MgGraph -UseDeviceCode -ContextScope Process -NoWelcome
    if(Get-MgContext){
        Write-Host "Connected to Graph API sucessfully" -ForegroundColor Green
    }else{
        Write-Error "Failed to connect to Graph API" -ForegroundColor Red
        Exit 1
    }
    
    Write-Host "Importing device with serial number: $($SN)" -ForegroundColor Blue
    
    if ($GroupTag) {
        $ImportRequest = Add-AutopilotImportedDevice -serialNumber $SN -hardwareIdentifier $HH -groupTag $GroupTag
    }
    else {
        $ImportRequest = Add-AutopilotImportedDevice -serialNumber $SN -hardwareIdentifier $HH
    }
    Write-Host "Checking import status" -ForegroundColor Blue
    
    Check-ImportStatus -ImportId $ImportRequest.importId -CheckInterval 10 -TimeOut 360
}



Register-AutopilotDevice