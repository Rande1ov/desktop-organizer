<# : batch script
@echo off
setlocal
cd /d "%~dp0"

cls
echo ========================================================
echo        Desktop Organizer and Jamo Fixer - STOP
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p='%~f0'; & ([scriptblock]::Create((Get-Content -LiteralPath $p -Encoding UTF8 -Raw))) -BatchPath $p"
echo.
echo Desktop Organizer stopped successfully.
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 2"
exit /b 0
#>
param(
    [string]$BatchPath = ""
)

# --- PURE ENGLISH POWERSHELL SCRIPT ENGINE ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "[1/2] Removing startup trigger from shell:startup..."
$startupFolder = [Environment]::GetFolderPath('Startup')
$vbsPath = Join-Path $startupFolder "DesktopOrganizer_Startup.vbs"
if (Test-Path -LiteralPath $vbsPath) {
    Remove-Item -LiteralPath $vbsPath -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed: $vbsPath"
} else {
    Write-Host "  [Info] Startup trigger was not registered."
}

Write-Host "[2/2] Stopping background monitor processes..."
$scriptDir = Split-Path -Parent $BatchPath
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$pidFile = Join-Path $scriptDir "desktop_organizer.pid"

$stoppedCount = 0

# 1. Stop via PID file
if (Test-Path -LiteralPath $pidFile) {
    try {
        $savedPid = (Get-Content -LiteralPath $pidFile -Raw).Trim()
        if ($savedPid) {
            $p = Get-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue
            if ($p) {
                Stop-Process -Id $p.Id -Force
                Write-Host "  [OK] Terminated daemon process via PID file (PID: $($p.Id))"
                $stoppedCount++
            }
        }
    } catch {}
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

# 2. Auxiliary check: scan any leftover daemon powershell instances
$targetProcesses = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { 
    ($_.CommandLine -like "*DesktopOrganizer_Start.bat*") -or 
    ($_.CommandLine -like "*DesktopVerticalManager*") -or
    ($_.CommandLine -like "*-DaemonMode*")
}

foreach ($proc in $targetProcesses) {
    if ($proc.ProcessId -eq $PID) { continue }
    try {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
        Write-Host "  [OK] Terminated leftover daemon (PID: $($proc.ProcessId))"
        $stoppedCount++
    } catch {}
}

if ($stoppedCount -eq 0) {
    Write-Host "  [Info] No active background daemon found."
} else {
    Write-Host "  [OK] Total $stoppedCount daemon process(es) stopped."
}
