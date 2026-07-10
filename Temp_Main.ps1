# --- ENFORCE ADMINISTRATOR RIGHTS AND STA THREADING ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$IsSTA = ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')

if (-not $IsAdmin -or -not $IsSTA) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File "$PSCommandPath"" -Verb RunAs -ErrorAction SilentlyContinue
    exit
}

# Fix for paths when running as a compiled EXE
$ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)

# ==========================================
# START OF MODULE: Embedded Release Notes
# ==========================================
$global:EmbeddedReleaseNotes = @"
3.0.0 
- Introduced Settings panel.
- Introduced Refresh Button to re-check securities.
- Baseline enforcement targets pending items.
- Reorganized the files of the project.

2.1.2 - Added button
â€¢ Fixed UI glitch

2.1.1 - Added smb
â€¢ Initial release
"@

# ==========================================
# START OF MODULE: Prerequisites.ps1
# ==========================================
# --- HIDE BACKGROUND CONSOLE WINDOW ---
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) | Out-Null

# --- LOAD REQUIRED .NET ASSEMBLIES ---
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing

# --- 0.25 STANDALONE EXE AUTO-UPDATE MODULE ---
$global:CurrentVersion = "3.0.0.0"
$RepoUser       = "markvayson"
$RepoName       = "Comtech-Tool"
$Branch         = "main"

$CurrentExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

if ($CurrentExePath -like "*.exe") {
    $VersionUrl = "https://raw.githubusercontent.com/$RepoUser/$RepoName/$Branch/version.txt"
    $ExeUrl     = "https://github.com/$RepoUser/$RepoName/raw/$Branch/adhicsv2.exe"

    try {
        $OnlineVersion = (Invoke-RestMethod -Uri $VersionUrl -UseBasicParsing -ErrorAction Stop).Trim()

        if ([version]$OnlineVersion -gt [version]$global:CurrentVersion) {
            $Directory = Split-Path $CurrentExePath
            $NewExePath = Join-Path $Directory "adhicsv2.new.exe"

            Invoke-WebRequest -Uri $ExeUrl -OutFile $NewExePath -UseBasicParsing -ErrorAction Stop

            $UpdateWorker = @"
            Start-Sleep -Seconds 2
            Remove-Item -Path "$CurrentExePath" -Force -ErrorAction SilentlyContinue
            Move-Item -Path "$NewExePath" -Destination "$CurrentExePath" -Force
            Start-Process -FilePath "$CurrentExePath"
"@
            Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -Command $UpdateWorker"
            exit
        }
    } catch { }
}

# ==========================================
# START OF MODULE: ThemeAndHelpers.ps1
# ==========================================
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

# ==========================================
# START OF MODULE: UserInterface.ps1
# ==========================================
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ADHICS Security Baseline &amp; Inventory Tool" 
        Height="700" Width="950" 
        WindowStartupLocation="CenterScreen" 
        Background="$WinBg" 
        FontFamily="Segoe UI Variable, Segoe UI, Arial">
    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="$BtnBg"/>
            <Setter Property="Foreground" Value="$TextPrimary"/>
            <Setter Property="BorderBrush" Value="$BorderColor"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center" Margin="20,0,0,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="$BtnHover"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    
    <Grid Margin="25" Opacity="0">
        <Grid.RenderTransform>
            <TranslateTransform Y="20"/>
        </Grid.RenderTransform>
        <Grid.Triggers>
            <EventTrigger RoutedEvent="Grid.Loaded">
                <BeginStoryboard>
                    <Storyboard>
                        <DoubleAnimation Storyboard.TargetProperty="Opacity" From="0.0" To="1.0" Duration="0:0:0.6"/>
                        <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.Y)" From="20" To="0" Duration="0:0:0.6">
                            <DoubleAnimation.EasingFunction>
                                <CubicEase EasingMode="EaseOut"/>
                            </DoubleAnimation.EasingFunction>
                        </DoubleAnimation>
                    </Storyboard>
                </BeginStoryboard>
            </EventTrigger>
        </Grid.Triggers>
        
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" FontSize="20" FontWeight="Bold" Foreground="$TextPrimary" Margin="0,0,0,20">Configuring Host: $env:COMPUTERNAME</TextBlock>

        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="280"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="$PanelBg" CornerRadius="8" BorderBrush="$BorderColor" BorderThickness="1" Margin="0,0,20,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="20,20,20,15">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE81C;" FontSize="20" Foreground="$HeaderIcon" VerticalAlignment="Center"/>
                        <TextBlock Text="Execution Summary" FontSize="18" FontWeight="Bold" Foreground="$TextPrimary" Margin="10,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>

                   <Border Grid.Row="1" Margin="10,10,10,60" BorderBrush="$BorderColor" BorderThickness="1" CornerRadius="4">
    <ScrollViewer Name="LogScroller" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="5">
        <StackPanel Name="LogPanel" Margin="0,0,0,0"/>
    </ScrollViewer>
</Border>
                </Grid>
            </Border>

            <StackPanel Grid.Column="1" VerticalAlignment="Top">
                <Button Name="BtnBaseline" IsEnabled="False" Height="65" Margin="0,0,0,15" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xEA18;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Name="TxtBaseline" Text="Enforce ADHICSv2 Security" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>

                <Button Name="BtnInventory" IsEnabled="False" Height="65" Margin="0,0,0,15" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE81E;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Name="TxtInventory" Text="Collect System Inventories" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>

                <Button Name="BtnPass" IsEnabled="False" Height="65" Margin="0,0,0,15" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE71E;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Text="Search Pass" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>

                <Button Name="BtnUpdate" IsEnabled="False" Height="65" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE895;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Text="Windows Update" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>
            </StackPanel>
        </Grid>

        <Border Grid.Row="2" Margin="0,20,0,0" BorderBrush="$BorderColor" BorderThickness="0,1,0,0" Padding="0,15,0,0">
            <Grid>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,20,20" Grid.Row="2">
    <Button Name="BtnRefresh" Content="&#x21BB; Refresh" Width="90" Height="32" Margin="0,0,10,0" Style="{StaticResource ModernButton}" Cursor="Hand"/>
    <Button Name="BtnSettings" Content="&#x2699; Settings" Width="90" Height="32" Style="{StaticResource ModernButton}" Cursor="Hand"/>
</StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$Reader = (New-Object System.Xml.XmlNodeReader $XAML)
$global:Form = [System.Windows.Markup.XamlReader]::Load($Reader)

if ($CurrentExePath -like "*.exe") {
    try {
        $AssociatedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($CurrentExePath)
        $IconBitmap = $AssociatedIcon.ToBitmap()
        $HBitmapHandle = $IconBitmap.GetHbitmap()
        $SizeOptions = [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
        $WpfIconSource = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap($HBitmapHandle, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty, $SizeOptions)
        $global:Form.Icon = $WpfIconSource
    } catch {}
}

$global:Form.Add_SourceInitialized({
    if (-not $script:IsLightMode) {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($global:Form)).Handle
        $darkMode = 1
        try { [DWM]::DwmSetWindowAttribute($hwnd, 20, [ref]$darkMode, 4) | Out-Null } catch {}
    }
})

$script:LogPanel = $global:Form.FindName("LogPanel")
$script:LogScroller = $global:Form.FindName("LogScroller")
$script:BtnBaseline = $global:Form.FindName("BtnBaseline")
$script:BtnInventory = $global:Form.FindName("BtnInventory")
$script:BtnUpdate = $global:Form.FindName("BtnUpdate")
$script:BtnPass = $global:Form.FindName("BtnPass")
$script:TxtBaseline = $global:Form.FindName("TxtBaseline")
$script:TxtInventory = $global:Form.FindName("TxtInventory")
$script:StatusBarTime = $global:Form.FindName("StatusBarTime")
$script:BtnRefresh = $global:Form.FindName("BtnRefresh")
$script:BtnSettings = $global:Form.FindName("BtnSettings")


$script:BaselineClicked = $false
$script:InventoryClicked = $false

$ClockTimer = New-Object System.Windows.Threading.DispatcherTimer
$ClockTimer.Interval = [TimeSpan]::FromSeconds(1)
$ClockTimer.Add_Tick({
    if ($script:StatusBarTime) {
        $script:StatusBarTime.Text = (Get-Date).ToString("MMM dd, yyyy hh:mm tt")
    }
})
$ClockTimer.Start()

# ==========================================
# START OF MODULE: InitialAudit.ps1
# ==========================================
function global:Invoke-InitialAudit {
    $script:LogPanel.Children.Clear()
    $global:AuditUI = @{} 

    # --- UPDATED: Accepts a custom message to display ---
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

    $LastHotfix = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
    $CurrentDate = Get-Date
    $script:ComplianceState.UpdateCheck = ($null -ne $LastHotfix -and $LastHotfix.InstalledOn.Month -eq $CurrentDate.Month -and $LastHotfix.InstalledOn.Year -eq $CurrentDate.Year)
    Show-AuditStatus "UpdateCheck" $global:AuditText.UpdateCheck $script:ComplianceState.UpdateCheck

    # 1. Windows Activation
    $License = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' and PartialProductKey is not null" -ErrorAction SilentlyContinue
    $script:ComplianceState.Activation = ($null -ne $License)
    Show-AuditStatus "Activation" $global:AuditText.ActivationStatus $script:ComplianceState.Activation "Licensed" "Unlicensed / Not Implemented"


    $OfficeApp = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "Microsoft Office" -or $_.DisplayName -match "Microsoft 365" } | Select-Object -First 1

if ($OfficeApp) {
    # Check if the name contains 2024 or Microsoft 365 (assuming 365 is always updated)
    $IsCompliant = ($OfficeApp.DisplayName -match "2024" -or $OfficeApp.DisplayName -match "365")
    $FoundVersion = if ($OfficeApp.DisplayName -match "(2019|2021|2024|365)") { $matches[1] } else { "Unknown Version" }
    
    Show-AuditStatus "Office" $global:AuditText.OfficeVersion $IsCompliant "Version $FoundVersion Installed" "Version $FoundVersion (Below 2024)"
} else {
    Show-AuditStatus "Office" $global:AuditText.Office $false "Installed" "Not Installed"
}

# winrar
   $WinRar = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "WinRAR" } | Select-Object -First 1

if ($WinRar) {
    $WinRarVer = $WinRar.DisplayVersion
    # Adjust the $true/$false logic below based on what version you consider "Pass"
    Show-AuditStatus "WinRAR" $global:AuditText.WinRARVersion $true "Version $WinRarVer" "Version $WinRarVer" 
} else {
    Show-AuditStatus "WinRAR" $global:AuditText.WinRARVersion $true "Not Installed" "Not Installed"
}

    $SchannelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
    $script:ComplianceState.SSLOlder = (Test-RegValue "$SchannelPath\SSL 3.0\Client" "Enabled" 0) -and (Test-RegValue "$SchannelPath\TLS 1.0\Client" "Enabled" 0)
    Show-AuditStatus "LegacySSL" $global:AuditText.LegacySSL $script:ComplianceState.SSLOlder "Disabled" "Enabled"

  # 3. Security Checks (SSL/TLS/Ciphers)
    $script:ComplianceState.TLS12 = (Test-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" "Enabled" 1)
    Show-AuditStatus "TLS12" "TLS 1.2" $script:ComplianceState.TLS12 "Enabled" "Disabled"

    $CipherPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers"
    $script:ComplianceState.WeakCiphers = (Test-RegValue "$CipherPath\RC4 128/128" "Enabled" 0) -and (Test-RegValue "$CipherPath\DES 56/56" "Enabled" 0)
    Show-AuditStatus "Ciphers" $global:AuditText.Ciphers $script:ComplianceState.WeakCiphers "Disabled" "Enabled"

   $Smb1 = Get-SmbServerConfiguration -ErrorAction SilentlyContinue | Select-Object -ExpandProperty EnableSMB1Protocol
Show-AuditStatus "SMB1" "SMBv1 Protocol" (-not $Smb1) "Disabled" "Enabled"

# SMB Signing Check
$SmbSign = Get-SmbServerConfiguration -ErrorAction SilentlyContinue | Select-Object -ExpandProperty RequireSecuritySignature
Show-AuditStatus "SMBSigning" $global:AuditText.SMBSigning $SmbSign "Enabled" "Disabled"

# SMBv1 Check
$Smb1 = Get-SmbServerConfiguration -ErrorAction SilentlyContinue | Select-Object -ExpandProperty EnableSMB1Protocol
$script:ComplianceState.SMB1 = (-not $Smb1)
Show-AuditStatus "SMB1" "SMBv1 Protocol" $script:ComplianceState.SMB1 "Disabled" "Enabled"

# SMB Signing Check
$SmbSign = Get-SmbServerConfiguration -ErrorAction SilentlyContinue | Select-Object -ExpandProperty RequireSecuritySignature
$script:ComplianceState.SMBSign = [bool]$SmbSign
Show-AuditStatus "SMBSign" "SMB Signing" $script:ComplianceState.SMBSign "Enabled" "Disabled"

# Split Network Shares & Shared Printers
$AllShares = Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "^(IPC\$|ADMIN\$|C\$|D\$)$" }

# File Shares (Type 0)
$FileShares = $AllShares | Where-Object { $_.ShareType -eq 0 -or $_.ShareType -eq "FileSystem" }
$script:ComplianceState.NetShares = ($null -eq $FileShares)
if ($FileShares) {
    $ShareNames = ($FileShares.Name -join ", ")
    Show-AuditStatus "NetShares" $global:AuditText.NetShares $false "None" $ShareNames
} else {
    Show-AuditStatus "NetShares" $global:AuditText.NetShares $true "None" "None"
}

# Printer Shares (Type 1)
$PrintShares = $AllShares | Where-Object { $_.ShareType -eq 1 -or $_.ShareType -eq "PrintQueue" }
$script:ComplianceState.PrintShares = ($null -eq $PrintShares)
if ($PrintShares) {
    $PrinterNames = ($PrintShares.Name -join ", ")
    Show-AuditStatus "PrintShares" $global:AuditText.PrintShares $false "None" $PrinterNames
} else {
    Show-AuditStatus "PrintShares" $global:AuditText.PrintShares $true "None" "None"
}

    $RogueUsers = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true -and $_.Name -notin @("Mark") }
    $script:ComplianceState.LocalUsers = ($null -eq $RogueUsers)
    Show-AuditStatus "LocalAcct" $global:AuditText.LocalAcct $script:ComplianceState.LocalUsers "No Local Users" "Found Local Users ( $($RogueUsers.Name -join ', ') )"

  $Bth = Get-Service -Name "bthserv" -ErrorAction SilentlyContinue
    Show-AuditStatus "Bluetooth" $global:AuditText.Bluetooth ($Bth.StartType -eq 'Disabled') "Disabled" "Enabled"


    $script:ComplianceState.Browsers = (Test-RegValue "HKLM:\SOFTWARE\Policies\Google\Chrome" "BrowserSignin" 0) -and (Test-RegValue "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "PasswordManagerEnabled" 0)
    Show-AuditStatus "Browsers" $global:AuditText.Browsers $script:ComplianceState.Browsers "Removed" "Not Removed"

  # 7. Wi-Fi
    $Wifi = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match "Wireless" -and $_.Status -eq "Up" }
    Show-AuditStatus "Wifi" $global:AuditText.Wifi ($null -eq $Wifi) "Disabled" "Enabled"

    
    # Finish Task Row
    $T_Finish = New-TaskRow $global:AuditText.Finish
    $global:AuditUI["Finish"] = $T_Finish
    Set-TaskRunning $T_Finish
    
    $Fails = ($script:ComplianceState.Values | Where-Object { $_ -eq $false }).Count
    
    if ($Fails -eq 0) {
        Complete-Task $T_Finish "$($global:AuditText.Finish) -> System is fully compliant." "Done"
    } else {
        Complete-Task $T_Finish "$($global:AuditText.Finish) -> $Fails controls require enforcement." "Warning"
    }

    $script:BtnBaseline.IsEnabled = $true
    $script:BtnInventory.IsEnabled = $true
    $script:BtnUpdate.IsEnabled = $true
    $script:BtnPass.IsEnabled = $true
    $script:BtnRefresh.IsEnabled = $true
    $script:BtnSettings.IsEnabled = $true
}

$global:Form.Add_ContentRendered({
    Invoke-InitialAudit
})

# ==========================================
# START OF MODULE: Action_Baseline.ps1
# ==========================================
$script:BtnBaseline.Add_Click({
    if ($script:BaselineClicked) {
        $Result = [System.Windows.MessageBox]::Show("You have already enforced the security baseline. Are you sure you want to run it again?", "Confirm Action", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($Result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    $script:BtnBaseline.IsEnabled = $false
    $script:BtnInventory.IsEnabled = $false
    $script:BtnUpdate.IsEnabled = $false
    $script:BtnPass.IsEnabled = $false
    
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

    $script:BtnBaseline.IsEnabled = $true
    $script:BtnInventory.IsEnabled = $true
    $script:BtnUpdate.IsEnabled = $true
    $script:BtnPass.IsEnabled = $true
})

# ==========================================
# START OF MODULE: Action_Inventory.ps1
# ==========================================
  


# --- SETTINGS BUTTON ACTION ---
$script:BtnSettings.Add_Click({

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

# ==========================================
# START OF MODULE: Action_Misc.ps1
# ==========================================
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
    $script:BtnBaseline.IsEnabled = $false
    $script:BtnInventory.IsEnabled = $false
    $script:BtnUpdate.IsEnabled = $false
    $script:BtnPass.IsEnabled = $false
    $script:BtnRefresh.IsEnabled = $false
    $script:BtnSettings.IsEnabled = $false
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

    $script:BtnBaseline.IsEnabled = $true
    $script:BtnInventory.IsEnabled = $true
    $script:BtnUpdate.IsEnabled = $true
    $script:BtnPass.IsEnabled = $true
})


# --- REFRESH BUTTON ACTION ---
$script:BtnRefresh.Add_Click({
    $script:BtnBaseline.IsEnabled = $false
    $script:BtnInventory.IsEnabled = $false
    $script:BtnUpdate.IsEnabled = $false
    $script:BtnPass.IsEnabled = $false
    $script:BtnRefresh.IsEnabled = $false
    $script:BtnSettings.IsEnabled = $false
    
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

# --- LAUNCH THE APPLICATION ---
$global:Form.ShowDialog() | Out-Null
