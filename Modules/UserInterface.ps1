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

                <Button Name="BtnUpdate" IsEnabled="False" Height="65" Margin="0,0,0,15" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE895;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Text="Windows Update" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>
                <Button Name="BtnRefresh" IsEnabled="False" Height="65" Margin="0,0,0,15" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xe72c;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Text="Refresh" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>
                <Button Name="BtnSettings" IsEnabled="False" Height="65" Margin="0,0,0,15" Style="{StaticResource ModernButton}">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets, Segoe UI Symbol" Text="&#xE713;" Margin="0,0,15,0" FontSize="20" VerticalAlignment="Center" Foreground="$HeaderIcon"/>
                        <TextBlock Text="Settings" FontWeight="SemiBold" VerticalAlignment="Center" FontSize="14"/>
                    </StackPanel>
                </Button>
            </StackPanel>
        </Grid>

        <Border Grid.Row="2" Margin="0,20,0,0" BorderBrush="$BorderColor" BorderThickness="0,1,0,0" Padding="0,15,0,0">
            <Grid>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,20,20" Grid.Row="2">
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