function Test-AdhicsSecurity {
    [CmdletBinding()]
    param (
        [string]$BotName = "ADHICS-Audit-Bot"
    )

    while ($true) {
        Clear-Host
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "   ADHICS Security Compliance Modular Auditor        " -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "  [1] Run ADHICS Security Audit" -ForegroundColor White
        Write-Host "  [2] Exit" -ForegroundColor White
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Select an option: " -NoNewline -ForegroundColor Yellow
        $menuChoice = [Console]::ReadKey($true).KeyChar

        if ($menuChoice -eq '2') {
            Write-Host "`nExiting tool. Stay secure!" -ForegroundColor Yellow
            break
        }

        if ($menuChoice -eq '1') {
            Clear-Host
            
            # --- ULTRA-FAST SYSTEM SPECS (WMI METHOD) ---
            $osName = (Get-WmiObject -Class Win32_OperatingSystem).Caption
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
            $osVersion = (Get-ItemProperty -Path $regPath).DisplayVersion
            $osBuild = (Get-ItemProperty -Path $regPath).CurrentBuild
            $hostname = [Environment]::MachineName
            
            # Pull the MAC address instantly
            $macAddress = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1).MacAddress
            if (-not $macAddress) { $macAddress = "No Active Adapter Found" }

            Write-Host "=====================================================" -ForegroundColor Gray
            Write-Host " Hostname:  $hostname" -ForegroundColor White
            Write-Host " MAC Addr:  $macAddress" -ForegroundColor White
            Write-Host " Target OS: $osName" -ForegroundColor White
            Write-Host " Version:   $osVersion (Build $osBuild)" -ForegroundColor White
            Write-Host "=====================================================" -ForegroundColor Gray
            Write-Host ""

            # --- AUDIT LOGIC ---
            $isCompliant = $true
            
            # =====================================================
            #  FAST CHECKS (Registry & Local Applications)
            # =====================================================
            Write-Host "[*] Running rapid network & protocol checks..." -ForegroundColor Cyan
            
            # Check TLS 1.0
            $tls10Path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client"
            $tls10Enabled = $true
            if (Test-Path $tls10Path) {
                $regValue = Get-ItemProperty -Path $tls10Path -Name "Enabled" -ErrorAction SilentlyContinue
                if ($regValue -and $regValue.Enabled -eq 0) { $tls10Enabled = $false }
            }

            # Check TLS 1.1
            $tls11Path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client"
            $tls11Enabled = $true
            if (Test-Path $tls11Path) {
                $regValue = Get-ItemProperty -Path $tls11Path -Name "Enabled" -ErrorAction SilentlyContinue
                if ($regValue -and $regValue.Enabled -eq 0) { $tls11Enabled = $false }
            }
            
            # Check TLS 1.2
            $tls12Path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
            $tls12Enabled = $false
            if (Test-Path $tls12Path) {
                $regValue = Get-ItemProperty -Path $tls12Path -Name "Enabled" -ErrorAction SilentlyContinue
                if ($regValue -and $regValue.Enabled -eq 1) { $tls12Enabled = $true }
            }

            # Check TLS 1.3
            $tls13Path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server"
            $tls13Enabled = $false
            if (Test-Path $tls13Path) {
                $regValue = Get-ItemProperty -Path $tls13Path -Name "Enabled" -ErrorAction SilentlyContinue
                if ($regValue -and $regValue.Enabled -eq 1) { $tls13Enabled = $true }
            }

            # Check SMB Protocols
            $smbConfig = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
            $smb1Enabled = $smbConfig.EnableSMB1Protocol
            $smb2Enabled = $smbConfig.EnableSMB2Protocol

            # Check SMB Signing Requirement
            $lanmanServerPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
            $smbServerSigningRequired = $false
            if (Test-Path $lanmanServerPath) {
                $signingReg = Get-ItemProperty -Path $lanmanServerPath -Name "RequireSecuritySignature" -ErrorAction SilentlyContinue
                if ($signingReg -and $signingReg.RequireSecuritySignature -eq 1) { $smbServerSigningRequired = $true }
            }

            # Check WinRAR Update Status
            $winrarCheck = winget list --id AlexanderRoshal.WinRAR --exact -e --accept-source-agreements 2>$null
            $winrarNeedsUpdate = $false
            $winrarInstalled = $false
            if ($winrarCheck -match "AlexanderRoshal.WinRAR") {
                $winrarInstalled = $true
                if ($winrarCheck -match "winget") { $winrarNeedsUpdate = $true }
            }

            # --- DISPLAY REPORT ---
            Write-Host "`n--- Current Compliance Status ---" -ForegroundColor White
            
            if ($tls10Enabled) { Write-Host "  [-] TLS 1.0 is ENABLED  -> [NON-COMPLIANT]" -ForegroundColor Red; $isCompliant = $false }
            else { Write-Host "  [+] TLS 1.0 is DISABLED -> [COMPLIANT]" -ForegroundColor Green }

            if ($tls11Enabled) { Write-Host "  [-] TLS 1.1 is ENABLED  -> [NON-COMPLIANT]" -ForegroundColor Red; $isCompliant = $false }
            else { Write-Host "  [+] TLS 1.1 is DISABLED -> [COMPLIANT]" -ForegroundColor Green }

            if ($tls12Enabled) { Write-Host "  [+] TLS 1.2 is ENABLED  -> [COMPLIANT]" -ForegroundColor Green }
            else { Write-Host "  [-] TLS 1.2 is DISABLED -> [NON-COMPLIANT]" -ForegroundColor Red; $isCompliant = $false }

            if ($tls13Enabled) { Write-Host "  [+] TLS 1.3 is ENABLED  -> [COMPLIANT]" -ForegroundColor Green }
            else { Write-Host "  [-] TLS 1.3 is DISABLED -> [NON-COMPLIANT]" -ForegroundColor Red; $isCompliant = $false }

            if ($smb1Enabled -eq $true) { Write-Host "  [-] SMBv1 is ENABLED    -> [NON-COMPLIANT]" -ForegroundColor Red; $isCompliant = $false }
            else { Write-Host "  [+] SMBv1 is DISABLED   -> [COMPLIANT]" -ForegroundColor Green }

            if ($smb2Enabled -eq $true) { Write-Host "  [+] SMBv2/v3 is ENABLED -> [COMPLIANT]" -ForegroundColor Green }
            else { Write-Host "  [-] SMBv2/v3 is DISABLED-> [NON-COMPLIANT]" -ForegroundColor Red; $isCompliant = $false }

            if ($smbServerSigningRequired) { Write-Host "  [+] SMB Signing Status  -> [COMPLIANT] (Required)" -ForegroundColor Green }
            else { Write-Host "  [-] SMB Signing Status  -> [NON-COMPLIANT] (Disabled)" -ForegroundColor Red; $isCompliant = $false }

            if (-not $winrarInstalled) {
                Write-Host "  [+] WinRAR Status       -> [COMPLIANT] (Not Installed)" -ForegroundColor Green
            } elseif ($winrarNeedsUpdate) { 
                Write-Host "  [-] WinRAR Status       -> [NON-COMPLIANT] (Update Available)" -ForegroundColor Red; $isCompliant = $false 
            } else { 
                Write-Host "  [+] WinRAR Status       -> [COMPLIANT] (Up to Date)" -ForegroundColor Green 
            }

            # --- THE INTERACTIVE QUESTION ---
            if ($isCompliant -eq $false) {
                Write-Host ""
                Write-Host "${BotName}: Non-compliant items found! Open IIS Crypto remediation panel? [1] Yes  [2] No: " -NoNewline -ForegroundColor Yellow
                $fixChoice = [Console]::ReadKey($true).KeyChar
                
                if ($fixChoice -eq '1') {
                    Write-Host "`n`n[+] Searching for and launching IIS Crypto..." -ForegroundColor Yellow
                    
                    # Target known locations of IISCrypto
                    $cryptoPaths = @(
                        "C:\Users\Public\Desktop\IISCrypto.exe",
                        "$Home\Desktop\IISCrypto.exe",
                        "C:\Program Files\IIS Crypto\IISCrypto.exe",
                        (Join-Path $PSScriptRoot "IISCrypto.exe")
                    )
                    
                    $appLaunched = $false
                    foreach ($path in $cryptoPaths) {
                        if (Test-Path $path) {
                            Start-Process $path -Verb RunAs
                            $appLaunched = $true
                            break
                        }
                    }

                    # Deep search backup if desktop handles shift around
                    if (-not $appLaunched) {
                        Write-Host "[*] Prompting system-wide location lookup..." -ForegroundColor Gray
                        $searchedPath = Get-ChildItem -Path "C:\" -Filter "IISCrypto.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($searchedPath) {
                            Start-Process $searchedPath.FullName -Verb RunAs
                        } else {
                            Write-Host "Error: IISCrypto.exe executable could not be found automatically." -ForegroundColor Red
                            Write-Host "Please place IISCrypto.exe into this script's folder: $PSScriptRoot" -ForegroundColor Gray
                        }
                    }
                } else {
                    Write-Host "`n`n${BotName}: Remediation skipped by user." -ForegroundColor Yellow
                }
            } else {
                Write-Host "`n${BotName}: Perfect! The system is already compliant with administrative checks." -ForegroundColor Green
            }
            
            Write-Host "`nPress any key to return to the menu..."
            [Console]::ReadKey($true) | Out-Null
        }
    }
}

Test-AdhicsSecurity