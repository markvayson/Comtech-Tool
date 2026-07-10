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