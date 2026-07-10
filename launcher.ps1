# --- 0. ENFORCE ADMINISTRATOR RIGHTS AND STA THREADING ---
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$IsSTA = ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')

if (-not $IsAdmin -or -not $IsSTA) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction SilentlyContinue
    exit
}

# 1. Get the current directory of this main script
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }

# 2. Strict Module Loading (Fail fast if missing)
$Modules = @(
    "Prerequisites.ps1",
    "ThemeAndHelpers.ps1",
    "UserInterface.ps1",
    "InitialAudit.ps1",
    "Action_Baseline.ps1",
    "Action_Inventory.ps1",
    "Action_Misc.ps1",
    "Action_Settings.ps1"
)

foreach ($Mod in $Modules) {
    $ModPath = Join-Path $ScriptDir "Modules\$Mod"
    if (-not (Test-Path $ModPath)) {
        Write-Warning "CRITICAL: Cannot find required module: $ModPath"
        Read-Host "Press Enter to exit..."
        exit
    }
    . $ModPath
}

# 3. Launch the Application safely
$global:Form.ShowDialog() | Out-Null
