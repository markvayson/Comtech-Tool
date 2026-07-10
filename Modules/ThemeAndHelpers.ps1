# --- 0.5 DETECT SYSTEM THEME (DARK/LIGHT MODE) ---
$ThemeKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
$script:IsLightMode = $true 

if (Test-Path $ThemeKey) {
    $ThemeVal = Get-ItemProperty -Path $ThemeKey -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
    if ($null -ne $ThemeVal -and $ThemeVal.AppsUseLightTheme -eq 0) {
        $script:IsLightMode = $false
    }
}

if ($script:IsLightMode) {
    $WinBg = "#F3F4F6"
    $PanelBg = "White"
    $TextPrimary = "#111827"
    $BorderColor = "#E5E7EB"
    $BtnBg = "White"
    $BtnText = "#005A9E"
    $BtnHover = "#E5E7EB" # <-- ADDED
    $HeaderIcon = "#005A9E"
}
else {
    $WinBg = "#111827"
    $PanelBg = "#1F2937"
    $TextPrimary = "#F9FAFB"
    $BorderColor = "#374151"
    $BtnBg = "#1F2937"
    $BtnText = "#60A5FA"
    $BtnHover = "#374151" # <-- ADDED
    $HeaderIcon = "#60A5FA"
}


# Define global audit sentences for unified editing
$global:AuditText = @{
    UpdateCheck      = "Windows Update"
    ActivationStatus = "Windows Activation Status"
    OfficeVersion    = "Microsoft Office Version"
    WinRARVersion    = "WinRAR Version"
    LegacySSL        = "Legacy SSL/TLS (SSL 2.0, SSL 3.0, TLS 1.0, TLS 1.1)"
    TLS12            = "TLS 1.2"
    Ciphers          = "Weak Ciphers (DES, RC2, RC4)"
    SMBv1            = "SMBv1 Protocol"
    SMBSigning       = "SMB Signing"
    NetShares        = "File Shares and Printers"
    PrintShares      = "Shared Printers"
    LocalAcct        = "Local User Accounts"
    Bluetooth        = "Bluetooth"
    Browsers         = "Browser (Sign-in & Passwords)"
    Wifi             = "Wi-Fi"
    Finish           = "Finalizing Compliance Run"
}



Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DWM {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@ -ErrorAction SilentlyContinue

$script:ComplianceState = @{
    WeakCiphers = $false
    SSLOlder    = $false
    TLS12       = $false
    SMBv1       = $false
    Shares      = $false
    Printers    = $false
    LocalUsers  = $false
    Bluetooth   = $false
    Browsers    = $false
}

function Test-RegValue {
    param([string]$Path, [string]$Name, [int]$ExpectedValue)
    try {
        $val = Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop
        return ($val -eq $ExpectedValue)
    }
    catch { return $false }
}

function Update-WpfUI {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background, 
        [System.Action]({ $frame.Continue = $false })
    ) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function New-TaskRow {
    param([string]$PreText)
    
    $Grid = New-Object System.Windows.Controls.Grid
    $Grid.Margin = "0,6,0,6"
    
    $Col1 = New-Object System.Windows.Controls.ColumnDefinition; $Col1.Width = "35"
    $Col2 = New-Object System.Windows.Controls.ColumnDefinition; $Col2.Width = "*"
    $Col3 = New-Object System.Windows.Controls.ColumnDefinition; $Col3.Width = "85"
    
    $Grid.ColumnDefinitions.Add($Col1)
    $Grid.ColumnDefinitions.Add($Col2)
    $Grid.ColumnDefinitions.Add($Col3)

    $TxtIcon = New-Object System.Windows.Controls.TextBlock -Property @{ Text = "[ ]"; FontFamily = "Consolas"; FontSize = 14; HorizontalAlignment = "Left"; VerticalAlignment = "Center" }
    $TxtMessage = New-Object System.Windows.Controls.TextBlock -Property @{ Text = $PreText; FontSize = 13; TextWrapping = "Wrap"; VerticalAlignment = "Center" }
    $TxtTime = New-Object System.Windows.Controls.TextBlock -Property @{ Text = ""; FontSize = 12; VerticalAlignment = "Center"; HorizontalAlignment = "Right" }

    if ($script:IsLightMode) {
        $TxtIcon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#9CA3AF")
        $TxtMessage.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#9CA3AF")
    }
    else {
        $TxtIcon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#6B7280")
        $TxtMessage.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#6B7280")
    }

    [System.Windows.Controls.Grid]::SetColumn($TxtIcon, 0)
    [System.Windows.Controls.Grid]::SetColumn($TxtMessage, 1)
    [System.Windows.Controls.Grid]::SetColumn($TxtTime, 2)

    $Grid.Children.Add($TxtIcon) | Out-Null
    $Grid.Children.Add($TxtMessage) | Out-Null
    $Grid.Children.Add($TxtTime) | Out-Null

    $script:LogPanel.Children.Add($Grid) | Out-Null
    return [PSCustomObject]@{ Icon = $TxtIcon; Text = $TxtMessage; Time = $TxtTime }
}


# The ONLY place you ever need to add a new button name:
$script:ControlButtons = @(
    "BtnBaseline", 
    "BtnInventory", 
    "BtnUpdate", 
    "BtnPass", 
    "BtnRefresh", 
    "BtnSettings"
   
    )

$global:SecurityEnforced = $false

function global:Set-AppButtonState {
    param([bool]$Enabled)

    foreach ($Name in $script:ControlButtons) {
        $Btn = Get-Variable -Scope script -Name $Name -ValueOnly -ErrorAction SilentlyContinue
        if ($Btn) { $Btn.IsEnabled = $Enabled }
        if ($global:SecurityEnforced) {$global:BtnBaseline.isEnabled = $false}
    }
}

function Set-TaskRunning {
    param($TaskRef)
    $TaskRef.Icon.Text = "[>]"
    $TaskRef.Text.Text += " -> Checking..."
    if ($script:IsLightMode) {
        $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#D97706")
        $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#4B5563")
    }
    else {
        $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#FBBF24")
        $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#D1D5DB")
    }
    $script:LogScroller.ScrollToBottom()
    Update-WpfUI
}

function Complete-Task {
    param($TaskRef, [string]$PostText, [string]$Status = "Success")
    $TaskRef.Text.Text = $PostText
    $TaskRef.Time.Text = (Get-Date).ToString("hh:mm:ss tt")

    if ($script:IsLightMode) {
        $TimeColor = "#9CA3AF"
        if ($Status -eq "Success") {
            $TaskRef.Icon.Text = "[$([char]0x2713)]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#2563EB")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#374151")
        }
        elseif ($Status -eq "Done") {
            $TaskRef.Icon.Text = "[=]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#1aff00")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#374151")
        }
        elseif ($Status -eq "Warning") {
            $TaskRef.Icon.Text = "[!]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#D97706")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#92400E")
        }
        else {
            $TaskRef.Icon.Text = "[X]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#DC2626")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#991B1B")
        }
    }
    else {
        $TimeColor = "#6B7280"
        if ($Status -eq "Success") {
            $TaskRef.Icon.Text = "[$([char]0x2713)]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#60A5FA")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#E5E7EB")
        }
        elseif ($Status -eq "Done") {
            $TaskRef.Icon.Text = "[=]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#1aff00")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#E5E7EB")
        }
        elseif ($Status -eq "Warning") {
            $TaskRef.Icon.Text = "[!]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#FBBF24")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#FCD34D")
        }
        else {
            $TaskRef.Icon.Text = "[X]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#F87171")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#FCA5A5")
        }
    }
    $TaskRef.Time.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($TimeColor)
    $script:LogScroller.ScrollToBottom()
    Update-WpfUI
}

function Set-RegKey($Path, $Name, $Value, $Type = "DWord") {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force | Out-Null
}



function Show-ThemedInputBox {
    param([string]$Title, [string]$Message, [string]$DefaultText = "")
    
    [xml]$InputXAML = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="$Title" Height="220" Width="420" 
            WindowStartupLocation="CenterScreen" 
            Background="$WinBg" ResizeMode="NoResize"
            FontFamily="Segoe UI Variable, Segoe UI, Arial">
        <Grid Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Text="$Message" Foreground="$TextPrimary" FontSize="14" Margin="0,0,0,15" TextWrapping="Wrap"/>
            <TextBox Name="InputBox" Grid.Row="1" Text="$DefaultText" Foreground="$TextPrimary" Background="$PanelBg" BorderBrush="$BorderColor" BorderThickness="1" Padding="8" FontSize="14"/>
            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom">
                <Button Name="BtnOK" Content="OK" Width="80" Height="32" Margin="0,0,10,0" Background="$BtnBg" Foreground="$BtnText" BorderBrush="$BorderColor" BorderThickness="1" Cursor="Hand"/>
                <Button Name="BtnCancel" Content="Cancel" Width="80" Height="32" Background="$BtnBg" Foreground="$BtnText" BorderBrush="$BorderColor" BorderThickness="1" Cursor="Hand"/>
            </StackPanel>
        </Grid>
    </Window>
"@
    $InputReader = (New-Object System.Xml.XmlNodeReader $InputXAML)
    $InputForm = [System.Windows.Markup.XamlReader]::Load($InputReader)

    if ($CurrentExePath -like "*.exe") {
        try { $InputForm.Icon = $global:Form.Icon } catch {}
    }

    $InputForm.Add_SourceInitialized({
            if (-not $script:IsLightMode) {
                $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($InputForm)).Handle
                $darkMode = 1
                try { [DWM]::DwmSetWindowAttribute($hwnd, 20, [ref]$darkMode, 4) | Out-Null } catch {}
            }
        })

    $InputTextBox = $InputForm.FindName("InputBox")
    $BtnOK = $InputForm.FindName("BtnOK")
    $BtnCancel = $InputForm.FindName("BtnCancel")
    
    $InputTextBox.SelectAll()
    $script:InputResult = $null

    $BtnOK.Add_Click({ $script:InputResult = $InputTextBox.Text; $InputForm.Close() })
    $BtnCancel.Add_Click({ $script:InputResult = $null; $InputForm.Close() })

    $InputForm.ShowDialog() | Out-Null
    return $script:InputResult
}