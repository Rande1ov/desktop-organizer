<# : batch script
@echo off
setlocal
cd /d "%~dp0"

:: Check if launched with -daemon flag
if "%~1"=="-daemon" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$p='%~f0'; & ([scriptblock]::Create((Get-Content -LiteralPath $p -Encoding UTF8 -Raw))) -DaemonMode -BatchPath $p"
    exit /b 0
)

:: Normal User Launch (Interactive)
cls
echo ========================================================
echo        Desktop 3-Column Organizer and Jamo Fixer
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p='%~f0'; & ([scriptblock]::Create((Get-Content -LiteralPath $p -Encoding UTF8 -Raw))) -BatchPath $p"
echo.
echo Process complete. This window will close shortly.
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 2"
exit /b 0
#>
param(
    [switch]$DaemonMode = $false,
    [string]$BatchPath = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- WIN32 / COM C# DEFINITION ---
$cSharpCode = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class DesktopCore {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr OpenDesktop(string lpszDesktop, uint dwFlags, bool fInherit, uint dwDesiredAccess);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetThreadDesktop(IntPtr hDesktop);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, string lpszClass, string lpszWindow);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    public static extern bool RedrawWindow(IntPtr hWnd, IntPtr lprcUpdate, IntPtr hrgnUpdate, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool VirtualFreeEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint dwFreeType);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, ref LVITEM lpBuffer, uint nSize, out IntPtr lpNumberOfBytesWritten);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out IntPtr lpNumberOfBytesRead);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public const uint LVM_FIRST = 0x1000;
    public const uint LVM_GETITEMCOUNT = LVM_FIRST + 4;
    public const uint LVM_GETITEMTEXTW = LVM_FIRST + 115;
    public const uint LVM_SETITEMPOSITION = LVM_FIRST + 15;

    public const int GWL_STYLE = -16;
    public const int LVS_AUTOARRANGE = 0x0100;

    public const uint RDW_INVALIDATE = 0x0001;
    public const uint RDW_ERASE = 0x0004;
    public const uint RDW_UPDATENOW = 0x0100;

    public const int SM_CXICONSPACING = 38;
    public const int SM_CYICONSPACING = 39;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct LVITEM {
        public uint mask;
        public int iItem;
        public int iSubItem;
        public uint state;
        public uint stateMask;
        public IntPtr pszText;
        public int cchTextMax;
        public int iImage;
        public IntPtr lParam;
        public int iIndent;
        public int iGroupId;
        public uint cColumns;
        public IntPtr puColumns;
        public IntPtr piColFmt;
        public int iGroup;
    }

    public class RawItem {
        public int Index;
        public string Name;
    }

    public static IntPtr FindListView() {
        IntPtr hProgman = FindWindow("Progman", null);
        IntPtr hDefView = FindWindowEx(hProgman, IntPtr.Zero, "SHELLDLL_DefView", null);
        if (hDefView == IntPtr.Zero) {
            EnumWindows((hWnd, lParam) => {
                IntPtr c = FindWindowEx(hWnd, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (c != IntPtr.Zero) {
                    hDefView = c;
                    return false;
                }
                return true;
            }, IntPtr.Zero);
        }
        if (hDefView != IntPtr.Zero) {
            return FindWindowEx(hDefView, IntPtr.Zero, "SysListView32", null);
        }
        return IntPtr.Zero;
    }

    public static void DisableAutoArrange(IntPtr hListView) {
        int style = GetWindowLong(hListView, GWL_STYLE);
        if ((style & LVS_AUTOARRANGE) != 0) {
            SetWindowLong(hListView, GWL_STYLE, style & ~LVS_AUTOARRANGE);
        }
    }

    public static List<RawItem> GetDesktopItems(out IntPtr outHwnd) {
        List<RawItem> list = new List<RawItem>();
        IntPtr hList = IntPtr.Zero;

        Thread t = new Thread(() => {
            IntPtr hDefault = OpenDesktop("Default", 0, false, 0x01FF);
            if (hDefault != IntPtr.Zero) {
                SetThreadDesktop(hDefault);
            }
            hList = FindListView();
            if (hList == IntPtr.Zero) return;

            DisableAutoArrange(hList);

            int count = (int)SendMessage(hList, LVM_GETITEMCOUNT, IntPtr.Zero, IntPtr.Zero);
            uint pid;
            GetWindowThreadProcessId(hList, out pid);

            IntPtr hProc = OpenProcess(0x0038, false, pid);
            if (hProc == IntPtr.Zero) return;

            int bufferSize = 512;
            IntPtr pMem = VirtualAllocEx(hProc, IntPtr.Zero, (uint)(Marshal.SizeOf(typeof(LVITEM)) + bufferSize), 0x1000, 0x04);
            IntPtr pText = new IntPtr(pMem.ToInt64() + Marshal.SizeOf(typeof(LVITEM)));

            for (int i = 0; i < count; i++) {
                LVITEM item = new LVITEM();
                item.mask = 1;
                item.iItem = i;
                item.pszText = pText;
                item.cchTextMax = 250;

                IntPtr written;
                WriteProcessMemory(hProc, pMem, ref item, (uint)Marshal.SizeOf(typeof(LVITEM)), out written);
                SendMessage(hList, LVM_GETITEMTEXTW, (IntPtr)i, pMem);

                byte[] textBuffer = new byte[bufferSize];
                IntPtr read;
                ReadProcessMemory(hProc, pText, textBuffer, (uint)bufferSize, out read);
                string text = Encoding.Unicode.GetString(textBuffer).Split('\0')[0];
                list.Add(new RawItem { Index = i, Name = text });
            }

            VirtualFreeEx(hProc, pMem, 0, 0x8000);
            CloseHandle(hProc);
        });
        t.Start();
        t.Join();

        outHwnd = hList;
        return list;
    }

    public static void SetItemPosition(IntPtr hListView, int index, int x, int y) {
        Thread t = new Thread(() => {
            IntPtr hDefault = OpenDesktop("Default", 0, false, 0x01FF);
            if (hDefault != IntPtr.Zero) {
                SetThreadDesktop(hDefault);
            }
            int lParam = (y << 16) | (x & 0xFFFF);
            SendMessage(hListView, LVM_SETITEMPOSITION, (IntPtr)index, (IntPtr)lParam);
        });
        t.Start();
        t.Join();
    }

    public static void RefreshDesktop(IntPtr hListView) {
        Thread t = new Thread(() => {
            IntPtr hDefault = OpenDesktop("Default", 0, false, 0x01FF);
            if (hDefault != IntPtr.Zero) {
                SetThreadDesktop(hDefault);
            }
            RedrawWindow(hListView, IntPtr.Zero, IntPtr.Zero, RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW);
        });
        t.Start();
        t.Join();
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'DesktopCore').Type) {
    Add-Type -TypeDefinition $cSharpCode
}
Add-Type -AssemblyName System.Windows.Forms

# --- SYSTEM KNOWN TITLES & PATHS ---
$shellApp = New-Object -ComObject Shell.Application
$recycleBinTitle = ""
try { $recycleBinTitle = $shellApp.Namespace(10).Title } catch {}

$downloadsFolderTitle = ""
try { $downloadsFolderTitle = $shellApp.Namespace('shell:Downloads').Self.Name } catch {}

$desktopDirs = @()
$oneDriveDesktop = Join-Path $env:USERPROFILE "OneDrive\바탕 화면"
if (Test-Path -LiteralPath $oneDriveDesktop) { $desktopDirs += $oneDriveDesktop }
$stdDesktop = [Environment]::GetFolderPath('Desktop')
if ((Test-Path -LiteralPath $stdDesktop) -and ($desktopDirs -notcontains $stdDesktop)) { $desktopDirs += $stdDesktop }

$downloadDirs = @()
$oneDriveDownloads = Join-Path $env:USERPROFILE "OneDrive\다운로드"
if (Test-Path -LiteralPath $oneDriveDownloads) { $downloadDirs += $oneDriveDownloads }
try {
    $stdDownloads = $shellApp.Namespace('shell:Downloads').Self.Path
    if ((Test-Path -LiteralPath $stdDownloads) -and ($downloadDirs -notcontains $stdDownloads)) { $downloadDirs += $stdDownloads }
} catch {}

# --- FUNCTION: FIX JAMO (NFD -> NFC) ---
function Fix-JamoNormalization {
    param([string[]]$targetDirectories)
    
    foreach ($dir in $targetDirectories) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $entries = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
            $rawName = $entry.Name
            $nfcName = $rawName.Normalize([System.Text.NormalizationForm]::FormC)
            if ($rawName -ne $nfcName) {
                $parent = $entry.DirectoryName
                if (-not $parent) { $parent = $entry.Parent.FullName }
                $tempName = "jamo_tmp_" + [System.Guid]::NewGuid().ToString("N")
                $tempPath = Join-Path $parent $tempName
                $finalPath = Join-Path $parent $nfcName
                
                try {
                    Move-Item -LiteralPath $entry.FullName -Destination $tempPath -Force -ErrorAction Stop
                    Move-Item -LiteralPath $tempPath -Destination $finalPath -Force -ErrorAction Stop
                    Write-Host "  [Jamo Fixed] $rawName -> $nfcName"
                } catch {
                    Write-Host "  [Jamo Skip] Locked or syncing: $rawName"
                }
            }
        }
    }
}

# --- FUNCTION: ARRANGE DESKTOP (3 VERTICAL COLUMNS) ---
function Invoke-DesktopArrangement {
    $hListView = [IntPtr]::Zero
    $rawItems = [DesktopCore]::GetDesktopItems([ref]$hListView)
    if ($hListView -eq [IntPtr]::Zero -or $rawItems.Count -eq 0) {
        Write-Host "  [Arrange Warning] Desktop ListView not found."
        return
    }

    # Classify items
    $classified = @()
    foreach ($item in $rawItems) {
        $name = $item.Name.Trim()
        $priority = 4
        
        # Priority 1: Downloads (Folder / Shortcut)
        if (($downloadsFolderTitle -and ($name -like "$downloadsFolderTitle*")) -or ($name -match '^(Downloads|`uB2E4`uC6B4`uB85C`uB4DC)(\.lnk)?$')) {
            $priority = 1
        }
        # Priority 2: Recycle Bin
        elseif (($recycleBinTitle -and ($name -eq $recycleBinTitle)) -or ($name -eq "Recycle Bin") -or ($name -eq "`uD734`uC9C0`uD1B5")) {
            $priority = 2
        }
        else {
            # Check if directory
            $isDir = $false
            foreach ($d in $desktopDirs) {
                $checkPath = Join-Path $d $name
                if (Test-Path -LiteralPath $checkPath -PathType Container) {
                    $isDir = $true
                    break
                }
            }
            if ($isDir) {
                $priority = 3
            } else {
                $priority = 4
            }
        }

        $classified += [PSCustomObject]@{
            Index = $item.Index
            Name = $name
            Priority = $priority
        }
    }

    # Sort items: Priority (Downloads -> Recycle Bin -> Folders -> Files) then Name
    $sortedItems = $classified | Sort-Object -Property Priority, Name

    # Exact Grid Metrics matched to user's display
    $startX = 5
    $startY = 2
    $spacingX = 106
    $spacingY = 149
    $columns = 3

    $totalCount = $sortedItems.Count

    # Fill row-by-row into 3 columns with 0 empty gaps
    # Row 0: Downloads (Col 0), Recycle Bin (Col 1), 1st Folder (Col 2)
    # Row 1: 2nd Folder (Col 0), 3rd Folder (Col 1), 4th Folder (Col 2)
    # Following rows: Files filling Col 0, 1, 2 consecutively
    # Exact vertical alignment ensures Shift + Down arrow key navigation works perfectly.
    for ($i = 0; $i -lt $totalCount; $i++) {
        $item = $sortedItems[$i]
        $col = $i % $columns
        $row = [int][Math]::Floor($i / [double]$columns)
        
        $x = $startX + ($col * $spacingX)
        $y = $startY + ($row * $spacingY)

        [DesktopCore]::SetItemPosition($hListView, $item.Index, $x, $y)
    }

    [DesktopCore]::RefreshDesktop($hListView)
    Write-Host "  [Arranged] $($totalCount) items aligned in 3 columns without gaps (Row-by-row, Shift+Down optimized)."
}

# --- FUNCTION: ONE-SHOT PIPELINE ---
function Execute-OrganizePipeline {
    Write-Host "[1/2] Resolving Jamo Decomposition..."
    Fix-JamoNormalization -targetDirectories ($desktopDirs + $downloadDirs)

    Write-Host "[2/2] Arranging Desktop in 3 Vertical Columns..."
    Invoke-DesktopArrangement
}

# --- FUNCTION: CONFIGURE STARTUP & SPAWN BACKGROUND PROCESS ---
function Setup-StartupAndDaemon {
    if (-not $BatchPath) {
        $BatchPath = Join-Path (Get-Location).Path "DesktopOrganizer_Start.bat"
    }
    $scriptDir = Split-Path -Parent $BatchPath
    if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
    
    # Startup folder
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $vbsPath = Join-Path $startupFolder "DesktopOrganizer_Startup.vbs"
    
    $vbsContent = "Set WshShell = CreateObject(`"WScript.Shell`")`nWshShell.Run `"`"`"$BatchPath`"`" -daemon`", 0, False"
    [System.IO.File]::WriteAllText($vbsPath, $vbsContent, [System.Text.Encoding]::ASCII)
    Write-Host "[Startup] Registered silent boot trigger at shell:startup"

    # Spawn background daemon if not already running
    $pidFile = Join-Path $scriptDir "desktop_organizer.pid"
    $isRunning = $false
    if (Test-Path -LiteralPath $pidFile) {
        $savedPid = Get-Content -LiteralPath $pidFile -Raw
        if ($savedPid -and (Get-Process -Id ([int]$savedPid.Trim()) -ErrorAction SilentlyContinue)) {
            $isRunning = $true
        }
    }

    if (-not $isRunning) {
        $scriptText = "& { `$p = '$BatchPath'; & ([scriptblock]::Create((Get-Content -LiteralPath `$p -Encoding UTF8 -Raw))) -DaemonMode -BatchPath `$p }"
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($scriptText)
        $encoded = [Convert]::ToBase64String($bytes)
        $daemonCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded"
        
        $wsh = New-Object -ComObject WScript.Shell
        $wsh.Run($daemonCmd, 0, $false)
        Write-Host "[Daemon] Background monitor daemon spawned independently."
    } else {
        Write-Host "[Daemon] Background monitor daemon is already running."
    }
}

# --- FUNCTION: BACKGROUND WATCHER DAEMON ---
function Start-BackgroundWatcher {
    $logPath = Join-Path $env:TEMP "DesktopOrganizer_daemon.log"
    try {
        $scriptDir = Split-Path -Parent $BatchPath
        if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
        $pidFile = Join-Path $scriptDir "desktop_organizer.pid"
        [System.IO.File]::WriteAllText($pidFile, $PID.ToString(), [System.Text.Encoding]::ASCII)

        Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Daemon entering watcher. PID: $PID" -Force
        
        Execute-OrganizePipeline

        # Setup FileSystemWatcher
        $watchers = @()
        $timer = New-Object System.Timers.Timer
        $timer.Interval = 2000
        $timer.AutoReset = $false
        
        $timerAction = {
            try {
                Execute-OrganizePipeline
            } catch {
                $err = $_.Exception.ToString()
                Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Timer error: $err"
            }
        }
        Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action $timerAction | Out-Null

        foreach ($dir in $desktopDirs) {
            if (-not (Test-Path -LiteralPath $dir)) { continue }
            $fsw = New-Object System.IO.FileSystemWatcher
            $fsw.Path = $dir
            $fsw.IncludeSubdirectories = $false
            $fsw.EnableRaisingEvents = $true
            
            $changeAction = {
                $name = $Event.SourceEventArgs.Name
                if ($name -match '(\.tmp|~\$|\.crdownload|\.part)$') { return }
                $timer.Stop()
                $timer.Start()
            }

            Register-ObjectEvent -InputObject $fsw -EventName Created -Action $changeAction | Out-Null
            Register-ObjectEvent -InputObject $fsw -EventName Deleted -Action $changeAction | Out-Null
            Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action $changeAction | Out-Null
            $watchers += $fsw
        }

        Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Event loop starting for PID: $PID" -Force
        while ($true) {
            Start-Sleep -Seconds 10
        }
    } catch {
        Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Daemon fatal crash: $($_.Exception.ToString())" -Force
    }
}

# --- MAIN DISPATCHER ---
if ($DaemonMode) {
    Start-BackgroundWatcher
} else {
    Execute-OrganizePipeline
    Setup-StartupAndDaemon
}
