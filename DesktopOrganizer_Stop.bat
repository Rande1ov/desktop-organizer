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

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "[1/2] Removing Windows startup registrations..."
$taskName = "DesktopOrganizerDaemon"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch {}
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed Scheduled Task: $taskName"
} else {
    Write-Host "  [Info] Scheduled Task was not registered."
}

$runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
if (Get-ItemProperty -Path $runKeyPath -Name "DesktopOrganizer" -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKeyPath -Name "DesktopOrganizer" -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed registry Run entry: DesktopOrganizer"
}

$startupFolder = [Environment]::GetFolderPath('Startup')
$vbsPath = Join-Path $startupFolder "DesktopOrganizer_Startup.vbs"
if (Test-Path -LiteralPath $vbsPath) {
    Remove-Item -LiteralPath $vbsPath -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed legacy VBS: $vbsPath"
}

Write-Host "[2/2] Stopping background daemon processes..."
$stoppedCount = 0

$pidFiles = @(
    (Join-Path $env:LOCALAPPDATA "DesktopOrganizer\desktop_organizer.pid")
)
$scriptDir = Split-Path -Parent $BatchPath
if ($scriptDir) {
    $pidFiles += (Join-Path $scriptDir "desktop_organizer.pid")
}

foreach ($pf in $pidFiles) {
    if (Test-Path -LiteralPath $pf) {
        try {
            $savedPid = (Get-Content -LiteralPath $pf -Raw).Trim()
            if ($savedPid) {
                $p = Get-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue
                if ($p) {
                    Stop-Process -Id $p.Id -Force -ErrorAction Stop
                    Write-Host "  [OK] Terminated daemon via PID file (PID: $($p.Id))"
                    $stoppedCount++
                }
            }
        } catch {}
        Remove-Item -LiteralPath $pf -Force -ErrorAction SilentlyContinue
    }
}

$psProcs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'"
foreach ($proc in $psProcs) {
    if ($proc.ProcessId -eq $PID) { continue }
    $cmd = $proc.CommandLine
    if (-not $cmd) { continue }
    $isTarget = ($cmd -like "*DesktopOrganizer_Start.bat*-DaemonMode*") -or ($cmd -like "*DesktopOrganizerDaemon*")
    if (-not $isTarget -and $cmd -match '-EncodedCommand\s+([A-Za-z0-9+/=]+)') {
        try {
            $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($matches[1]))
            if ($decoded -like "*-DaemonMode*") {
                $isTarget = $true
            }
        } catch {}
    }
    if ($isTarget) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            Write-Host "  [OK] Terminated daemon process (PID: $($proc.ProcessId))"
            $stoppedCount++
        } catch {}
    }
}

if ($stoppedCount -eq 0) {
    Write-Host "  [Info] No active background daemon found."
} else {
    Write-Host "  [OK] Total $stoppedCount daemon process(es) stopped."
}
