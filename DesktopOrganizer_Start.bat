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

# --- WIN32 / C# VERTICAL MANAGER & NATIVE WATCHER & KEYBOARD HOOK ---
$cSharpCode = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class DesktopVerticalManager {
    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr OpenDesktop(string lpszDesktop, uint dwFlags, bool fInherit, uint dwDesiredAccess);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetThreadDesktop(IntPtr hDesktop);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, string lpszClass, string lpszWindow);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr hWnd, IntPtr lprcUpdate, IntPtr hrgnUpdate, uint flags);
    [DllImport("user32.dll", SetLastError = true)] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", SetLastError = true)] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)] private static extern IntPtr GetModuleHandle(string lpModuleName);
    [DllImport("user32.dll")] private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);
    [DllImport("user32.dll")] private static extern bool TranslateMessage([In] ref MSG lpMsg);
    [DllImport("user32.dll")] private static extern IntPtr DispatchMessage([In] ref MSG lpMsg);

    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr VirtualAllocEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint flAllocationType, uint flProtect);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool VirtualFreeEx(IntPtr hProcess, IntPtr lpAddress, uint dwSize, uint dwFreeType);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool WriteProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, ref LVITEM lpBuffer, uint nSize, out IntPtr lpNumberOfBytesWritten);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool ReadProcessMemory(IntPtr hProcess, IntPtr lpBaseAddress, byte[] lpBuffer, uint nSize, out IntPtr lpNumberOfBytesRead);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr hObject);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    public const uint LVM_FIRST = 0x1000;
    public const uint LVM_GETITEMCOUNT = LVM_FIRST + 4;
    public const uint LVM_GETITEMTEXTW = LVM_FIRST + 115;
    public const uint LVM_SETITEMPOSITION = LVM_FIRST + 15;
    public const uint LVM_GETITEMPOSITION = LVM_FIRST + 16;
    public const uint LVM_SETITEMSTATE = LVM_FIRST + 43;
    public const uint LVM_GETNEXTITEM = LVM_FIRST + 12;

    public const int LVIS_FOCUSED = 0x0001;
    public const int LVIS_SELECTED = 0x0002;
    public const int LVNI_FOCUSED = 0x0001;

    public const int GWL_STYLE = -16;
    public const int LVS_AUTOARRANGE = 0x0100;
    public const uint RDW_INVALIDATE = 0x0001;
    public const uint RDW_ERASE = 0x0004;
    public const uint RDW_UPDATENOW = 0x0100;

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int VK_SHIFT = 0x10;
    private const int VK_UP = 0x26;
    private const int VK_DOWN = 0x28;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct LVITEM {
        public uint mask; public int iItem; public int iSubItem; public uint state; public uint stateMask; public IntPtr pszText; public int cchTextMax; public int iImage; public IntPtr lParam; public int iIndent; public int iGroupId; public uint cColumns; public IntPtr puColumns; public IntPtr piColFmt; public int iGroup;
    }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)] public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public POINT pt; }

    public class ItemEntry {
        public int Index;
        public string Name;
    }

    private static IntPtr _hookId = IntPtr.Zero;
    private static LowLevelKeyboardProc _proc = HookCallback;
    private static Thread _hookThread = null;

    // Native Watcher variables (Thread-safe flag)
    public static volatile bool NeedsArrange = false;
    private static List<FileSystemWatcher> _watchers = new List<FileSystemWatcher>();
    private static System.Threading.Timer _debounceTimer = null;

    public static IntPtr FindListView() {
        IntPtr hProgman = FindWindow("Progman", null);
        IntPtr hDefView = FindWindowEx(hProgman, IntPtr.Zero, "SHELLDLL_DefView", null);
        if (hDefView == IntPtr.Zero) {
            EnumWindows((hWnd, lParam) => {
                IntPtr c = FindWindowEx(hWnd, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (c != IntPtr.Zero) { hDefView = c; return false; }
                return true;
            }, IntPtr.Zero);
        }
        return (hDefView != IntPtr.Zero) ? FindWindowEx(hDefView, IntPtr.Zero, "SysListView32", null) : IntPtr.Zero;
    }

    public static bool IsDesktopForeground() {
        IntPtr hFore = GetForegroundWindow();
        if (hFore == IntPtr.Zero) return false;
        StringBuilder sb = new StringBuilder(256);
        GetClassName(hFore, sb, 256);
        string cls = sb.ToString();
        if (cls == "Progman" || cls == "WorkerW" || cls == "SHELLDLL_DefView" || cls == "SysListView32") return true;
        IntPtr hDefView = FindWindowEx(hFore, IntPtr.Zero, "SHELLDLL_DefView", null);
        return hDefView != IntPtr.Zero;
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN) {
            int vkCode = Marshal.ReadInt32(lParam);
            if ((vkCode == VK_DOWN || vkCode == VK_UP) && (GetAsyncKeyState(VK_SHIFT) < 0)) {
                if (IsDesktopForeground()) {
                    if (HandleVerticalSelection(vkCode == VK_DOWN)) {
                        return (IntPtr)1; // Suppress default horizontal row selection!
                    }
                }
            }
        }
        return CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private static bool HandleVerticalSelection(bool isDown) {
        IntPtr hList = FindListView();
        if (hList == IntPtr.Zero) return false;

        int count = (int)SendMessage(hList, LVM_GETITEMCOUNT, IntPtr.Zero, IntPtr.Zero);
        int focused = (int)SendMessage(hList, LVM_GETNEXTITEM, (IntPtr)(-1), (IntPtr)LVNI_FOCUSED);
        if (focused < 0) return false;

        uint pid;
        GetWindowThreadProcessId(hList, out pid);
        IntPtr hProc = OpenProcess(0x0038, false, pid);
        if (hProc == IntPtr.Zero) return false;

        IntPtr pPoint = VirtualAllocEx(hProc, IntPtr.Zero, (uint)Marshal.SizeOf(typeof(POINT)), 0x1000, 0x04);
        byte[] ptb = new byte[Marshal.SizeOf(typeof(POINT))];
        IntPtr read;

        SendMessage(hList, LVM_GETITEMPOSITION, (IntPtr)focused, pPoint);
        ReadProcessMemory(hProc, pPoint, ptb, (uint)ptb.Length, out read);
        int curX = BitConverter.ToInt32(ptb, 0);
        int curY = BitConverter.ToInt32(ptb, 4);

        int bestIndex = -1;
        int bestDist = int.MaxValue;

        for (int i = 0; i < count; i++) {
            if (i == focused) continue;
            SendMessage(hList, LVM_GETITEMPOSITION, (IntPtr)i, pPoint);
            ReadProcessMemory(hProc, pPoint, ptb, (uint)ptb.Length, out read);
            int x = BitConverter.ToInt32(ptb, 0);
            int y = BitConverter.ToInt32(ptb, 4);

            if (Math.Abs(x - curX) <= 35) {
                if (isDown && y > curY) {
                    int dist = y - curY;
                    if (dist < bestDist) { bestDist = dist; bestIndex = i; }
                } else if (!isDown && y < curY) {
                    int dist = curY - y;
                    if (dist < bestDist) { bestDist = dist; bestIndex = i; }
                }
            }
        }

        VirtualFreeEx(hProc, pPoint, 0, 0x8000);
        CloseHandle(hProc);

        if (bestIndex != -1) {
            LVITEM lv = new LVITEM();
            lv.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
            lv.state = LVIS_SELECTED | LVIS_FOCUSED;
            IntPtr pLv = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(LVITEM)));
            Marshal.StructureToPtr(lv, pLv, false);
            SendMessage(hList, LVM_SETITEMSTATE, (IntPtr)bestIndex, pLv);
            Marshal.FreeHGlobal(pLv);
            return true;
        }

        return false;
    }

    public static void StartHookThread() {
        if (_hookThread != null && _hookThread.IsAlive) return;
        _hookThread = new Thread(() => {
            using (Process curProcess = Process.GetCurrentProcess())
            using (ProcessModule curModule = curProcess.MainModule) {
                _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(curModule.ModuleName), 0);
            }
            MSG msg;
            while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }
            if (_hookId != IntPtr.Zero) {
                UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }
        });
        _hookThread.IsBackground = true;
        _hookThread.Start();
    }

    public static void StartNativeWatcher(string[] paths) {
        _debounceTimer = new System.Threading.Timer((state) => {
            NeedsArrange = true;
        }, null, Timeout.Infinite, Timeout.Infinite);

        foreach (string path in paths) {
            if (!Directory.Exists(path)) continue;
            try {
                FileSystemWatcher fsw = new FileSystemWatcher(path);
                fsw.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.Size | NotifyFilters.LastWrite;
                fsw.IncludeSubdirectories = false;
                
                FileSystemEventHandler changeHandler = (s, e) => {
                    if (e.Name.EndsWith(".tmp") || e.Name.StartsWith("~$")) return;
                    _debounceTimer.Change(800, Timeout.Infinite); // 800ms debounce
                };

                fsw.Created += changeHandler;
                fsw.Deleted += changeHandler;
                fsw.Renamed += (s, e) => {
                    if (e.Name.EndsWith(".tmp") || e.Name.StartsWith("~$")) return;
                    _debounceTimer.Change(800, Timeout.Infinite);
                };

                fsw.EnableRaisingEvents = true;
                _watchers.Add(fsw);
            } catch {}
        }
    }

    public static List<ItemEntry> GetAllItems(out IntPtr outHwnd) {
        List<ItemEntry> list = new List<ItemEntry>();
        IntPtr hList = IntPtr.Zero;

        Thread t = new Thread(() => {
            IntPtr hDefault = OpenDesktop("Default", 0, false, 0x01FF);
            if (hDefault != IntPtr.Zero) SetThreadDesktop(hDefault);
            hList = FindListView();
            if (hList == IntPtr.Zero) return;

            int style = GetWindowLong(hList, GWL_STYLE);
            if ((style & LVS_AUTOARRANGE) != 0) {
                SetWindowLong(hList, GWL_STYLE, style & ~LVS_AUTOARRANGE);
            }

            int count = (int)SendMessage(hList, LVM_GETITEMCOUNT, IntPtr.Zero, IntPtr.Zero);
            uint pid;
            GetWindowThreadProcessId(hList, out pid);
            IntPtr hProc = OpenProcess(0x0038, false, pid);
            if (hProc == IntPtr.Zero) return;

            int bufferSize = 512;
            IntPtr pMem = VirtualAllocEx(hProc, IntPtr.Zero, (uint)(Marshal.SizeOf(typeof(LVITEM)) + bufferSize), 0x1000, 0x04);
            IntPtr pText = new IntPtr(pMem.ToInt64() + Marshal.SizeOf(typeof(LVITEM)));

            for (int i = 0; i < count; i++) {
                LVITEM item = new LVITEM(); item.mask = 1; item.iItem = i; item.pszText = pText; item.cchTextMax = 250;
                IntPtr written; WriteProcessMemory(hProc, pMem, ref item, (uint)Marshal.SizeOf(typeof(LVITEM)), out written);
                SendMessage(hList, LVM_GETITEMTEXTW, (IntPtr)i, pMem);
                byte[] textBuffer = new byte[bufferSize]; IntPtr read; ReadProcessMemory(hProc, pText, textBuffer, (uint)bufferSize, out read);
                string text = Encoding.Unicode.GetString(textBuffer).Split('\0')[0];
                list.Add(new ItemEntry { Index = i, Name = text });
            }
            VirtualFreeEx(hProc, pMem, 0, 0x8000); CloseHandle(hProc);
        });
        t.Start(); t.Join();

        outHwnd = hList;
        return list;
    }

    public static void SetItemPosition(IntPtr hListView, int index, int x, int y) {
        Thread t = new Thread(() => {
            IntPtr hDefault = OpenDesktop("Default", 0, false, 0x01FF);
            if (hDefault != IntPtr.Zero) SetThreadDesktop(hDefault);
            int lParam = (y << 16) | (x & 0xFFFF);
            SendMessage(hListView, LVM_SETITEMPOSITION, (IntPtr)index, (IntPtr)lParam);
        });
        t.Start(); t.Join();
    }

    public static void RefreshDesktop(IntPtr hListView) {
        Thread t = new Thread(() => {
            IntPtr hDefault = OpenDesktop("Default", 0, false, 0x01FF);
            if (hDefault != IntPtr.Zero) SetThreadDesktop(hDefault);
            RedrawWindow(hListView, IntPtr.Zero, IntPtr.Zero, RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW);
        });
        t.Start(); t.Join();
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'DesktopVerticalManager').Type) {
    Add-Type -TypeDefinition $cSharpCode
}
Add-Type -AssemblyName System.Windows.Forms

# --- SYSTEM DIRECTORIES (Pure Unicode & Dynamic Detection) ---
$shellApp = New-Object -ComObject Shell.Application
$recycleBinTitle = ""
try { $recycleBinTitle = $shellApp.Namespace(10).Title } catch {}

$downloadsFolderTitle = ""
try { $downloadsFolderTitle = $shellApp.Namespace('shell:Downloads').Self.Name } catch {}

# Detect all Desktop directories (Hyunfield, OneDrive, Standard, Public)
$desktopDirs = @()
try {
    $regVal = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue).Desktop
    if ($regVal) {
        $expanded = [Environment]::ExpandEnvironmentVariables($regVal)
        if (Test-Path -LiteralPath $expanded) { $desktopDirs += $expanded }
    }
} catch {}

$userHyunfield = "C:\Users\guswn\OneDrive\Hyunfield"
if ((Test-Path -LiteralPath $userHyunfield) -and ($desktopDirs -notcontains $userHyunfield)) {
    $desktopDirs += $userHyunfield
}

$envDesktop = [Environment]::GetFolderPath('Desktop')
if ((Test-Path -LiteralPath $envDesktop) -and ($desktopDirs -notcontains $envDesktop)) {
    $desktopDirs += $envDesktop
}

$stdDesktop = Join-Path $env:USERPROFILE "Desktop"
if ((Test-Path -LiteralPath $stdDesktop) -and ($desktopDirs -notcontains $stdDesktop)) {
    $desktopDirs += $stdDesktop
}

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

# --- FUNCTION: ARRANGE DESKTOP (EXACT 3-COLUMN SEAMLESS MATCH) ---
function Invoke-DesktopArrangement {
    $hListView = [IntPtr]::Zero
    $rawItems = [DesktopVerticalManager]::GetAllItems([ref]$hListView)
    if ($hListView -eq [IntPtr]::Zero -or $rawItems.Count -eq 0) {
        Write-Host "  [Arrange Warning] Desktop ListView not found."
        return
    }

    $col1List = @()
    $col2List = @()
    $col3List = @()

    $folders = @()
    $files = @()

    $strDownloads = (-join [char[]]@(0xB2E4, 0xC6B4, 0xB85C, 0xB4DC))
    $strRecycle = (-join [char[]]@(0xD734, 0xC9C0, 0xD1B5))
    $strMod = (-join [char[]]@(0xC218, 0xC815))
    $strChef = (-join [char[]]@(0xD658, 0xC0DD, 0xC170, 0xD504))
    $strHwa = [string][char]0xD654

    foreach ($item in $rawItems) {
        $name = $item.Name.Trim()
        
        $isDir = $false
        foreach ($d in $desktopDirs) {
            $checkPath = Join-Path $d $name
            if (Test-Path -LiteralPath $checkPath -PathType Container) {
                $isDir = $true
                break
            }
        }

        $obj = [PSCustomObject]@{
            Index = $item.Index
            Name = $name
            IsDir = $isDir
        }

        $isDownloads = (($downloadsFolderTitle -and ($name -like "$downloadsFolderTitle*")) -or ($name -like "*$strDownloads*") -or ($name -like "*Downloads*"))
        $isRecycle = (($recycleBinTitle -and ($name -eq $recycleBinTitle)) -or ($name -eq "Recycle Bin") -or ($name -eq $strRecycle))

        if ($isDownloads) {
            $col1List += $obj
        }
        elseif ($isRecycle) {
            $col2List += $obj
        }
        elseif ($isDir) {
            $folders += $obj
        }
        else {
            $files += $obj
        }
    }

    $folders = $folders | Sort-Object Name
    foreach ($f in $folders) {
        if ($f.Name -like "*officedocs*") {
            $col1List += $f
        }
        elseif ($f.Name -like "*workspace*") {
            $col2List += $f
        }
        elseif ($f.Name -like "*games*" -or $f.Name -like "*$strChef*") {
            $col3List += $f
        }
        else {
            if ($col1List.Count -le $col2List.Count -and $col1List.Count -le $col3List.Count) { $col1List += $f }
            elseif ($col2List.Count -le $col3List.Count) { $col2List += $f }
            else { $col3List += $f }
        }
    }

    $files = $files | Sort-Object Name
    foreach ($file in $files) {
        $n = $file.Name
        if ($n -like "*$strMod*2*" -or ($n -like "*$strMod*1*" -and $n -like "*020*")) {
            $col1List += $file
        }
        elseif ($n -like "*KakaoTalk*" -or $n -like "*018$strHwa.*" -or $n -like "*020.*" -or $n -like "*020$strHwa.*") {
            $col2List += $file
        }
        elseif ($n -like "*019*" -or $n -like "*19$strHwa*") {
            $col3List += $file
        }
        else {
            if ($col1List.Count -le $col2List.Count -and $col1List.Count -le $col3List.Count) { $col1List += $file }
            elseif ($col2List.Count -le $col3List.Count) { $col2List += $file }
            else { $col3List += $file }
        }
    }

    # Strict height balancing: guarantee equal column count (e.g. 4 / 4 / 4)
    $targetPerCol = [int][Math]::Ceiling($rawItems.Count / 3.0)
    while ($col3List.Count -gt $targetPerCol -and ($col2List.Count -lt $targetPerCol -or $col1List.Count -lt $targetPerCol)) {
        if ($col2List.Count -lt $targetPerCol) {
            $col2List += $col3List[-1]
            $col3List = @($col3List[0..($col3List.Count - 2)])
        } elseif ($col1List.Count -lt $targetPerCol) {
            $col1List += $col3List[-1]
            $col3List = @($col3List[0..($col3List.Count - 2)])
        } else { break }
    }
    while ($col1List.Count -gt $targetPerCol -and ($col2List.Count -lt $targetPerCol -or $col3List.Count -lt $targetPerCol)) {
        if ($col2List.Count -lt $targetPerCol) {
            $col2List += $col1List[-1]
            $col1List = @($col1List[0..($col1List.Count - 2)])
        } elseif ($col3List.Count -lt $targetPerCol) {
            $col3List += $col1List[-1]
            $col1List = @($col1List[0..($col1List.Count - 2)])
        } else { break }
    }

    $colX = @(5, 111, 217)
    $startY = 2
    $spacingY = 149

    for ($r = 0; $r -lt $col1List.Count; $r++) {
        $y = $startY + ($r * $spacingY)
        [DesktopVerticalManager]::SetItemPosition($hListView, $col1List[$r].Index, $colX[0], $y)
    }

    for ($r = 0; $r -lt $col2List.Count; $r++) {
        $y = $startY + ($r * $spacingY)
        [DesktopVerticalManager]::SetItemPosition($hListView, $col2List[$r].Index, $colX[1], $y)
    }

    for ($r = 0; $r -lt $col3List.Count; $r++) {
        $y = $startY + ($r * $spacingY)
        [DesktopVerticalManager]::SetItemPosition($hListView, $col3List[$r].Index, $colX[2], $y)
    }

    [DesktopVerticalManager]::RefreshDesktop($hListView)
    Write-Host "  [Arranged] Successfully matched 3-column vertical grid without gaps! (Col1: $($col1List.Count), Col2: $($col2List.Count), Col3: $($col3List.Count))"
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
        
        $spawned = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine = $daemonCmd}
        if ($spawned.ProcessId) {
            [System.IO.File]::WriteAllText($pidFile, $spawned.ProcessId.ToString(), [System.Text.Encoding]::ASCII)
            Write-Host "[Daemon] Background monitor & vertical selection hook spawned (PID: $($spawned.ProcessId))."
        } else {
            # Fallback to WScript.Shell
            $wsh = New-Object -ComObject WScript.Shell
            $wsh.Run($daemonCmd, 0, $false)
            Write-Host "[Daemon] Background monitor & vertical selection hook spawned."
        }
    } else {
        Write-Host "[Daemon] Background monitor daemon is already running."
    }
}

# --- FUNCTION: BACKGROUND WATCHER & VERTICAL SELECTION HOOK DAEMON ---
function Start-BackgroundWatcher {
    $scriptDir = Split-Path -Parent $BatchPath
    if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
    $pidFile = Join-Path $scriptDir "desktop_organizer.pid"
    [System.IO.File]::WriteAllText($pidFile, $PID.ToString(), [System.Text.Encoding]::ASCII)

    $logPath = Join-Path $env:TEMP "DesktopOrganizer_daemon.log"
    Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Daemon started with native watcher & keyboard hook. PID: $PID" -Force
    
    try {
        Execute-OrganizePipeline
    } catch {
        Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Initial pipeline error: $($_.Exception.ToString())"
    }

    # Start Native C# FileSystemWatcher on all Desktop directories
    [DesktopVerticalManager]::StartNativeWatcher($desktopDirs)

    # Start Keyboard Hook in background thread
    [DesktopVerticalManager]::StartHookThread()

    # Main thread polling loop (Thread-safe)
    while ($true) {
        if ([DesktopVerticalManager]::NeedsArrange) {
            [DesktopVerticalManager]::NeedsArrange = $false
            Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] File change detected. Triggering auto-arrangement..." -Force
            try {
                Execute-OrganizePipeline
                Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Auto-arrangement successfully executed." -Force
            } catch {
                Add-Content -LiteralPath $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Auto-arrangement error: $($_.Exception.ToString())" -Force
            }
        }
        Start-Sleep -Milliseconds 300
    }
}

# --- MAIN DISPATCHER ---
if ($DaemonMode) {
    Start-BackgroundWatcher
} else {
    Execute-OrganizePipeline
    Setup-StartupAndDaemon
}
