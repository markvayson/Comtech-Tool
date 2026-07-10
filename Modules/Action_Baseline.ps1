$script:BtnBaseline.Add_Click({
    if ($script:BaselineClicked) {
        $Result = [System.Windows.MessageBox]::Show("You have already enforced the security baseline. Are you sure you want to run it again?", "Confirm Action", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($Result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

   Set-AppButtonState $false
    
    # DO NOT clear the LogPanel. We are going to reuse the rows from InitialAudit.
    Update-WpfUI
    Start-Sleep -Milliseconds 600
    
    $CurrentDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $script:BaselineSummary = [ordered]@{ Hostname = $env:COMPUTERNAME; Scan_Date = $CurrentDate }

    # 1. Windows Update
    if (-not $script:ComplianceState.UpdateCheck) {
        $T_Update = $global:AuditUI["UpdateCheck"]
        $T_Update.Text.Text = $global:AuditText.UpdateCheck # Reset text
        Set-TaskRunning $T_Update
        
        $LastHotfix = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
        if ($null -ne $LastHotfix -and $null -ne $LastHotfix.InstalledOn) {
            $HotfixDate = $LastHotfix.InstalledOn.ToString("MMM/dd/yy")
            $script:BaselineSummary.Windows_Update = $HotfixDate
            Complete-Task $T_Update "Security Update -> $($LastHotfix.HotfixID) on ($HotfixDate) - Check for updates." "Warning"
        } else { 
            $script:BaselineSummary.Windows_Update = "Never / Unknown"
            Complete-Task $T_Update "Security Update -> Unknown or Never" "Warning" 
        }
        $Brush = New-Object System.Windows.Media.BrushConverter
        $script:BtnUpdate.BorderBrush = $Brush.ConvertFromString("#F59E0B") 
        $script:BtnUpdate.BorderThickness = "2"
    } else { $script:BaselineSummary.Windows_Update = "Already Compliant" }

    # 2. Activation Status
    if (-not $script:ComplianceState.ActivationStatus) {
        $T_Act = $global:AuditUI["ActivationStatus"]
        $T_Act.Text.Text = $global:AuditText.ActivationStatus
        Set-TaskRunning $T_Act
        
        try {
            $LicenseQuery = "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' and PartialProductKey is not null"
            $License = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter $LicenseQuery -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($License -and $License.LicenseStatus -eq 1) { 
                $script:BaselineSummary.Windows_Activated = "Licensed"
                Complete-Task $T_Act "Windows Activation Status -> Activated (Licensed)" "Success" 
            } else { 
                $script:BaselineSummary.Windows_Activated = "Unlicensed"
                Complete-Task $T_Act "Windows Activation Status -> UNLICENSED / NOT ACTIVATED" "Error"
            }
        } catch { 
            $script:BaselineSummary.Windows_Activated = "Unlicensed"
            Complete-Task $T_Act "Windows Activation Status -> Verification Failed" "Error"
        }
    } else { $script:BaselineSummary.Windows_Activated = "Already Compliant" }

    # 3. Office Version
    if (-not $script:ComplianceState.OfficeVersion) {
        $T_Office = $global:AuditUI["OfficeVersion"]
        $T_Office.Text.Text = $global:AuditText.OfficeVersion
        Set-TaskRunning $T_Office
        Complete-Task $T_Office "Microsoft Office Version -> Not Detected or Supported" "Warning"
        $script:BaselineSummary.Office_EOL_Status = "Not Detected"
    } else { $script:BaselineSummary.Office_EOL_Status = "Already Compliant" }

    # 4. WinRAR Version
    if (-not $script:ComplianceState.WinRARVersion) {
        $T_WinRAR = $global:AuditUI["WinRARVersion"]
        $T_WinRAR.Text.Text = $global:AuditText.WinRARVersion
        Set-TaskRunning $T_WinRAR
        
        $CurrentWinRar = "Not Installed"
        try {
            $ScriptDir = $PSScriptRoot
            if (-not $ScriptDir) { $ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
            $CentralInstaller = Join-Path $ScriptDir "winrar-x64.exe"
            
            if (Test-Path $CentralInstaller) {
                $InstallerVerInfo = (Get-Item $CentralInstaller).VersionInfo.ProductVersion
                $LatVerStr = [regex]::Match($InstallerVerInfo, '\d+\.\d+').Value
                
                $T_WinRAR.Text.Text = "Installing WinRAR $LatVerStr from IT share..."
                Update-WpfUI
                
                $InstallProc = Start-Process -FilePath $CentralInstaller -ArgumentList "/S" -Wait -PassThru -WindowStyle Hidden
                if ($InstallProc.ExitCode -eq 0) { 
                    $script:BaselineSummary.WinRAR = $LatVerStr
                    Complete-Task $T_WinRAR "WinRAR version -> Updated from IT Share to $LatVerStr" "Success"
                } else {
                    $script:BaselineSummary.WinRAR = "Failed"
                    Complete-Task $T_WinRAR "WinRAR installation returned exit code $($InstallProc.ExitCode)." "Error"
                }
            } else {
                $script:BaselineSummary.WinRAR = "Installer Missing"
                Complete-Task $T_WinRAR "WinRAR installer (winrar-x64.exe) not found in IT folder." "Warning"
            }
        } catch {
            $script:BaselineSummary.WinRAR = "Error"
            Complete-Task $T_WinRAR "WinRAR network share check failed." "Error"
        }
    } else { $script:BaselineSummary.WinRAR = "Already Compliant" }

    # 5. Legacy SSL
    if (-not $script:ComplianceState.SSLOlder) {
        $T_SSL = $global:AuditUI["LegacySSL"]
        $T_SSL.Text.Text = $global:AuditText.LegacySSL
        Set-TaskRunning $T_SSL
        
        $SchannelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
        foreach ($ver in @("SSL 2.0", "SSL 3.0", "TLS 1.0", "TLS 1.1")) {
            Set-RegKey "$SchannelPath\$ver\Client" "Enabled" 0; Set-RegKey "$SchannelPath\$ver\Server" "Enabled" 0
        }
        $script:BaselineSummary.SSL_Configured = "Configured"
        Complete-Task $T_SSL "SSL 2.0 / 3.0 / TLS 1.0 / 1.1 -> Disabled" "Success" 
    } else { $script:BaselineSummary.SSL_Configured = "Already Compliant" }

    # 6. TLS 1.2
    if (-not $script:ComplianceState.TLS12) {
        $T_TLS = $global:AuditUI["TLS12"]
        $T_TLS.Text.Text = $global:AuditText.TLS12
        Set-TaskRunning $T_TLS
        
        $SchannelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
        Set-RegKey "$SchannelPath\TLS 1.2\Client" "Enabled" 1; Set-RegKey "$SchannelPath\TLS 1.2\Server" "Enabled" 1
        $script:BaselineSummary.TLS_Configured = "Configured"
        Complete-Task $T_TLS "TLS 1.2 -> Enabled" "Success"
    } else { $script:BaselineSummary.TLS_Configured = "Already Compliant" }

    # 7. Ciphers
    if (-not $script:ComplianceState.WeakCiphers) {
        $T_Ciphers = $global:AuditUI["Ciphers"]
        $T_Ciphers.Text.Text = $global:AuditText.Ciphers
        Set-TaskRunning $T_Ciphers
        
        $CipherPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers"
        $WeakCiphers = @("NULL", "DES 56/56", "RC2 40/128", "RC2 56/128", "RC2 128/128", "RC4 40/128", "RC4 56/128", "RC4 128/128", "Triple DES 168")
        foreach ($Cipher in $WeakCiphers) { Set-RegKey "$CipherPath\$Cipher" "Enabled" 0 }
        $script:BaselineSummary.Ciphers_Configured = "Configured"
        Complete-Task $T_Ciphers "Weak Ciphers -> Disabled" "Success"
    } else { $script:BaselineSummary.Ciphers_Configured = "Already Compliant" }

    # 8. SMBv1
    if (-not $script:ComplianceState.SMBv1) {
        $T_SMB = $global:AuditUI["SMBv1"]
        $T_SMB.Text.Text = $global:AuditText.SMBv1
        Set-TaskRunning $T_SMB
        
        try {
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue | Out-Null
            Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue | Out-Null
        } catch { }
        Set-RegKey "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" 0
        $script:BaselineSummary.SMB_Configured = "Configured"
        Complete-Task $T_SMB "SMBv1 Termination & SMB Signing -> Configured." "Success"
    } else { $script:BaselineSummary.SMB_Configured = "Already Compliant" }

    # 9. Shares
    if (-not $script:ComplianceState.Shares) {
        $T_Shares = $global:AuditUI["Shares"]
        $T_Shares.Text.Text = $global:AuditText.Shares
        Set-TaskRunning $T_Shares
        
        $DroppedFolders = @()
        $CustomShares = Get-CimInstance -ClassName Win32_Share -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 0 -and $_.Name -notmatch '\$$' }
        if ($CustomShares) {
            foreach ($Share in $CustomShares) { 
                net share "$($Share.Name)" /delete /y | Out-Null
                $DroppedFolders += $Share.Name
            }
            $script:BaselineSummary.Shares_Removed = $DroppedFolders -join ', '
            Complete-Task $T_Shares "Shared Files and Folders: $($DroppedFolders -join ', ') -> Unshared" "Warning"
        }
    } else { $script:BaselineSummary.Shares_Removed = "Already Compliant" }

    # 10. Printers
    if (-not $script:ComplianceState.Printers) {
        $T_Printers = $global:AuditUI["Printers"]
        $T_Printers.Text.Text = $global:AuditText.Printers
        Set-TaskRunning $T_Printers
        
        $DroppedPrinters = @()
        $SharedPrinters = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared -eq $true }
        if ($SharedPrinters) {
            foreach ($Printer in $SharedPrinters) {
                Set-Printer -Name $Printer.Name -Shared $false -ErrorAction SilentlyContinue | Out-Null
                $DroppedPrinters += $Printer.Name
            }
            $script:BaselineSummary.Printers_Removed = $DroppedPrinters -join ', '
            Complete-Task $T_Printers "Shared Printers: $($DroppedPrinters -join ', ') -> Unshared" "Warning"
        }
    } else { $script:BaselineSummary.Printers_Removed = "Already Compliant" }

    # 11. Local Accounts
    if (-not $script:ComplianceState.LocalUsers) {
        $T_Local = $global:AuditUI["LocalAcct"]
        $T_Local.Text.Text = $global:AuditText.LocalAcct
        Set-TaskRunning $T_Local
        
        $LocalUsers = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
        if ($LocalUsers) {
            foreach ($User in $LocalUsers) {
                if ($User.Name -notin @("Mark")) {
                    Disable-LocalUser -Name $User.Name -ErrorAction SilentlyContinue | Out-Null
                }
            }
        }
        $script:BaselineSummary.Local_Accounts = "Audited"
        Complete-Task $T_Local "Local User Accounts -> Disabled." "Success"
    } else { $script:BaselineSummary.Local_Accounts = "Already Compliant" }

    # 12. Bluetooth
    if (-not $script:ComplianceState.Bluetooth) {
        $T_BT = $global:AuditUI["Bluetooth"]
        $T_BT.Text.Text = $global:AuditText.Bluetooth
        Set-TaskRunning $T_BT
        
        $BtDevices = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object Status -eq 'OK'
        if ($BtDevices) { $BtDevices | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
        
        $BthService = Get-Service -Name "bthserv" -ErrorAction SilentlyContinue
        if ($BthService) {
            Set-Service -Name "bthserv" -StartupType Disabled -ErrorAction SilentlyContinue | Out-Null
            Stop-Service -Name "bthserv" -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $script:BaselineSummary.Bluetooth_Status = "Disabled"
        Complete-Task $T_BT "Bluetooth -> Disabled." "Success"
    } else { $script:BaselineSummary.Bluetooth_Status = "Already Compliant" }

    # 13. Browsers
    if (-not $script:ComplianceState.Browsers) {
        $T_Browser = $global:AuditUI["Browsers"]
        $T_Browser.Text.Text = $global:AuditText.Browsers
        Set-TaskRunning $T_Browser
        
        $ChromePath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
        Set-RegKey $ChromePath "BrowserSignin" 0 "DWord"; Set-RegKey $ChromePath "PasswordManagerEnabled" 0 "DWord"
        
        $EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        Set-RegKey $EdgePath "BrowserSignin" 0 "DWord"; Set-RegKey $EdgePath "PasswordManagerEnabled" 0 "DWord"

        $script:BaselineSummary.Browser_Hardening = "Disabled"
        Complete-Task $T_Browser "Browser sign-in and passwords -> Disabled." "Success"
    } else { $script:BaselineSummary.Browser_Hardening = "Already Compliant" }

    # 14. Wi-Fi Disable (Added from Audit logic)
    if (-not $script:ComplianceState.Wifi) {
        $T_Wifi = $global:AuditUI["Wifi"]
        $T_Wifi.Text.Text = $global:AuditText.Wifi
        Set-TaskRunning $T_Wifi
        
        $WifiAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match "Wireless" }
        if ($WifiAdapter) { $WifiAdapter | Disable-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
        
        $script:BaselineSummary.Wifi_Status = "Disabled"
        Complete-Task $T_Wifi "Wi-Fi -> Disabled." "Success"
    } else { $script:BaselineSummary.Wifi_Status = "Already Compliant" }


    # 15. Finish Task
    $T_Finish = $global:AuditUI["Finish"]
    $T_Finish.Text.Text = $global:AuditText.Finish
    Set-TaskRunning $T_Finish
    
    $ScriptDir = $PSScriptRoot
    if (-not $ScriptDir) { $ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
    $LogCsvPath = Join-Path $ScriptDir "Execution_Baseline_Summary_$($env:COMPUTERNAME).csv"
    
    [PSCustomObject]$script:BaselineSummary | Export-Csv -Path $LogCsvPath -Append -NoTypeInformation -Force
    Complete-Task $T_Finish "Compliance Run Complete. Log saved. Reboot suggested." "Done"

    # UI Visual Polish
    $script:BaselineClicked = $true
    $script:TxtBaseline.Text = "Enforce ADHICSv2 Security $([char]0x2713)"
    $Brush = New-Object System.Windows.Media.BrushConverter
    $script:BtnBaseline.BorderBrush = $Brush.ConvertFromString("#10B981") 
    $script:BtnBaseline.BorderThickness = "2"

    Set-AppButtonState $true
})