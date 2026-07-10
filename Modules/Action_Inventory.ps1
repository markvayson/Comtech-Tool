$script:BtnInventory.Add_Click({
    if ($script:InventoryClicked) {
        $Result = [System.Windows.MessageBox]::Show("You have already collected the system inventories. Are you sure you want to run it again?", "Confirm Action", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($Result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

   Set-AppButtonState $false
    $script:LogPanel.Children.Clear()

    $T_Init   = New-TaskRow "Initialization: Executing Asset & Software Discovery..."
    $T_Soft   = New-TaskRow "Resolving Directory Structure & Writing Software Inventory..."
    $T_Asset  = New-TaskRow "Resolving Directory Structure & WritingWHardware Asset Inventory..."

    Update-WpfUI
    Start-Sleep -Milliseconds 600

    Set-TaskRunning $T_Init
    Start-Sleep -Milliseconds 300
    Complete-Task $T_Init "Initialization: Executing Asset & Software Discovery..." "Success"

    $ScriptDir = $PSScriptRoot
    if (-not $ScriptDir) { $ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
    $InventoryFolder = Join-Path $ScriptDir "Inventory Folder"
    if (-not (Test-Path $InventoryFolder)) { New-Item -ItemType Directory -Path $InventoryFolder | Out-Null }
    
    $CurrentScanDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $Hostname = $env:COMPUTERNAME

    Set-TaskRunning $T_Soft
    $SoftwareFolder = Join-Path $InventoryFolder "Software Inventory"
    if (-not (Test-Path $SoftwareFolder)) { New-Item -ItemType Directory -Path $SoftwareFolder | Out-Null }
    
    $CsvPath = Join-Path $SoftwareFolder "$Hostname.csv"
    $UninstallPaths = @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")
    
    $InstalledSoftware = Get-ItemProperty $UninstallPaths -ErrorAction SilentlyContinue | 
        Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 -and $_.ParentKeyName -eq $null } |
        Select-Object @{N='PC_Name';E={$Hostname}}, DisplayName, DisplayVersion, Publisher, InstallDate, @{N='ScanDate';E={$CurrentScanDate}} | 
        Sort-Object DisplayName
        
    if ($InstalledSoftware) {
        $InstalledSoftware | Export-Csv -Path $CsvPath -NoTypeInformation -Force
        $MasterSoftwarePath = Join-Path $InventoryFolder "Master_Software_Inventory.csv"
        $MasterSoftwarePathBKP = Join-Path $SoftwareFolder "Master_Software_Inventory_bkp.csv"
        $InstalledSoftware | Export-Csv -Path $MasterSoftwarePathBKP -Append -NoTypeInformation -Force
        $InstalledSoftware | Export-Csv -Path $MasterSoftwarePath -Append -NoTypeInformation -Force
        Complete-Task $T_Soft "$($InstalledSoftware.Count) applications saved to '$Hostname.csv'." "Success"
    } else {
        Complete-Task $T_Soft "Failed to retrieve software list." "Error"
    }

    Set-TaskRunning $T_Asset
    $AssetFolder = Join-Path $InventoryFolder "Asset Inventory"
    if (-not (Test-Path $AssetFolder)) { New-Item -ItemType Directory -Path $AssetFolder | Out-Null }
    $AssetCsvPath = Join-Path $AssetFolder "$($Hostname)_Asset.csv"

    try {
        $ChassisInfo = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue
        $ChassisType = if ($ChassisInfo) { $ChassisInfo.ChassisTypes[0] } else { 0 }
        $Description = if ($ChassisType -match '^(8|9|10|11|12|14|18|21)$' -or (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) { "Laptop" } else { "Desktop" }

        $Department = Show-ThemedInputBox -Title "Department Entry" -Message "Please enter the Department for this asset:" -DefaultText ""
        if ([string]::IsNullOrWhiteSpace($Department)) { $Department = "" }
        
        $systemInfo = Get-CimInstance Win32_ComputerSystem
        $biosInfo   = Get-CimInstance Win32_BIOS
        $os         = Get-CimInstance Win32_OperatingSystem
        $cpu        = Get-CimInstance Win32_Processor | Select-Object -First 1
        $windowsVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
        
        $osCaption = $os.Caption
        $buildNumber = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name CurrentBuildNumber).CurrentBuildNumber
        if ($buildNumber -ge 22000) { $osCaption = $osCaption -replace "Windows 10", "Windows 11" }

        $RAM = if ($systemInfo.TotalPhysicalMemory) { [math]::Round($systemInfo.TotalPhysicalMemory/1GB,2) } else { 0 }
        
        $AssetCustodian = if ($DomainUsers.Count -gt 0) { $DomainUsers -join ', ' } else { "None Detected" }

        $ActiveNetworks = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=$true" -ErrorAction SilentlyContinue
        $MacAddresses = ($ActiveNetworks.MACAddress | Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false }) -join ', '
        $IpAddresses = ($ActiveNetworks.IPAddress | Where-Object { $_ -match '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' }) -join ', '

        $AssetData = [PSCustomObject]@{
            Description   = $Description
            Manufacturer  = $systemInfo.Manufacturer
            Model         = $systemInfo.Model
            Department    = $Department
            SerialNumber  = $biosInfo.SerialNumber
            MacAddress    = $MacAddresses
            SystemDetails = "Device: $Hostname | CPU: $($cpu.Name) | RAM: $($RAM)GB | OS: $osCaption $windowsVersion"
            IpAddress     = $IpAddresses
            HostName      = $Hostname
            AssetClassification = "CONFIDENTIAL"
            C = "4"
            I = "4"
            A = "3"
            StatusOfTheAsset = "CRITICAL"
            StatusErrorNotes = "ACTIVE-WORKING"
            AssetOwner = ""
            AssetCustodian = $AssetCustodian
            AssetUpdatedDate = ""
            SoftwareVersion = ""
            ScanDate      = $CurrentScanDate
        }
        
        if ($AssetData) {
            $AssetData | Export-Csv -Path $AssetCsvPath -NoTypeInformation -Force
            $MasterInventoryPath = Join-Path $InventoryFolder "Master_Asset_Inventory.csv"            
            $MasterInventoryPathBKP = Join-Path $AssetFolder "Master_Asset_Inventory_bkp.csv"
            $AssetData | Export-Csv -Path $MasterInventoryPathBKP -Append -NoTypeInformation -Force
            $AssetData | Export-Csv -Path $MasterInventoryPath -Append -NoTypeInformation -Force
            Complete-Task $T_Asset "Appended asset data successfully." "Success"
        }
    } catch { 
        Complete-Task $T_Asset "Failed to retrieve or write hardware asset information." "Error" 
    }

   Set-AppButtonState $true
})