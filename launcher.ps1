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

# --- 0. ENFORCE ADMINISTRATOR RIGHTS AND STA THREADING ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$IsSTA = ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')

if (-not $IsAdmin -or -not $IsSTA) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction SilentlyContinue
    exit
}

# --- 0.25 STANDALONE EXE AUTO-UPDATE MODULE ---
$CurrentVersion = "2.1.1"
$RepoUser       = "markvayson"   # <--- CHANGE TO YOUR GITHUB USERNAME
$RepoName       = "Comtech-Tool"         # <--- CHANGE TO YOUR REPOSITORY NAME
$Branch         = "main"

$CurrentExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

# Only run update checks if running as a compiled executable
if ($CurrentExePath -like "*.exe") {
    $VersionUrl = "https://raw.githubusercontent.com/$RepoUser/$RepoName/$Branch/version.txt"
    $ExeUrl     = "https://github.com/$RepoUser/$RepoName/raw/$Branch/adhicsv2.exe"

    try {
        $OnlineVersion = (Invoke-RestMethod -Uri $VersionUrl -UseBasicParsing -ErrorAction Stop).Trim()

        if ([version]$OnlineVersion -gt [version]$CurrentVersion) {
            $Directory = Split-Path $CurrentExePath
            $NewExePath = Join-Path $Directory "adhicsv2.new.exe"

            # Download the new compiled executable binary
            Invoke-WebRequest -Uri $ExeUrl -OutFile $NewExePath -UseBasicParsing -ErrorAction Stop

            # Background task script to swap files cleanly once this process terminates
            $UpdateWorker = @"
            Start-Sleep -Seconds 2
            Remove-Item -Path "$CurrentExePath" -Force -ErrorAction SilentlyContinue
            Move-Item -Path "$NewExePath" -Destination "$CurrentExePath" -Force
            Start-Process -FilePath "$CurrentExePath"
"@
            # Execute worker completely hidden
            Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -Command $UpdateWorker"
            exit
        }
    } catch {
        # Fallback: Safely bypass if offline or GitHub is unreachable
    }
}

# --- 0.5 DETECT SYSTEM THEME (DARK/LIGHT MODE) ---
$ThemeKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
$script:IsLightMode = $true 

if (Test-Path $ThemeKey) {
    $ThemeVal = Get-ItemProperty -Path $ThemeKey -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
    if ($null -ne $ThemeVal -and $ThemeVal.AppsUseLightTheme -eq 0) {
        $script:IsLightMode = $false
    }
}

# Assign Theme Variables
if ($script:IsLightMode) {
    $WinBg        = "#F3F4F6"
    $PanelBg      = "White"
    $TextPrimary  = "#111827"
    $BorderColor  = "#E5E7EB"
    $BtnBg        = "White"
    $BtnHover     = "#F9FAFB"
    $BtnText      = "#005A9E"
    $HeaderIcon   = "#005A9E"
} else {
    $WinBg        = "#111827"
    $PanelBg      = "#1F2937"
    $TextPrimary  = "#F9FAFB"
    $BorderColor  = "#374151"
    $BtnBg        = "#1F2937"
    $BtnHover     = "#374151"
    $BtnText      = "#60A5FA"
    $HeaderIcon   = "#60A5FA"
}

# --- DARK MODE TITLE BAR HELPER ---
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DWM {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@ -ErrorAction SilentlyContinue

# --- 1. DEFINE THE MAIN UI (XAML) ---
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

                    <ScrollViewer Name="LogScroller" Grid.Row="1" Margin="20,0,10,20" VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="LogPanel"/>
                    </ScrollViewer>
                </Grid>
            </Border>

            <StackPanel Grid.Column="1" VerticalAlignment="Top">
                <Button Name="BtnBaseline" Height="65" Margin="0,0,0,15" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xEA18;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Name="TxtBaseline" Text="Enforce ADHICSv2 Security" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>

                <Button Name="BtnInventory" Height="65" Margin="0,0,0,15" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE81E;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Name="TxtInventory" Text="Collect System Inventories" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>

                <Button Name="BtnPass" Height="65" Margin="0,0,0,15" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE71E;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Text="Search Pass" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>

                <Button Name="BtnUpdate" Height="65" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE895;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Text="Windows Update" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>
            </StackPanel>
        </Grid>

        <Border Grid.Row="2" Margin="0,20,0,0" BorderBrush="$BorderColor" BorderThickness="0,1,0,0" Padding="0,15,0,0">
            <Grid>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Center">
                    <Ellipse Width="8" Height="8" Fill="#3B82F6" Margin="0,0,10,0"/>
                    <TextBlock Name="StatusText" Text="Made by markvayson" Foreground="$TextPrimary" Opacity="0.8" FontSize="13"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE823;" FontSize="14" Foreground="$TextPrimary" Opacity="0.8" Margin="0,0,8,0" VerticalAlignment="Center"/>
                    <TextBlock Name="StatusBarTime" Text="Current Version: $CurrentVersion" Foreground="$TextPrimary" Opacity="0.8" FontSize="13" VerticalAlignment="Center"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# --- 2. LOAD UI AND MAP CONTROLS ---
$Reader = (New-Object System.Xml.XmlNodeReader $XAML)
$Form = [System.Windows.Markup.XamlReader]::Load($Reader)

# DYNAMIC WINDOW ICON EXTRACTION (Inherits EXE design natively)
if ($CurrentExePath -like "*.exe") {
    try {
        $AssociatedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($CurrentExePath)
        $IconBitmap = $AssociatedIcon.ToBitmap()
        $HBitmapHandle = $IconBitmap.GetHbitmap()
        $SizeOptions = [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
        $WpfIconSource = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap($HBitmapHandle, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty, $SizeOptions)
        $Form.Icon = $WpfIconSource
    } catch {}
}

$Form.Add_SourceInitialized({
    if (-not $script:IsLightMode) {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Form)).Handle
        $darkMode = 1
        try { [DWM]::DwmSetWindowAttribute($hwnd, 20, [ref]$darkMode, 4) | Out-Null } catch {}
    }
})

$script:LogPanel = $Form.FindName("LogPanel")
$script:LogScroller = $Form.FindName("LogScroller")
$script:BtnBaseline = $Form.FindName("BtnBaseline")
$script:BtnInventory = $Form.FindName("BtnInventory")
$script:BtnUpdate = $Form.FindName("BtnUpdate")
$script:BtnPass = $Form.FindName("BtnPass")

$script:TxtBaseline = $Form.FindName("TxtBaseline")
$script:TxtInventory = $Form.FindName("TxtInventory")

$script:BaselineClicked = $false
$script:InventoryClicked = $false

# Start Live Clock for the Status Bar
$ClockTimer = New-Object System.Windows.Threading.DispatcherTimer
$ClockTimer.Interval = [TimeSpan]::FromSeconds(1)
$ClockTimer.Add_Tick({
    if ($script:StatusBarTime) {
        $script:StatusBarTime.Text = (Get-Date).ToString("MMM dd, yyyy hh:mm tt")
    }
})
$ClockTimer.Start()

# --- 3. CORE HELPER FUNCTIONS FOR IN-PLACE UPDATING LOGS ---
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
    } else {
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
    return [PSCustomObject]@{ Icon=$TxtIcon; Text=$TxtMessage; Time=$TxtTime }
}

function Set-TaskRunning {
    param($TaskRef)
    $TaskRef.Icon.Text = "[>]"
    $TaskRef.Text.Text += " -> Checking..."
    if ($script:IsLightMode) {
        $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#D97706")
        $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#4B5563")
    } else {
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
        } elseif ($Status -eq "Done") {
            $TaskRef.Icon.Text = "[=]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#1aff00")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#374151")
        } elseif ($Status -eq "Warning") {
            $TaskRef.Icon.Text = "[!]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#D97706")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#92400E")
        } else {
            $TaskRef.Icon.Text = "[X]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#DC2626")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#991B1B")
        }
    } else {
        $TimeColor = "#6B7280"
        if ($Status -eq "Success") {
            $TaskRef.Icon.Text = "[$([char]0x2713)]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#60A5FA")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#E5E7EB")
        } elseif ($Status -eq "Done") {
            $TaskRef.Icon.Text = "[=]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#1aff00")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#E5E7EB")
        } elseif ($Status -eq "Warning") {
            $TaskRef.Icon.Text = "[!]"
            $TaskRef.Icon.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#FBBF24")
            $TaskRef.Text.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#FCD34D")
        } else {
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
        try { $InputForm.Icon = $Form.Icon } catch {}
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

# ==============================================================================
# BUTTON 1: SECURITY BASELINE & HARDENING
# ==============================================================================
$script:BtnBaseline.Add_Click({
    # Check if already clicked and prompt the user
    if ($script:BaselineClicked) {
        $Result = [System.Windows.MessageBox]::Show("You have already enforced the security baseline. Are you sure you want to run it again?", "Confirm Action", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($Result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    $script:BtnBaseline.IsEnabled = $false
    $script:BtnInventory.IsEnabled = $false
    $script:BtnUpdate.IsEnabled = $false
    $script:BtnPass.IsEnabled = $false
    $script:LogPanel.Children.Clear()
    
    $T_Update  = New-TaskRow "Security Update"
    $T_Act     = New-TaskRow "Windows Activation Status"
    $T_Office  = New-TaskRow "Microsoft Office Version"
    $T_WinRAR  = New-TaskRow "WinRAR Version"

    Update-WpfUI
    Start-Sleep -Milliseconds 600
    
    $CurrentDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $script:BaselineSummary = [ordered]@{ Hostname = $env:COMPUTERNAME; Scan_Date = $CurrentDate }

    Set-TaskRunning $T_Update
    $WarnUpdate = $false # Initialize warning flag
    $LastHotfix = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
    
    if ($null -ne $LastHotfix -and $null -ne $LastHotfix.InstalledOn) {
        $HotfixDate = $LastHotfix.InstalledOn.ToString("MMM/dd/yy")
        $script:BaselineSummary.Windows_Update = $HotfixDate
        
        $CurrentDate = Get-Date
        if ($LastHotfix.InstalledOn.Month -ne $CurrentDate.Month -or $LastHotfix.InstalledOn.Year -ne $CurrentDate.Year) {
            Complete-Task $T_Update "Security Update -> $($LastHotfix.HotfixID) on ($HotfixDate) - Check for updates." "Warning"
            $WarnUpdate = $true
        } else {
            Complete-Task $T_Update "Security Update -> $($LastHotfix.HotfixID) on ($HotfixDate)" "Success" 
        }
    } else { 
        $script:BaselineSummary.Windows_Update = "Never / Unknown"
        Complete-Task $T_Update "Security Update -> Unknown or Never" "Warning" 
        $WarnUpdate = $true
    }

    # --- HIGHLIGHT WINDOWS UPDATE BUTTON IF WARNING TRIGGERED ---
    if ($WarnUpdate) {
        $Brush = New-Object System.Windows.Media.BrushConverter
        $script:BtnUpdate.BorderBrush = $Brush.ConvertFromString("#F59E0B") # Bright Amber Border
        $script:BtnUpdate.BorderThickness = "2"
    }

    $T_SSL = New-TaskRow "SSL 2.0 / SSL 3.0 / TLS 1.0 / TLS 1.1"

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

    $T_TLS = New-TaskRow "TLS 1.2"

    Set-TaskRunning $T_Office
    $OfficeVer = "Not Detected"
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration") {
        $ProdId = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -Name ProductReleaseIds -ErrorAction SilentlyContinue).ProductReleaseIds
        $DisplayVer = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -Name VersionToReport -ErrorAction SilentlyContinue).VersionToReport
        $OfficeVer = "$ProdId (v$DisplayVer)"
    }
    $script:BaselineSummary.Office_EOL_Status = $OfficeVer
    Complete-Task $T_Office "Microsoft Office Version -> $OfficeVer" "Success"

    $T_Ciphers = New-TaskRow "Weak Ciphers"

    Set-TaskRunning $T_WinRAR
    $WinRarReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver" -ErrorAction SilentlyContinue
    $CurrentWinRar = if ($WinRarReg -and $WinRarReg.DisplayVersion) { $WinRarReg.DisplayVersion } else { "Not Installed" }
    $script:BaselineSummary.WinRAR = $CurrentWinRar

    if ($CurrentWinRar -eq "Not Installed") {
        $Shell = New-Object -ComObject WScript.Shell
        $DialogResult = $Shell.Popup("WinRAR is not currently installed.`n`nWould you like to install it now?", 3, "Install WinRAR?", 4132)
        if ($DialogResult -eq 6) {
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                $T_WinRAR.Text.Text = "Connecting to Windows Package Manager (Winget)..."
                Update-WpfUI
                $WingetArgs = @("install", "--id", "RARLab.WinRAR", "--exact", "--silent", "--accept-package-agreements", "--accept-source-agreements")
                $InstallProc = Start-Process -FilePath "winget" -ArgumentList $WingetArgs -Wait -PassThru -WindowStyle Hidden
                if ($InstallProc.ExitCode -eq 0 -or $InstallProc.ExitCode -match "1978335189|2316632043") { 
                    $script:BaselineSummary.WinRAR = "Newly Installed"
                    Complete-Task $T_WinRAR "WinRAR version -> Newly Installed via Winget" "Success"
                } else {
                    Complete-Task $T_WinRAR "Winget installation failed." "Error"
                }
            } else { Complete-Task $T_WinRAR "Winget not found." "Error" }
        } else {
            Complete-Task $T_WinRAR "WinRAR Installation -> skipped." "Warning"
        }
    } else {
        Complete-Task $T_WinRAR "WinRAR Version -> $CurrentWinRar" "Success"
    }

    $T_SMB = New-TaskRow "SMBv1 Termination & SMB Signing Enforcement"

    Set-TaskRunning $T_SSL
    $SchannelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
    foreach ($ver in @("SSL 2.0", "SSL 3.0", "TLS 1.0", "TLS 1.1")) {
        Set-RegKey "$SchannelPath\$ver\Client" "Enabled" 0; Set-RegKey "$SchannelPath\$ver\Server" "Enabled" 0
    }
    $script:BaselineSummary.SSL_Configured = "Configured"
    Complete-Task $T_SSL "SSL 2.0 / SSL 3.0 / TLS 1.0 / TLS 1.1 -> Disabled" "Success"

    $T_Shares = New-TaskRow "Shared Files and Folders"
    
    Set-TaskRunning $T_TLS
    $SchannelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
    Set-RegKey "$SchannelPath\TLS 1.2\Client" "Enabled" 1; Set-RegKey "$SchannelPath\TLS 1.2\Server" "Enabled" 1
    $script:BaselineSummary.TLS_Configured = "Configured"
    Complete-Task $T_TLS "TLS 1.2 -> Enabled" "Success"

    $T_Printers = New-TaskRow "Shared Printers"
    
    Set-TaskRunning $T_Ciphers
    $CipherPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers"
    $WeakCiphers = @("NULL", "DES 56/56", "RC2 40/128", "RC2 56/128", "RC2 128/128", "RC4 40/128", "RC4 56/128", "RC4 128/128", "Triple DES 168")
    foreach ($Cipher in $WeakCiphers) { Set-RegKey "$CipherPath\$Cipher" "Enabled" 0 }
    $script:BaselineSummary.Ciphers_Configured = "Configured"
    Complete-Task $T_Ciphers "Weak Ciphers -> Disabled" "Success"

    $T_Local = New-TaskRow "Local User Accounts"

    Set-TaskRunning $T_SMB
    try {
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue | Out-Null
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force -ErrorAction SilentlyContinue | Out-Null
    } catch { }
    Set-RegKey "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" 0
    $script:BaselineSummary.SMB_Configured = "Configured"
    Complete-Task $T_SMB "SMBv1 Termination & SMB Signing Enforcement -> Configured." "Success"

    $T_BT = New-TaskRow "Bluetooth"

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
    } else {
        $script:BaselineSummary.Shares_Removed = "None"
        Complete-Task $T_Shares "Shared Files and Folders -> None" "Success"
    }


    Set-TaskRunning $T_Printers
    $DroppedPrinters = @()
    $SharedPrinters = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared -eq $true }
    
    if ($SharedPrinters) {
        foreach ($Printer in $SharedPrinters) {
            Set-Printer -Name $Printer.Name -Shared $false -ErrorAction SilentlyContinue | Out-Null
            $DroppedPrinters += $Printer.Name
        }
        Complete-Task $T_Printers "Shared Printers: $($DroppedPrinters -join ', ') -> Unshared" "Warning"
    } else {
        $script:BaselineSummary.Printers_Removed = "None"
        Complete-Task $T_Printers "Shared Printers -> None" "Success"
    }

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

    # ==============================================================================
    # ADDED TASKS: WI-FI DISABLEMENT & BROWSER HARDENING
    # ==============================================================================
    
    $T_Wifi = New-TaskRow "WIFI"
    Set-TaskRunning $T_Wifi
    $WifiAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalMediaType -eq '802.11' -or $_.Name -match "Wi-Fi|Wireless" }
    if ($WifiAdapters) {
        $Names = @()
        foreach ($Adapter in $WifiAdapters) {
            Disable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            $Names += $Adapter.Name
        }
        $script:BaselineSummary.Wifi_Status = "Disabled"
        Complete-Task $T_Wifi "Wi-Fi adapters Disabled ($($Names -join ', '))" "Success"
    } else {
        $script:BaselineSummary.Wifi_Status = "Not Present / Already Disabled"
        Complete-Task $T_Wifi "No active Wi-Fi adapters found." "Success"
    }

    $T_Browser = New-TaskRow "Browser Sign-in and Saved Passwords"
    Set-TaskRunning $T_Browser
    $ChromePath = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    Set-RegKey $ChromePath "BrowserSignin" 0 "DWord"; Set-RegKey $ChromePath "PasswordManagerEnabled" 0 "DWord"
    
    $EdgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    Set-RegKey $EdgePath "BrowserSignin" 0 "DWord"; Set-RegKey $EdgePath "PasswordManagerEnabled" 0 "DWord"

    $script:BaselineSummary.Browser_Hardening = "Disabled"
    Complete-Task $T_Browser "Browser sign-in and password managers Disabled." "Success"

    # ==============================================================================

    Set-TaskRunning $T_Finish
    $ScriptDir = $PSScriptRoot
    if (-not $ScriptDir) { $ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
    $LogCsvPath = Join-Path $ScriptDir "Execution_Baseline_Summary_$($env:COMPUTERNAME).csv"
    
    [PSCustomObject]$script:BaselineSummary | Export-Csv -Path $LogCsvPath -Append -NoTypeInformation -Force
    Complete-Task $T_Finish "Compliance Run Complete. Log saved. Reboot suggested." "Done"

    # --- MARK AS CLICKED AND UPDATE VISUALS ---
    $script:BaselineClicked = $true
    $script:TxtBaseline.Text = "Enforce ADHICSv2 Security $([char]0x2713)"
    $Brush = New-Object System.Windows.Media.BrushConverter
    $script:BtnBaseline.BorderBrush = $Brush.ConvertFromString("#10B981") # Emerald Green
    $script:BtnBaseline.BorderThickness = "2"

    $script:BtnBaseline.IsEnabled = $true
    $script:BtnInventory.IsEnabled = $true
    $script:BtnUpdate.IsEnabled = $true
    $script:BtnPass.IsEnabled = $true
})

# ==============================================================================
# BUTTON 2: ASSET & SOFTWARE INVENTORY
# ==============================================================================
$script:BtnInventory.Add_Click({
    # Check if already clicked and prompt the user
    if ($script:InventoryClicked) {
        $Result = [System.Windows.MessageBox]::Show("You have already collected the system inventories. Are you sure you want to run it again?", "Confirm Action", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($Result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    $script:BtnBaseline.IsEnabled = $false
    $script:BtnInventory.IsEnabled = $false
    $script:BtnUpdate.IsEnabled = $false
    $script:BtnPass.IsEnabled = $false
    $script:LogPanel.Children.Clear()

    $T_Init   = New-TaskRow "Initialization: Executing Asset & Software Discovery..."
    $T_Soft   = New-TaskRow "Resolving Directory Structure & Writing Software Inventory..."
    $T_Asset  = New-TaskRow "Resolving Directory Structure & Writing Hardware Asset Inventory..."


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
        
        $DomainUsers = @()
        $Profiles = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { $_.Special -eq $false }
        
        foreach ($UserProfile in $Profiles) {
            try {
                $Account = Get-CimInstance Win32_UserAccount -Filter "SID='$($UserProfile.SID)'" -ErrorAction Stop
                if ($Account.LocalAccount -eq $false -and $Account.Disabled -eq $false) { $DomainUsers += $Account.Name }
            } catch { continue }
        }
        
        $AssetCustodian = if ($DomainUsers.Count -gt 0) { $DomainUsers -join ', ' } else { "None Detected" }

        $AssetData = [PSCustomObject]@{
            Description   = $Description
            Manufacturer  = $systemInfo.Manufacturer
            Model         = $systemInfo.Model
            Department    = $Department
            SerialNumber  = $biosInfo.SerialNumber
            SystemDetails = "Device: $Hostname | CPU: $($cpu.Name) | RAM: $($RAM)GB | OS: $osCaption $windowsVersion"
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

    $script:BtnBaseline.IsEnabled = $true
    $script:BtnInventory.IsEnabled = $true
    $script:BtnUpdate.IsEnabled = $true
    $script:BtnPass.IsEnabled = $true
})

# ==============================================================================
# BUTTON 3: WINDOWS UPDATE
# ==============================================================================
$script:BtnUpdate.Add_Click({
    # --- RESET BUTTON APPEARANCE TO DEFAULT ---
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

# ==============================================================================
# BUTTON 4: SEARCH MULTIPLE TARGETS (FILE EXPLORER UI)
# ==============================================================================
$script:BtnPass.Add_Click({
    $script:BtnBaseline.IsEnabled = $false
    $script:BtnInventory.IsEnabled = $false
    $script:BtnUpdate.IsEnabled = $false
    $script:BtnPass.IsEnabled = $false
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

# --- SHOW UI ---
$Form.ShowDialog() | Out-Null