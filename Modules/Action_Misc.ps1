$script:BtnUpdate.Add_Click({
    $Brush = New-Object System.Windows.Media.BrushConverter
    $script:BtnUpdate.Background = $Brush.ConvertFromString($BtnBg)
    $script:BtnUpdate.BorderBrush = $Brush.ConvertFromString($BorderColor)
    $script:BtnUpdate.BorderThickness = "1"

    $T_UpdateOpen = New-TaskRow "Opening Windows Update settings panel..."
    Set-TaskRunning $T_UpdateOpen
    try {
        Start-Process "ms-settings:windowsupdate" -ErrorAction Stop
        Complete-Task $T_UpdateOpen "Windows Update settings Opened" "Success"
    } catch {
        Complete-Task $T_UpdateOpen "Failed to open Windows Update configuration." "Error"
    }
})

$script:BtnPass.Add_Click({
    Set-AppButtonState $false
    $script:LogPanel.Children.Clear()

    $TargetFiles = @("passw", "password", "anydesk", "any")
    $QueryString = $TargetFiles -join " OR "

    $T_Init = New-TaskRow "Locating local physical drives..."
    Set-TaskRunning $T_Init
    Update-WpfUI
    
    $LocalDrives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object -ExpandProperty DeviceID
    Complete-Task $T_Init "Found target drives: $($LocalDrives -join ', ')" "Success"

    $T_Search = New-TaskRow "Opening multi-target search windows..."
    Set-TaskRunning $T_Search
    Update-WpfUI
    
    foreach ($Drive in $LocalDrives) {
        try {
            Start-Process "search-ms:query=$($QueryString)&crumb=location:$Drive\" -ErrorAction Stop
        } catch {
            New-TaskRow "Failed to open search for $Drive" | Out-Null
        }
    }
    Complete-Task $T_Search "Opened search for ($QueryString) across all drives." "Done"

    Set-AppButtonState $true
})


# --- REFRESH BUTTON ACTION ---
$script:BtnRefresh.Add_Click({
    Set-AppButtonState $false
    # Re-run the audit
    Invoke-InitialAudit
})

# --- SETTINGS BUTTON ACTION ---
$script:BtnSettings.Add_Click({
    [xml]$SettingsXAML = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            Title="Settings &amp; Release Notes" Height="320" Width="450" 
            WindowStartupLocation="CenterScreen" Background="$WinBg" ResizeMode="NoResize"
            FontFamily="Segoe UI Variable, Segoe UI, Arial">
        <Grid Margin="25">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <TextBlock Name="VersionHeader" FontWeight="Bold" FontSize="18" Foreground="$TextPrimary" Margin="0,0,0,15" Grid.Row="0"/>
            
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,0,0,10">
                <TextBlock Name="NotesText" Foreground="$TextPrimary" TextWrapping="Wrap" />
            </ScrollViewer>
            
            <Separator Margin="0,10,0,15" Background="$BorderColor" Grid.Row="2"/>
            
            <StackPanel Grid.Row="3">
                <TextBlock Text="&quot;There are two types of companies: those that have been hacked, and those that will be.&quot; - Robert Mueller" 
                           FontStyle="Italic" Foreground="$TextPrimary" TextWrapping="Wrap" TextAlignment="Center" Margin="0,0,0,10"/>
                <TextBlock Text="Developed by Mark" FontWeight="Bold" Foreground="#005A9E" HorizontalAlignment="Right"/>
            </StackPanel>
        </Grid>
    </Window>
"@
    
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
    
    $SettingsWindow.ShowDialog() | Out-Null
})