param(
    [switch]$NotificationOnly,
    [int]$ServerId = 0
)

$ErrorActionPreference = 'Stop'

# Ensure STA apartment state for WPF UI
if (-not $NotificationOnly -and [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-Sta',
        '-File', "`"$PSCommandPath`""
    )
    if ($ServerId -gt 0) { $argList += @('-ServerId', $ServerId) }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden
    exit
}

# Embedded C# helper to stream JSONL output asynchronously without blocking WPF UI
$csharpSource = @"
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;

public class SpeedtestCliRunner
{
    public ConcurrentQueue<string> OutputLines { get; private set; }
    public ConcurrentQueue<string> ErrorLines { get; private set; }
    public bool HasExited { get { return _process == null || _process.HasExited; } }
    public int ExitCode { get { return (_process != null && _process.HasExited) ? _process.ExitCode : -1; } }

    private Process _process;

    public SpeedtestCliRunner()
    {
        OutputLines = new ConcurrentQueue<string>();
        ErrorLines = new ConcurrentQueue<string>();
    }

    public void Start(string exePath, string arguments)
    {
        Stop();
        OutputLines = new ConcurrentQueue<string>();
        ErrorLines = new ConcurrentQueue<string>();

        var psi = new ProcessStartInfo
        {
            FileName = exePath,
            Arguments = arguments,
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        _process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        _process.OutputDataReceived += (s, e) =>
        {
            if (!string.IsNullOrWhiteSpace(e.Data))
                OutputLines.Enqueue(e.Data.Trim());
        };
        _process.ErrorDataReceived += (s, e) =>
        {
            if (!string.IsNullOrWhiteSpace(e.Data))
                ErrorLines.Enqueue(e.Data.Trim());
        };

        _process.Start();
        _process.BeginOutputReadLine();
        _process.BeginErrorReadLine();
    }

    public void Stop()
    {
        try
        {
            if (_process != null && !_process.HasExited)
            {
                _process.Kill();
                _process.WaitForExit(1000);
            }
        }
        catch { }
        finally
        {
            if (_process != null)
            {
                try { _process.Dispose(); } catch { }
                _process = null;
            }
        }
    }
}
"@

if (-not ('SpeedtestCliRunner' -as [type])) {
    Add-Type -TypeDefinition $csharpSource -Language CSharp
}

function Show-SpeedtestToast {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Body
    )
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

        $escapedTitle = [System.Security.SecurityElement]::Escape($Title)
        $escapedBody  = [System.Security.SecurityElement]::Escape($Body)

        $toastXmlString = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$escapedTitle</text>
            <text>$escapedBody</text>
        </binding>
    </visual>
</toast>
"@
        $xmlDoc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xmlDoc.LoadXml($toastXmlString)
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDoc)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    }
    catch {
        # Fallback if Windows Toast notifications are disabled
    }
}

function Resolve-SpeedtestBinary {
    $candidates = @(
        (Join-Path $PSScriptRoot 'bin\speedtest.exe'),
        (Join-Path $env:LOCALAPPDATA 'AliSpeedTest\bin\speedtest.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\speedtest.exe')
    )

    $wingetPkgRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $wingetPkgRoot) {
        $wingetExe = Get-ChildItem -Path $wingetPkgRoot -Filter 'speedtest.exe' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like '*Ookla.Speedtest.CLI*' } |
            Select-Object -First 1
        if ($wingetExe) {
            $candidates += $wingetExe.FullName
        }
    }

    $cmd = Get-Command 'speedtest.exe' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $candidates += $cmd.Source
    }

    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }

    # Auto-download official Ookla Speedtest CLI if not installed yet
    $targetDir  = Join-Path $env:LOCALAPPDATA 'AliSpeedTest\bin'
    $targetExe  = Join-Path $targetDir 'speedtest.exe'
    $tempZip    = Join-Path $env:TEMP 'ookla-speedtest-win64.zip'
    $downloadUrl = 'https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip'

    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing
    Expand-Archive -Path $tempZip -DestinationPath $targetDir -Force
    Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue

    if (Test-Path $targetExe) {
        return $targetExe
    }

    throw "Could not find or download official Ookla speedtest.exe."
}

# Notification-only headless mode
if ($NotificationOnly) {
    Show-SpeedtestToast -Title "Speedtest.net" -Body "Measuring your internet speed in the background..."
    try {
        $exe = Resolve-SpeedtestBinary
        $cliArgs = @('--format=json', '--accept-license', '--accept-gdpr')
        if ($ServerId -gt 0) { $cliArgs += "--server-id=$ServerId" }
        $rawJson = & $exe @cliArgs 2>$null
        $data = $rawJson | ConvertFrom-Json
        $downMbps = [math]::Round($data.download.bandwidth / 125000, 2)
        $upMbps   = [math]::Round($data.upload.bandwidth / 125000, 2)
        $pingMs   = [math]::Round($data.ping.latency, 1)
        Show-SpeedtestToast -Title "Speedtest Complete" -Body "Download: $downMbps Mbps | Upload: $upMbps Mbps | Ping: $pingMs ms"
    }
    catch {
        Show-SpeedtestToast -Title "Speedtest Failed" -Body $_.Exception.Message
    }
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Speedtest.net"
        Width="430" Height="375"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen"
        Topmost="True">
    <Border CornerRadius="16" Background="#0B1120" BorderBrush="#1E293B" BorderThickness="1.5" Margin="10">
        <Border.Effect>
            <DropShadowEffect BlurRadius="20" ShadowDepth="4" Opacity="0.6" Color="#000000"/>
        </Border.Effect>
        <Grid Margin="20,16,20,16">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <Grid Grid.Row="0" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Width="10" Height="10" CornerRadius="5" Background="#38BDF8" Margin="0,0,8,0" Name="StatusDot"/>
                    <TextBlock Text="SPEEDTEST.NET" FontFamily="Segoe UI" FontWeight="Bold" FontSize="14" Foreground="#F8FAFC"/>
                    <TextBlock Text="  &#x2022;  Official CLI API" FontFamily="Segoe UI" FontSize="11.5" Foreground="#64748B" VerticalAlignment="Center"/>
                </StackPanel>
                <Button Name="CloseBtn" Grid.Column="1" Content="&#x2715;" Width="28" Height="28"
                        Background="#1E293B" Foreground="#94A3B8" BorderThickness="0"
                        FontFamily="Segoe UI" FontSize="12" Cursor="Hand" ToolTip="Close (Esc)">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Background="{TemplateBinding Background}" CornerRadius="8">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Grid>

            <!-- Status & Progress Bar -->
            <StackPanel Grid.Row="1" Margin="0,0,0,14">
                <Grid Margin="0,0,0,6">
                    <TextBlock Name="StatusText" Text="Initializing Speedtest..." FontFamily="Segoe UI" FontSize="12.5" FontWeight="SemiBold" Foreground="#CBD5E1"/>
                    <TextBlock Name="PercentText" Text="0%" FontFamily="Segoe UI" FontSize="12" FontWeight="Bold" Foreground="#38BDF8" HorizontalAlignment="Right"/>
                </Grid>
                <Grid Height="6">
                    <Border CornerRadius="3" Background="#1E293B"/>
                    <ProgressBar Name="TestProgress" Minimum="0" Maximum="100" Value="0" Height="6"
                                 Background="Transparent" Foreground="#38BDF8" BorderThickness="0"/>
                </Grid>
            </StackPanel>

            <!-- Main Download / Upload Cards -->
            <Grid Grid.Row="2" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Download Card -->
                <Border Grid.Column="0" CornerRadius="12" Background="#131C31" BorderBrush="#1E293B" BorderThickness="1" Padding="14,12">
                    <StackPanel VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                            <TextBlock Text="&#x2193; DOWNLOAD" FontFamily="Segoe UI" FontSize="11" FontWeight="Bold" Foreground="#38BDF8"/>
                        </StackPanel>
                        <TextBlock Name="DownloadValue" Text="--" FontFamily="Segoe UI" FontSize="32" FontWeight="Bold" Foreground="#F8FAFC"/>
                        <TextBlock Text="Mbps" FontFamily="Segoe UI" FontSize="11.5" Foreground="#64748B"/>
                    </StackPanel>
                </Border>

                <!-- Upload Card -->
                <Border Grid.Column="2" CornerRadius="12" Background="#131C31" BorderBrush="#1E293B" BorderThickness="1" Padding="14,12">
                    <StackPanel VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                            <TextBlock Text="&#x2191; UPLOAD" FontFamily="Segoe UI" FontSize="11" FontWeight="Bold" Foreground="#C084FC"/>
                        </StackPanel>
                        <TextBlock Name="UploadValue" Text="--" FontFamily="Segoe UI" FontSize="32" FontWeight="Bold" Foreground="#F8FAFC"/>
                        <TextBlock Text="Mbps" FontFamily="Segoe UI" FontSize="11.5" Foreground="#64748B"/>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Secondary Metrics: Ping / Jitter / Loss -->
            <Grid Grid.Row="3" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0" CornerRadius="8" Background="#111827" BorderBrush="#1E293B" BorderThickness="1" Padding="10,7">
                    <StackPanel>
                        <TextBlock Text="PING" FontFamily="Segoe UI" FontSize="10" FontWeight="Bold" Foreground="#64748B"/>
                        <TextBlock Name="PingValue" Text="-- ms" FontFamily="Segoe UI" FontSize="14" FontWeight="Bold" Foreground="#34D399" Margin="0,2,0,0"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="2" CornerRadius="8" Background="#111827" BorderBrush="#1E293B" BorderThickness="1" Padding="10,7">
                    <StackPanel>
                        <TextBlock Text="JITTER" FontFamily="Segoe UI" FontSize="10" FontWeight="Bold" Foreground="#64748B"/>
                        <TextBlock Name="JitterValue" Text="-- ms" FontFamily="Segoe UI" FontSize="14" FontWeight="Bold" Foreground="#FBBF24" Margin="0,2,0,0"/>
                    </StackPanel>
                </Border>

                <Border Grid.Column="4" CornerRadius="8" Background="#111827" BorderBrush="#1E293B" BorderThickness="1" Padding="10,7">
                    <StackPanel>
                        <TextBlock Text="PACKET LOSS" FontFamily="Segoe UI" FontSize="10" FontWeight="Bold" Foreground="#64748B"/>
                        <TextBlock Name="LossValue" Text="--%" FontFamily="Segoe UI" FontSize="14" FontWeight="Bold" Foreground="#E2E8F0" Margin="0,2,0,0"/>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- ISP & Server Info -->
            <Border Grid.Row="4" CornerRadius="8" Background="#0F172A" Padding="10,6" Margin="0,0,0,12">
                <TextBlock Name="ServerInfoText" Text="Server: Detecting nearest Speedtest.net server..."
                           FontFamily="Segoe UI" FontSize="11.5" Foreground="#94A3B8" TextTrimming="CharacterEllipsis"/>
            </Border>

            <!-- Action Buttons -->
            <Grid Grid.Row="5">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="8"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Button Name="RetestBtn" Grid.Column="0" Content="&#x21BB;  Re-test" Height="32"
                        Background="#0284C7" Foreground="#FFFFFF" BorderThickness="0"
                        FontFamily="Segoe UI" FontSize="12" FontWeight="SemiBold" Cursor="Hand" IsEnabled="False">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="8">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsEnabled" Value="False">
                                    <Setter TargetName="BtnBorder" Property="Background" Value="#1E293B"/>
                                    <Setter Property="Foreground" Value="#475569"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>

                <Button Name="CopyBtn" Grid.Column="2" Content="Copy Result" Height="32"
                        Background="#1E293B" Foreground="#E2E8F0" BorderThickness="0"
                        FontFamily="Segoe UI" FontSize="12" FontWeight="SemiBold" Cursor="Hand" IsEnabled="False">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="8">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsEnabled" Value="False">
                                    <Setter Property="Foreground" Value="#475569"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>

                <Button Name="OpenUrlBtn" Grid.Column="4" Content="Web Certificate" Height="32"
                        Background="#1E293B" Foreground="#38BDF8" BorderThickness="0"
                        FontFamily="Segoe UI" FontSize="12" FontWeight="SemiBold" Cursor="Hand" IsEnabled="False">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border Name="BtnBorder" Background="{TemplateBinding Background}" CornerRadius="8">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsEnabled" Value="False">
                                    <Setter Property="Foreground" Value="#475569"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Set window icon if available
$icoPath = Join-Path $PSScriptRoot 'assets\speedtest.ico'
if (Test-Path $icoPath) {
    try {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($icoPath))
    } catch { }
}

# Grab UI Controls
$StatusDot      = $window.FindName('StatusDot')
$CloseBtn       = $window.FindName('CloseBtn')
$StatusText     = $window.FindName('StatusText')
$PercentText    = $window.FindName('PercentText')
$TestProgress   = $window.FindName('TestProgress')
$DownloadValue  = $window.FindName('DownloadValue')
$UploadValue    = $window.FindName('UploadValue')
$PingValue      = $window.FindName('PingValue')
$JitterValue    = $window.FindName('JitterValue')
$LossValue      = $window.FindName('LossValue')
$ServerInfoText = $window.FindName('ServerInfoText')
$RetestBtn      = $window.FindName('RetestBtn')
$CopyBtn        = $window.FindName('CopyBtn')
$OpenUrlBtn     = $window.FindName('OpenUrlBtn')

$brushConverter = New-Object System.Windows.Media.BrushConverter

# Shared state
$state = [hashtable]::Synchronized(@{
    Runner       = New-Object SpeedtestCliRunner
    ResultUrl    = ''
    SummaryText  = ''
    GotFinalData = $false
    IspName      = ''
    ServerLabel  = ''
})

# Allow dragging the borderless window
$window.Add_MouseLeftButtonDown({
    try { $window.DragMove() } catch { }
})

# Escape key closes window
$window.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
        $state.Runner.Stop()
        $window.Close()
    }
})

$CloseBtn.Add_Click({
    $state.Runner.Stop()
    $window.Close()
})

$CopyBtn.Add_Click({
    if ($state.SummaryText) {
        [System.Windows.Clipboard]::SetText($state.SummaryText)
        $CopyBtn.Content = "Copied!"
    }
})

$OpenUrlBtn.Add_Click({
    if ($state.ResultUrl) {
        Start-Process $state.ResultUrl
    }
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(80)

function Start-SpeedtestRun {
    $state.GotFinalData = $false
    $state.ResultUrl    = ''
    $state.SummaryText  = ''

    $DownloadValue.Text  = '--'
    $UploadValue.Text    = '--'
    $PingValue.Text      = '-- ms'
    $JitterValue.Text    = '-- ms'
    $LossValue.Text      = '--%'
    $ServerInfoText.Text = 'Server: Connecting to nearest Speedtest.net server...'
    $StatusText.Text     = 'Connecting to Speedtest.net...'
    $PercentText.Text    = '0%'
    $TestProgress.Value  = 2
    $StatusDot.Background = $brushConverter.ConvertFromString('#38BDF8')

    $RetestBtn.IsEnabled  = $false
    $CopyBtn.IsEnabled    = $false
    $CopyBtn.Content      = 'Copy Result'
    $OpenUrlBtn.IsEnabled = $false

    try {
        $exePath = Resolve-SpeedtestBinary
    }
    catch {
        $StatusText.Text = "Error: Could not find or download speedtest.exe"
        $StatusDot.Background = $brushConverter.ConvertFromString('#EF4444')
        $RetestBtn.IsEnabled = $true
        return
    }

    $cliArgs = '--format=jsonl --progress=yes --accept-license --accept-gdpr'
    if ($ServerId -gt 0) {
        $cliArgs += " --server-id=$ServerId"
    }

    Show-SpeedtestToast -Title "Speedtest.net" -Body "Measuring your internet speed..."
    $state.Runner.Start($exePath, $cliArgs)
    $timer.Start()
}

$timer.Add_Tick({
    $line = $null
    while ($state.Runner.OutputLines.TryDequeue([ref]$line)) {
        try {
            $evt = $line | ConvertFrom-Json
        }
        catch {
            continue
        }

        switch ($evt.type) {
            'testStart' {
                $state.IspName     = $evt.isp
                $state.ServerLabel = "$($evt.server.name) ($($evt.server.location))"
                $ServerInfoText.Text = "ISP: $($state.IspName)  |  Server: $($state.ServerLabel)"
                $StatusText.Text     = "Connected. Measuring latency..."
                $TestProgress.Value  = 8
                $PercentText.Text    = "8%"
            }
            'ping' {
                $lat = [math]::Round($evt.ping.latency, 1)
                $jit = [math]::Round($evt.ping.jitter, 1)
                $PingValue.Text   = "$lat ms"
                $JitterValue.Text = "$jit ms"
                $pct = [math]::Min(20, [math]::Max(8, [math]::Round($evt.ping.progress * 20)))
                $TestProgress.Value = $pct
                $PercentText.Text   = "$pct%"
                $StatusText.Text    = "Measuring Ping & Jitter..."
            }
            'download' {
                $mbps = [math]::Round($evt.download.bandwidth / 125000, 2)
                $DownloadValue.Text = "$mbps"
                $pct = [math]::Min(60, 20 + [math]::Round($evt.download.progress * 40))
                $TestProgress.Value = $pct
                $PercentText.Text   = "$pct%"
                $StatusText.Text    = "Testing Download Speed..."
            }
            'upload' {
                $mbps = [math]::Round($evt.upload.bandwidth / 125000, 2)
                $UploadValue.Text = "$mbps"
                $pct = [math]::Min(99, 60 + [math]::Round($evt.upload.progress * 39))
                $TestProgress.Value = $pct
                $PercentText.Text   = "$pct%"
                $StatusText.Text    = "Testing Upload Speed..."
            }
            'result' {
                $state.GotFinalData = $true
                $downMbps = [math]::Round($evt.download.bandwidth / 125000, 2)
                $upMbps   = [math]::Round($evt.upload.bandwidth / 125000, 2)
                $pingMs   = [math]::Round($evt.ping.latency, 1)
                $jitterMs = [math]::Round($evt.ping.jitter, 1)
                $lossPct  = if ($null -ne $evt.packetLoss) { [math]::Round($evt.packetLoss, 1) } else { 0 }

                $DownloadValue.Text = "$downMbps"
                $UploadValue.Text   = "$upMbps"
                $PingValue.Text     = "$pingMs ms"
                $JitterValue.Text   = "$jitterMs ms"
                $LossValue.Text     = "$lossPct%"

                if ($evt.isp -and $evt.server) {
                    $state.IspName     = $evt.isp
                    $state.ServerLabel = "$($evt.server.name) ($($evt.server.location))"
                    $ServerInfoText.Text = "ISP: $($state.IspName)  |  Server: $($state.ServerLabel)"
                }

                $TestProgress.Value   = 100
                $PercentText.Text     = "100%"
                $StatusText.Text      = "Speedtest Complete"
                $StatusDot.Background = $brushConverter.ConvertFromString('#34D399')

                if ($evt.result -and $evt.result.url) {
                    $state.ResultUrl = $evt.result.url
                    $OpenUrlBtn.IsEnabled = $true
                }

                $state.SummaryText = "Speedtest.net Result:`r`nDownload: $downMbps Mbps`r`nUpload: $upMbps Mbps`r`nPing: $pingMs ms (Jitter: $jitterMs ms)`r`nISP: $($state.IspName) | Server: $($state.ServerLabel)"
                if ($state.ResultUrl) {
                    $state.SummaryText += "`r`nURL: $($state.ResultUrl)"
                }

                $RetestBtn.IsEnabled = $true
                $CopyBtn.IsEnabled   = $true

                Show-SpeedtestToast -Title "Speedtest Complete" -Body "Download: $downMbps Mbps | Upload: $upMbps Mbps | Ping: $pingMs ms"
            }
        }
    }

    if ($state.Runner.HasExited) {
        $timer.Stop()
        $RetestBtn.IsEnabled = $true
        if (-not $state.GotFinalData) {
            $errLine = $null
            $errMsg = "Connection failed or speedtest was interrupted."
            while ($state.Runner.ErrorLines.TryDequeue([ref]$errLine)) {
                $errMsg = $errLine
            }
            $StatusText.Text      = "Test failed. Check connection and retry."
            $ServerInfoText.Text  = $errMsg
            $StatusDot.Background = $brushConverter.ConvertFromString('#EF4444')
        }
    }
})

$RetestBtn.Add_Click({
    Start-SpeedtestRun
})

$window.Add_ContentRendered({
    # Drop always-on-top after initial popup so it doesn't block other apps if user clicks away
    $window.Topmost = $false
    Start-SpeedtestRun
})

$window.Add_Closed({
    $timer.Stop()
    $state.Runner.Stop()
})

[void]$window.ShowDialog()
