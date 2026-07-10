  


# --- SETTINGS BUTTON ACTION ---
$script:BtnSettings.Add_Click({
    Set-AppButtonState $false
    $Reader = (New-Object System.Xml.XmlNodeReader $SettingsXAML)
    $SettingsWindow = [System.Windows.Markup.XamlReader]::Load($Reader)
    
    # 1. Dynamically set the Version Title
    $VersionHeader = $SettingsWindow.FindName("VersionHeader")
    $AppVer = if ($global:CurrentVersion) { $global:CurrentVersion } else { "Unknown" }
    $VersionHeader.Text = "Release Notes - Version $AppVer"
    
    # 2. Read from embedded variable
    $NotesText = $SettingsWindow.FindName("NotesText")
    
    if ($global:EmbeddedReleaseNotes) {
        $AllLines = $global:EmbeddedReleaseNotes -split "`n"   
        $CapturedText = @()
        $IsCapturing = $false
        
        # Strip trailing ".0" if your global version is 2.1.3.0 but notes just say 2.1.3
        $SearchVer = $AppVer -replace '\.0$', ''
        
        foreach ($Line in $AllLines) {
            $Line = $Line.Trim("`r") # Clean up any weird carriage returns
            
            if (-not $IsCapturing) {
                # Start capturing when we find the version
                if ($Line -match "^$([regex]::Escape($SearchVer))") {
                    $IsCapturing = $true
                }
                continue 
            }
            
            # Stop capturing if we hit another version number
            if ($Line -match "^\d+\.\d+") {
                break
            }
            
            # Add the notes to our list
            $CapturedText += $Line
        }
        
        if ($CapturedText.Count -gt 0) {
            $NotesText.Text = ($CapturedText -join "`n").Trim()
        } else {
            $NotesText.Text = "No specific notes found for version $SearchVer.`n`nPlease ensure your version number in ReleaseNotes.txt exactly matches this version."
        }
    } else {
        $NotesText.Text = "No embedded release notes found."
    }
    
    # Inherit Dark/Light mode behavior
    $SettingsWindow.Add_SourceInitialized({
        if (-not $script:IsLightMode) {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($SettingsWindow)).Handle
            $darkMode = 1
            try { [DWM]::DwmSetWindowAttribute($hwnd, 20, [ref]$darkMode, 4) | Out-Null } catch {}
        }
    })
    Set-AppButtonState $false
    $SettingsWindow.ShowDialog() | Out-Null
})