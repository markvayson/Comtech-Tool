function global:Invoke-InitialAudit {
    $script:LogPanel.Children.Clear()
    $global:AuditUI = @{}
$script:ComplianceState = @{}
    # --- Accepts a custom message to display ---
    function Show-AuditStatus {
        param([string]$ControlKey, [string]$ControlName, [bool]$Status, [string]$PassMsg, [string]$FailMsg)
        $T_Check = New-TaskRow "Auditing: $ControlName"
        Update-WpfUI
        Start-Sleep -Milliseconds 50
        $Msg = if ($Status) { "$ControlName -> $PassMsg" } else { "$ControlName -> $FailMsg" }
        $Icon = if ($Status) { "Done" } else { "Warning" }
        Complete-Task $T_Check $Msg $Icon
        $global:AuditUI[$ControlKey] = $T_Check
    }

    # 1. Windows Updates (Pass if under 30 days old)
    $LastHotfix = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
    $CurrentDate = Get-Date
    if ($null -ne $LastHotfix) {
        $DaysSinceUpdate = ($CurrentDate - $LastHotfix.InstalledOn).TotalDays
        $script:ComplianceState.UpdateCheck = ($DaysSinceUpdate -le 30)
    } else {
        $script:ComplianceState.UpdateCheck = $false
    }
    Show-AuditStatus "UpdateCheck" $global:AuditText.UpdateCheck $script:ComplianceState.UpdateCheck "Updated within 30 days" "Out of date (Over 30 days)"

    # 2. Windows Activation Status (Pass if license exists)
    $License = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' and PartialProductKey is not null" -ErrorAction SilentlyContinue
    $script:ComplianceState.Activation = ($null -ne $License)
    Show-AuditStatus "Activation" $global:AuditText.ActivationStatus $script:ComplianceState.Activation "Licensed" "Unlicensed / Not Implemented"

    # 3. Microsoft Office Version (Pass if 2024 or newer / 365)
    $OfficeApp = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "Microsoft Office" -or $_.DisplayName -match "Microsoft 365" } | Select-Object -First 1

    if ($OfficeApp) {
        $script:ComplianceState.Office = ($OfficeApp.DisplayName -match "2024" -or $OfficeApp.DisplayName -match "365" -or $OfficeApp.DisplayName -match "202[5-9]")
        $FoundVersion = if ($OfficeApp.DisplayName -match "(2019|2021|2024|365)") { $matches[1] } else { "Unknown Version" }
        Show-AuditStatus "Office" $global:AuditText.OfficeVersion $script:ComplianceState.Office "Version $FoundVersion Installed" "Version $FoundVersion (Below 2024)"
    } else {
        $script:ComplianceState.Office = $false
        Show-AuditStatus "Office" $global:AuditText.Office $script:ComplianceState.Office "Installed" "Not Installed"
    }

    # 4. WinRAR Version (Always Pass for now)
    $WinRar = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "WinRAR" } | Select-Object -First 1
    $script:ComplianceState.WinRAR = $true
    if ($WinRar) {
        Show-AuditStatus "WinRAR" $global:AuditText.WinRARVersion $script:ComplianceState.WinRAR "Version $($WinRar.DisplayVersion)" "Version $($WinRar.DisplayVersion)"
    } else {
        Show-AuditStatus "WinRAR" $global:AuditText.WinRARVersion $script:ComplianceState.WinRAR "Not Installed" "Not Installed"
    }

    # 5. Legacy SSL (Pass if disabled)
    $SchannelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
    $script:ComplianceState.SSLOlder = (Test-RegValue "$SchannelPath\SSL 3.0\Client" "Enabled" 0) -and (Test-RegValue "$SchannelPath\TLS 1.0\Client" "Enabled" 0)
    Show-AuditStatus "LegacySSL" $global:AuditText.LegacySSL $script:ComplianceState.SSLOlder "Disabled" "Enabled"

    # 6. TLS 1.2 (Pass if enabled)
    $script:ComplianceState.TLS12 = (Test-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" "Enabled" 1)
    Show-AuditStatus "TLS12" "TLS 1.2" $script:ComplianceState.TLS12 "Enabled" "Disabled"

    # 7. Weak Ciphers (Pass if DES, RC2, and RC4 are disabled/removed)
    $CipherPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers"
    $script:ComplianceState.WeakCiphers = (Test-RegValue "$CipherPath\RC4 128/128" "Enabled" 0) -and 
                                          (Test-RegValue "$CipherPath\DES 56/56" "Enabled" 0) -and
                                          (Test-RegValue "$CipherPath\RC2 56/128" "Enabled" 0)
    Show-AuditStatus "Ciphers" $global:AuditText.Ciphers $script:ComplianceState.WeakCiphers "Disabled" "Enabled"

    # 8. SMBv1 Protocol (Pass if disabled)
    $Smb1 = Get-SmbServerConfiguration -ErrorAction SilentlyContinue | Select-Object -ExpandProperty EnableSMB1Protocol
    $script:ComplianceState.SMB1 = (-not $Smb1)
    Show-AuditStatus "SMB1" "SMBv1 Protocol" $script:ComplianceState.SMB1 "Disabled" "Enabled"

    # 9. SMB Signing (Pass if required)
    $SmbSign = Get-SmbServerConfiguration -ErrorAction SilentlyContinue | Select-Object -ExpandProperty RequireSecuritySignature
    $script:ComplianceState.SMBSign = [bool]$SmbSign
    Show-AuditStatus "SMBSign" "SMB Signing" $script:ComplianceState.SMBSign "Enabled" "Disabled"

    # 10. File Shares (Pass if there is no file sharing)
    $AllShares = Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "^(IPC\$|ADMIN\$|C\$|D\$|print\$)$" }
    $FileShares = $AllShares | Where-Object { $_.ShareType -eq 0 -or $_.ShareType -eq "FileSystem" }
    $script:ComplianceState.NetShares = ($null -eq $FileShares)
    if ($FileShares) {
        $ShareNames = ($FileShares.Name -join ", ")
        Show-AuditStatus "NetShares" $global:AuditText.NetShares $script:ComplianceState.NetShares "None" $ShareNames
    } else {
        Show-AuditStatus "NetShares" $global:AuditText.NetShares $script:ComplianceState.NetShares "None" "None"
    }

    # 11. Printer Shares (Pass if there is no printer sharing)
    $PrintShares = $AllShares | Where-Object { $_.ShareType -eq 1 -or $_.ShareType -eq "PrintQueue" }
    $script:ComplianceState.PrintShares = ($null -eq $PrintShares)
    if ($PrintShares) {
        $PrinterNames = ($PrintShares.Name -join ", ")
        Show-AuditStatus "PrintShares" $global:AuditText.PrintShares $script:ComplianceState.PrintShares "None" $PrinterNames
    } else {
        Show-AuditStatus "PrintShares" $global:AuditText.PrintShares $script:ComplianceState.PrintShares "None" "None"
    }

    # 12. Local User Accounts (Pass if active unauthorized users are absent)
    $RogueUsers = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true -and $_.Name -notin @("Mark") }
    $script:ComplianceState.LocalUsers = ($null -eq $RogueUsers)
    Show-AuditStatus "LocalAcct" $global:AuditText.LocalAcct $script:ComplianceState.LocalUsers "No Local Users" "Found Local Users ( $($RogueUsers.Name -join ', ') )"

    # 13. Bluetooth (Pass if disabled)
    $Bth = Get-Service -Name "bthserv" -ErrorAction SilentlyContinue
    $script:ComplianceState.Bluetooth = ($Bth.StartType -eq 'Disabled')
    Show-AuditStatus "Bluetooth" $global:AuditText.Bluetooth $script:ComplianceState.Bluetooth "Disabled" "Enabled"

    # 14. Browser Sign-in & Passwords (Pass if disabled via policies)
    $script:ComplianceState.Browsers = (Test-RegValue "HKLM:\SOFTWARE\Policies\Google\Chrome" "BrowserSignin" 0) -and (Test-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "PasswordManagerEnabled" 0)
    Show-AuditStatus "Browsers" $global:AuditText.Browsers $script:ComplianceState.Browsers "Removed" "Not Removed"

    # 15. Wi-Fi (Pass if adapter is disabled)
    $Wifi = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Wireless" -and $_.Status -eq "Up" }
    $script:ComplianceState.Wifi = ($null -eq $Wifi)
    Show-AuditStatus "Wifi" $global:AuditText.Wifi $script:ComplianceState.Wifi "Disabled" "Enabled"
    
    # --- Finish Evaluation & Tally Fails ---
    $T_Finish = New-TaskRow $global:AuditText.Finish
    $global:AuditUI["Finish"] = $T_Finish
    Set-TaskRunning $T_Finish
    
    $Fails = ($script:ComplianceState.Values | Where-Object { $_ -eq $false }).Count
    
    if ($Fails -eq 0) {
        Complete-Task $T_Finish "$($global:AuditText.Finish) -> System is fully compliant." "Done"
      
        $global:SecurityEnforced = $true
    } 
    
  Set-AppButtonState $true
}

$global:Form.Add_ContentRendered({
    Invoke-InitialAudit
})