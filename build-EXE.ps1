# ==============================================================================
# Build-EXE.ps1
# Automatically merges modular PowerShell scripts and compiles them to a single EXE
# (Includes embedded text file support)
# ==============================================================================

$ScriptDir = $PSScriptRoot
$ModulesDir = Join-Path $ScriptDir "Modules"
$TempScript = Join-Path $ScriptDir "Temp_Main.ps1"
$OutputFile = Join-Path $ScriptDir "Comtech-Tool.exe"

# 1. Ensure PS2EXE compiler is installed
if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "PS2EXE compiler not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}

# 2. Add the Elevation and STA threading block from your launcher
$HeaderCode = @"
# --- ENFORCE ADMINISTRATOR RIGHTS AND STA THREADING ---
`$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
`$IsSTA = ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')

if (-not `$IsAdmin -or -not `$IsSTA) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"`$PSCommandPath`"" -Verb RunAs -ErrorAction SilentlyContinue
    exit
}

# Fix for paths when running as a compiled EXE
`$ScriptDir = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
"@

$CombinedCode = [System.Collections.Generic.List[string]]::new()
$CombinedCode.Add($HeaderCode)

Write-Host "Merging files..." -ForegroundColor Cyan

# 3. Embed the Release Notes as a variable
$NotesPath = Join-Path $ModulesDir "ReleaseNotes.txt"
if (Test-Path $NotesPath) {
    $NotesContent = Get-Content $NotesPath -Raw
    $CombinedCode.Add("`n# ==========================================")
    $CombinedCode.Add("# START OF MODULE: Embedded Release Notes")
    $CombinedCode.Add("# ==========================================")
    $CombinedCode.Add("`$global:EmbeddedReleaseNotes = @`"`n$NotesContent`n`"@")
    Write-Host "-> Successfully embedded ReleaseNotes.txt" -ForegroundColor Green
} else {
    Write-Warning "Could not find $NotesPath to embed."
}

# 4. Define the exact order to merge your modules
$Modules = @(
    "Prerequisites.ps1",
    "ThemeAndHelpers.ps1",
    "UserInterface.ps1",
    "InitialAudit.ps1",
    "Action_Baseline.ps1",
    "Action_Inventory.ps1",
    "Action_Misc.ps1"
)

# 5. Read and combine all files
foreach ($Mod in $Modules) {
    $ModPath = Join-Path $ModulesDir $Mod
    if (Test-Path $ModPath) {
        $CombinedCode.Add("`n# ==========================================")
        $CombinedCode.Add("# START OF MODULE: $Mod")
        $CombinedCode.Add("# ==========================================")
        $CombinedCode.Add((Get-Content $ModPath -Raw))
    } else {
        Write-Warning "CRITICAL: Could not find $ModPath. Build aborted."
        exit
    }
}

# 6. Add the final trigger to launch the UI
$CombinedCode.Add("`n# --- LAUNCH THE APPLICATION ---")
$CombinedCode.Add("`$global:Form.ShowDialog() | Out-Null")

# 7. Save the merged code to a temporary file
Set-Content -Path $TempScript -Value ($CombinedCode -join "`n") -Encoding UTF8

Write-Host "Waiting for file to write to disk..." -ForegroundColor Yellow
Start-Sleep -Seconds 2 # <-- Gives Windows time to save the file

# Safety check to see if Antivirus deleted it
if (-not (Test-Path $TempScript)) {
    Write-Host "`nCRITICAL ERROR: Temp_Main.ps1 disappeared immediately after creation!" -ForegroundColor Red
    Write-Host "Your Antivirus (Windows Defender) is likely deleting it because it contains security-modifying code." -ForegroundColor Yellow
    Write-Host "Please add this folder to your Antivirus exclusions and try again." -ForegroundColor White
    exit
}
# 8. Compile the temporary script into an EXE
Write-Host "Compiling to $OutputFile..." -ForegroundColor Cyan
Invoke-ps2exe -InputFile $TempScript -OutputFile $OutputFile -NoConsole

# 9. Clean up the temporary file
if (Test-Path $OutputFile) {
    Remove-Item $TempScript -Force
    Write-Host "`nSUCCESS! Your single-file application has been built:" -ForegroundColor Green
    Write-Host $OutputFile -ForegroundColor White
} else {
    Write-Host "`nCompilation failed." -ForegroundColor Red
}