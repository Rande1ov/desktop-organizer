<# : batch script
@echo off
setlocal
cd /d "%~dp0"

cls
echo ========================================================
echo        Desktop 3-Column Organizer and Jamo Fixer
echo ========================================================
echo.
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -Command "$p='%~f0'; & ([scriptblock]::Create((Get-Content -LiteralPath $p -Encoding UTF8 -Raw))) -BatchPath $p"
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

$cSharpSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

public class DesktopOrganizerDaemon {
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
    private const int WM_KEYUP = 0x0101;
    private const int VK_LBUTTON = 0x01;
    private const int VK_RBUTTON = 0x02;
    private const int VK_SHIFT = 0x10;
    private const int VK_LEFT = 0x25;
    private const int VK_UP = 0x26;
    private const int VK_RIGHT = 0x27;
    private const int VK_DOWN = 0x28;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct LVITEM {
        public uint mask; public int iItem; public int iSubItem; public uint state; public uint stateMask; public IntPtr pszText; public int cchTextMax; public int iImage; public IntPtr lParam; public int iIndent; public int iGroupId; public uint cColumns; public IntPtr puColumns; public IntPtr piColFmt; public int iGroup;
    }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x; public int y; }

    public class DesktopItem {
        public int Index;
        public string Name;
        public int X;
        public int Y;
        public bool IsDir;
    }

    public class PosItem {
        public int Index;
        public int X;
        public int Y;
    }

    private static Mutex _mutex = null;
    private static IntPtr _hookId = IntPtr.Zero;
    private static LowLevelKeyboardProc _proc = HookCallback;
    private static int _anchorIndex = -1;

    private static List<string> _desktopDirs = new List<string>();
    private static List<string> _downloadDirs = new List<string>();
    private static List<FileSystemWatcher> _watchers = new List<FileSystemWatcher>();
    private static System.Threading.Timer _stage1Timer = null;
    private static System.Threading.Timer _stage2Timer = null;
    private static System.Windows.Forms.Timer _watchdogTimer = null;
    private static volatile bool _pendingArrange = false;
    private static readonly object _arrangeLock = new object();
    private static string _logPath = Path.Combine(Path.GetTempPath(), "DesktopOrganizer_daemon.log");

    private static void Log(string msg) {
        try {
            string line = string.Format("[{0}] {1}{2}", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"), msg, Environment.NewLine);
            File.AppendAllText(_logPath, line, Encoding.UTF8);
        } catch {}
    }

    public static string RunOnce() {
        DiscoverDirectories();
        int moved = 0;
        int total = 0;
        lock (_arrangeLock) {
            FixJamoNormalization();
            ArrangeDesktop(false, out total, out moved);
        }
        return string.Format("Processed {0} items (repositioned {1}).", total, moved);
    }

    public static void RunDaemon() {
        bool createdNew;
        _mutex = new Mutex(true, "Local\\DesktopOrganizerDaemon_SingleInstance", out createdNew);
        if (!createdNew) {
            return;
        }

        try {
            IntPtr hDefault = OpenDesktop("Default", 0, false, 0x01FF);
            if (hDefault != IntPtr.Zero) SetThreadDesktop(hDefault);
            DiscoverDirectories();
            Log("Interactive STA Daemon started. PID: " + Process.GetCurrentProcess().Id);

            int total, moved;
            lock (_arrangeLock) {
                FixJamoNormalization();
                ArrangeDesktop(false, out total, out moved);
            }

            _stage1Timer = new System.Threading.Timer((s) => { _pendingArrange = true; }, null, Timeout.Infinite, Timeout.Infinite);
            _stage2Timer = new System.Threading.Timer((s) => { _pendingArrange = true; }, null, Timeout.Infinite, Timeout.Infinite);

            StartFileWatchers();
            InstallKeyboardHook();

            _watchdogTimer = new System.Windows.Forms.Timer();
            _watchdogTimer.Interval = 500;
            int tickCount = 0;
            _watchdogTimer.Tick += (s, e) => {
                tickCount++;
                if (_pendingArrange) {
                    _pendingArrange = false;
                    RunOrganizePipeline(false);
                    tickCount = 0;
                } else if (tickCount >= 4) {
                    tickCount = 0;
                    if (!IsMouseButtonDown()) {
                        RunOrganizePipeline(true);
                    }
                }
            };
            _watchdogTimer.Start();

            Application.Run();
        } catch (Exception ex) {
            Log("Fatal daemon error: " + ex.ToString());
        } finally {
            if (_hookId != IntPtr.Zero) {
                UnhookWindowsHookEx(_hookId);
                _hookId = IntPtr.Zero;
            }
            if (_mutex != null) {
                try { _mutex.ReleaseMutex(); } catch {}
            }
        }
    }

    private static bool IsMouseButtonDown() {
        return (GetAsyncKeyState(VK_LBUTTON) < 0) || (GetAsyncKeyState(VK_RBUTTON) < 0);
    }

    private static void DiscoverDirectories() {
        _desktopDirs.Clear();
        _downloadDirs.Clear();

        try {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders")) {
                if (key != null) {
                    object val = key.GetValue("Desktop");
                    if (val != null) {
                        string expanded = Environment.ExpandEnvironmentVariables(val.ToString());
                        if (Directory.Exists(expanded) && !_desktopDirs.Contains(expanded)) _desktopDirs.Add(expanded);
                    }
                }
            }
        } catch {}

        string hyunfield = @"C:\Users\guswn\OneDrive\Hyunfield";
        if (Directory.Exists(hyunfield) && !_desktopDirs.Contains(hyunfield)) _desktopDirs.Add(hyunfield);

        string envDesktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
        if (!string.IsNullOrEmpty(envDesktop) && Directory.Exists(envDesktop) && !_desktopDirs.Contains(envDesktop)) _desktopDirs.Add(envDesktop);

        string userProf = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        string stdDesktop = Path.Combine(userProf, "Desktop");
        if (Directory.Exists(stdDesktop) && !_desktopDirs.Contains(stdDesktop)) _desktopDirs.Add(stdDesktop);

        string odDown = Path.Combine(userProf, "OneDrive\\\uB2E4\uC6B4\uB85C\uB4DC");
        if (Directory.Exists(odDown) && !_downloadDirs.Contains(odDown)) _downloadDirs.Add(odDown);

        string stdDown = Path.Combine(userProf, "Downloads");
        if (Directory.Exists(stdDown) && !_downloadDirs.Contains(stdDown)) _downloadDirs.Add(stdDown);
    }

    private static void StartFileWatchers() {
        foreach (string path in _desktopDirs) {
            try {
                FileSystemWatcher fsw = new FileSystemWatcher(path);
                fsw.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite;
                fsw.IncludeSubdirectories = false;

                FileSystemEventHandler onFsEvent = (s, e) => {
                    if (e.Name != null && (e.Name.EndsWith(".tmp") || e.Name.StartsWith("~$") || e.Name.StartsWith("jamo_tmp_"))) return;
                    _stage1Timer.Change(500, Timeout.Infinite);
                    _stage2Timer.Change(1500, Timeout.Infinite);
                };

                fsw.Created += onFsEvent;
                fsw.Deleted += onFsEvent;
                fsw.Renamed += (s, e) => {
                    if (e.Name != null && (e.Name.EndsWith(".tmp") || e.Name.StartsWith("~$") || e.Name.StartsWith("jamo_tmp_"))) return;
                    _stage1Timer.Change(500, Timeout.Infinite);
                    _stage2Timer.Change(1500, Timeout.Infinite);
                };
                fsw.EnableRaisingEvents = true;
                _watchers.Add(fsw);
            } catch (Exception ex) {
                Log("Watcher error on " + path + ": " + ex.Message);
            }
        }
        Log("Watching Desktop dirs: " + string.Join(" | ", _desktopDirs.ToArray()));
    }

    private static void FixJamoNormalization() {
        List<string> allDirs = new List<string>();
        allDirs.AddRange(_desktopDirs);
        allDirs.AddRange(_downloadDirs);

        foreach (string dir in allDirs) {
            if (!Directory.Exists(dir)) continue;
            try {
                foreach (string entryPath in Directory.GetFileSystemEntries(dir)) {
                    string rawName = Path.GetFileName(entryPath);
                    string nfcName = rawName.Normalize(NormalizationForm.FormC);
                    if (rawName != nfcName) {
                        string parent = Path.GetDirectoryName(entryPath);
                        string tempPath = Path.Combine(parent, "jamo_tmp_" + Guid.NewGuid().ToString("N"));
                        string finalPath = Path.Combine(parent, nfcName);
                        try {
                            if (Directory.Exists(entryPath)) {
                                Directory.Move(entryPath, tempPath);
                                Directory.Move(tempPath, finalPath);
                            } else if (File.Exists(entryPath)) {
                                File.Move(entryPath, tempPath);
                                File.Move(tempPath, finalPath);
                            }
                            Log("Jamo fixed: " + rawName + " -> " + nfcName);
                        } catch {}
                    }
                }
            } catch {}
        }
    }

    private static void RunOrganizePipeline(bool onlyIfNeeded) {
        lock (_arrangeLock) {
            try {
                FixJamoNormalization();
                int total, moved;
                ArrangeDesktop(onlyIfNeeded, out total, out moved);
            } catch (Exception ex) {
                Log("Pipeline error: " + ex.Message);
            }
        }
    }

    private static void ArrangeDesktop(bool onlyIfNeeded, out int totalCount, out int movedCount) {
        int tCount = 0;
        int mCount = 0;
        Thread worker = new Thread(() => {
            IntPtr hDefault = OpenDesktop("Default", 0, false, 0x01FF);
            if (hDefault != IntPtr.Zero) SetThreadDesktop(hDefault);
            IntPtr hList = FindListView();
            if (hList == IntPtr.Zero) return;

            int style = GetWindowLong(hList, GWL_STYLE);
            if ((style & LVS_AUTOARRANGE) != 0) {
                SetWindowLong(hList, GWL_STYLE, style & ~LVS_AUTOARRANGE);
            }

            int count = (int)SendMessage(hList, LVM_GETITEMCOUNT, IntPtr.Zero, IntPtr.Zero);
            if (count <= 0) return;
            tCount = count;

            uint pid;
            GetWindowThreadProcessId(hList, out pid);
            IntPtr hProc = OpenProcess(0x0038, false, pid);
            if (hProc == IntPtr.Zero) return;

            List<DesktopItem> rawItems = new List<DesktopItem>();
            int bufferSize = 512;
            IntPtr pMem = VirtualAllocEx(hProc, IntPtr.Zero, (uint)(Marshal.SizeOf(typeof(LVITEM)) + bufferSize), 0x1000, 0x04);
            IntPtr pPoint = VirtualAllocEx(hProc, IntPtr.Zero, (uint)Marshal.SizeOf(typeof(POINT)), 0x1000, 0x04);
            IntPtr pText = new IntPtr(pMem.ToInt64() + Marshal.SizeOf(typeof(LVITEM)));
            byte[] ptb = new byte[Marshal.SizeOf(typeof(POINT))];
            byte[] textBuffer = new byte[bufferSize];

            for (int i = 0; i < count; i++) {
                LVITEM item = new LVITEM();
                item.mask = 1;
                item.iItem = i;
                item.pszText = pText;
                item.cchTextMax = 250;
                IntPtr written;
                WriteProcessMemory(hProc, pMem, ref item, (uint)Marshal.SizeOf(typeof(LVITEM)), out written);
                SendMessage(hList, LVM_GETITEMTEXTW, (IntPtr)i, pMem);
                IntPtr read;
                ReadProcessMemory(hProc, pText, textBuffer, (uint)bufferSize, out read);
                string text = Encoding.Unicode.GetString(textBuffer).Split('\0')[0].Trim();

                SendMessage(hList, LVM_GETITEMPOSITION, (IntPtr)i, pPoint);
                ReadProcessMemory(hProc, pPoint, ptb, (uint)ptb.Length, out read);
                int x = BitConverter.ToInt32(ptb, 0);
                int y = BitConverter.ToInt32(ptb, 4);

                bool isDir = false;
                foreach (string d in _desktopDirs) {
                    if (Directory.Exists(Path.Combine(d, text))) {
                        isDir = true;
                        break;
                    }
                }

                rawItems.Add(new DesktopItem { Index = i, Name = text, X = x, Y = y, IsDir = isDir });
            }

            VirtualFreeEx(hProc, pMem, 0, 0x8000);
            VirtualFreeEx(hProc, pPoint, 0, 0x8000);
            CloseHandle(hProc);

            string strDownloads = "\uB2E4\uC6B4\uB85C\uB4DC";
            string strRecycle = "\uD734\uC9C0\uD1B5";
            string strMod = "\uC218\uC815";
            string strChef = "\uD658\uC0DD\uC170\uD504";
            string strHwa = "\uD654";

            List<DesktopItem> col1List = new List<DesktopItem>();
            List<DesktopItem> col2List = new List<DesktopItem>();
            List<DesktopItem> col3List = new List<DesktopItem>();
            List<DesktopItem> folders = new List<DesktopItem>();
            List<DesktopItem> files = new List<DesktopItem>();

            foreach (DesktopItem item in rawItems) {
                string n = item.Name;
                bool isDownloads = (n.IndexOf(strDownloads, StringComparison.OrdinalIgnoreCase) >= 0) || (n.IndexOf("Downloads", StringComparison.OrdinalIgnoreCase) >= 0);
                bool isRecycle = (n == strRecycle) || (n.Equals("Recycle Bin", StringComparison.OrdinalIgnoreCase));

                if (isDownloads) col1List.Add(item);
                else if (isRecycle) col2List.Add(item);
                else if (item.IsDir) folders.Add(item);
                else files.Add(item);
            }

            folders.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase));
            foreach (DesktopItem f in folders) {
                if (f.Name.IndexOf("officedocs", StringComparison.OrdinalIgnoreCase) >= 0) col1List.Add(f);
                else if (f.Name.IndexOf("workspace", StringComparison.OrdinalIgnoreCase) >= 0) col2List.Add(f);
                else if (f.Name.IndexOf("games", StringComparison.OrdinalIgnoreCase) >= 0 || f.Name.IndexOf(strChef, StringComparison.OrdinalIgnoreCase) >= 0) col3List.Add(f);
                else {
                    if (col1List.Count <= col2List.Count && col1List.Count <= col3List.Count) col1List.Add(f);
                    else if (col2List.Count <= col3List.Count) col2List.Add(f);
                    else col3List.Add(f);
                }
            }

            files.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase));
            foreach (DesktopItem file in files) {
                string n = file.Name;
                if ((n.Contains(strMod) && n.Contains("2")) || (n.Contains(strMod) && n.Contains("1") && n.Contains("020"))) {
                    col1List.Add(file);
                } else if (n.IndexOf("KakaoTalk", StringComparison.OrdinalIgnoreCase) >= 0 || n.Contains("018" + strHwa + ".") || n.Contains("020.") || n.Contains("020" + strHwa + ".")) {
                    col2List.Add(file);
                } else if (n.Contains("019") || n.Contains("19" + strHwa)) {
                    col3List.Add(file);
                } else {
                    if (col1List.Count <= col2List.Count && col1List.Count <= col3List.Count) col1List.Add(file);
                    else if (col2List.Count <= col3List.Count) col2List.Add(file);
                    else col3List.Add(file);
                }
            }

            int targetPerCol = (int)Math.Ceiling(rawItems.Count / 3.0);
            while (col3List.Count > targetPerCol && (col2List.Count < targetPerCol || col1List.Count < targetPerCol)) {
                if (col2List.Count < targetPerCol) {
                    col2List.Add(col3List[col3List.Count - 1]);
                    col3List.RemoveAt(col3List.Count - 1);
                } else if (col1List.Count < targetPerCol) {
                    col1List.Add(col3List[col3List.Count - 1]);
                    col3List.RemoveAt(col3List.Count - 1);
                } else break;
            }
            while (col1List.Count > targetPerCol && (col2List.Count < targetPerCol || col3List.Count < targetPerCol)) {
                if (col2List.Count < targetPerCol) {
                    col2List.Add(col1List[col1List.Count - 1]);
                    col1List.RemoveAt(col1List.Count - 1);
                } else if (col3List.Count < targetPerCol) {
                    col3List.Add(col1List[col1List.Count - 1]);
                    col1List.RemoveAt(col1List.Count - 1);
                } else break;
            }

            int[] colX = new int[] { 5, 111, 217 };
            int startY = 2;
            int spacingY = 154;
            int tol = onlyIfNeeded ? 15 : 2;

            List<DesktopItem>[] cols = new List<DesktopItem>[] { col1List, col2List, col3List };
            for (int c = 0; c < 3; c++) {
                for (int r = 0; r < cols[c].Count; r++) {
                    int targetX = colX[c];
                    int targetY = startY + (r * spacingY);
                    DesktopItem it = cols[c][r];
                    if (Math.Abs(it.X - targetX) > tol || Math.Abs(it.Y - targetY) > tol) {
                        int lParam = (targetY << 16) | (targetX & 0xFFFF);
                        SendMessage(hList, LVM_SETITEMPOSITION, (IntPtr)it.Index, (IntPtr)lParam);
                        mCount++;
                    }
                }
            }

            if (mCount > 0 || !onlyIfNeeded) {
                if (mCount > 0) {
                    RedrawWindow(hList, IntPtr.Zero, IntPtr.Zero, RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW);
                    Log(string.Format("Arranged {0} items (moved {1}; Col1:{2}, Col2:{3}, Col3:{4}).", rawItems.Count, mCount, col1List.Count, col2List.Count, col3List.Count));
                }
            }
        });
        worker.Start();
        worker.Join();
        totalCount = tCount;
        movedCount = mCount;
    }

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

    private static void SetItemStateSafely(IntPtr hProc, IntPtr hList, int itemIndex, uint state, uint stateMask) {
        IntPtr pMem = VirtualAllocEx(hProc, IntPtr.Zero, (uint)Marshal.SizeOf(typeof(LVITEM)), 0x1000, 0x04);
        if (pMem == IntPtr.Zero) return;
        LVITEM lv = new LVITEM();
        lv.stateMask = stateMask;
        lv.state = state;
        IntPtr written;
        WriteProcessMemory(hProc, pMem, ref lv, (uint)Marshal.SizeOf(typeof(LVITEM)), out written);
        SendMessage(hList, LVM_SETITEMSTATE, (IntPtr)itemIndex, pMem);
        VirtualFreeEx(hProc, pMem, 0, 0x8000);
    }

    private static void InstallKeyboardHook() {
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule) {
            _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(curModule.ModuleName), 0);
        }
        Log("Keyboard hook installed: " + (_hookId != IntPtr.Zero));
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        try {
            if (nCode >= 0) {
                int vkCode = Marshal.ReadInt32(lParam);
                if (wParam == (IntPtr)WM_KEYUP && (vkCode == VK_SHIFT || vkCode == 0xA0 || vkCode == 0xA1)) {
                    _anchorIndex = -1;
                } else if (wParam == (IntPtr)WM_KEYDOWN) {
                    bool isShift = (GetAsyncKeyState(VK_SHIFT) < 0);
                    if (!isShift) {
                        _anchorIndex = -1;
                    } else if (IsDesktopForeground()) {
                        if (vkCode == VK_DOWN || vkCode == VK_UP) {
                            if (HandleVerticalSelection(vkCode == VK_DOWN)) {
                                return (IntPtr)1;
                            }
                        } else if (vkCode == VK_RIGHT || vkCode == VK_LEFT) {
                            if (HandleHorizontalSelection(vkCode == VK_RIGHT)) {
                                return (IntPtr)1;
                            }
                        }
                    }
                }
            }
        } catch {}
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

        List<PosItem> colItems = new List<PosItem>();
        for (int i = 0; i < count; i++) {
            SendMessage(hList, LVM_GETITEMPOSITION, (IntPtr)i, pPoint);
            ReadProcessMemory(hProc, pPoint, ptb, (uint)ptb.Length, out read);
            int x = BitConverter.ToInt32(ptb, 0);
            int y = BitConverter.ToInt32(ptb, 4);
            if (Math.Abs(x - curX) <= 35) {
                colItems.Add(new PosItem { Index = i, X = x, Y = y });
            }
        }
        VirtualFreeEx(hProc, pPoint, 0, 0x8000);

        if (colItems.Count <= 1) {
            CloseHandle(hProc);
            return false;
        }

        colItems.Sort((a, b) => a.Y.CompareTo(b.Y));

        int curPos = -1;
        int anchorPos = -1;
        for (int i = 0; i < colItems.Count; i++) {
            if (colItems[i].Index == focused) curPos = i;
            if (colItems[i].Index == _anchorIndex) anchorPos = i;
        }

        if (curPos < 0) {
            CloseHandle(hProc);
            return false;
        }

        if (anchorPos < 0) {
            _anchorIndex = focused;
            anchorPos = curPos;
        }

        int targetPos = isDown ? (curPos + 1) : (curPos - 1);
        if (targetPos < 0 || targetPos >= colItems.Count) {
            CloseHandle(hProc);
            return true;
        }

        int minP = Math.Min(anchorPos, targetPos);
        int maxP = Math.Max(anchorPos, targetPos);
        int oldMinP = Math.Min(anchorPos, curPos);
        int oldMaxP = Math.Max(anchorPos, curPos);

        for (int p = oldMinP; p <= oldMaxP; p++) {
            if (p < minP || p > maxP) {
                SetItemStateSafely(hProc, hList, colItems[p].Index, 0, (uint)LVIS_SELECTED);
            }
        }

        for (int p = minP; p <= maxP; p++) {
            uint state = (uint)LVIS_SELECTED;
            uint mask = (uint)LVIS_SELECTED;
            if (p == targetPos) {
                state |= (uint)LVIS_FOCUSED;
                mask |= (uint)LVIS_FOCUSED;
            }
            SetItemStateSafely(hProc, hList, colItems[p].Index, state, mask);
        }

        CloseHandle(hProc);
        return true;
    }

    private static bool HandleHorizontalSelection(bool isRight) {
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

        List<PosItem> allItems = new List<PosItem>();
        for (int i = 0; i < count; i++) {
            SendMessage(hList, LVM_GETITEMPOSITION, (IntPtr)i, pPoint);
            ReadProcessMemory(hProc, pPoint, ptb, (uint)ptb.Length, out read);
            int x = BitConverter.ToInt32(ptb, 0);
            int y = BitConverter.ToInt32(ptb, 4);
            allItems.Add(new PosItem { Index = i, X = x, Y = y });
        }
        VirtualFreeEx(hProc, pPoint, 0, 0x8000);

        if (allItems.Count <= 1) {
            CloseHandle(hProc);
            return false;
        }

        allItems.Sort((a, b) => {
            int rowA = a.Y / 80;
            int rowB = b.Y / 80;
            if (rowA != rowB) return rowA.CompareTo(rowB);
            return a.X.CompareTo(b.X);
        });

        int curPos = -1;
        int anchorPos = -1;
        for (int i = 0; i < allItems.Count; i++) {
            if (allItems[i].Index == focused) curPos = i;
            if (allItems[i].Index == _anchorIndex) anchorPos = i;
        }

        if (curPos < 0) {
            CloseHandle(hProc);
            return false;
        }

        if (anchorPos < 0) {
            _anchorIndex = focused;
            anchorPos = curPos;
        }

        int targetPos = isRight ? (curPos + 1) : (curPos - 1);
        if (targetPos < 0 || targetPos >= allItems.Count) {
            CloseHandle(hProc);
            return true;
        }

        int minP = Math.Min(anchorPos, targetPos);
        int maxP = Math.Max(anchorPos, targetPos);
        int oldMinP = Math.Min(anchorPos, curPos);
        int oldMaxP = Math.Max(anchorPos, curPos);

        for (int p = oldMinP; p <= oldMaxP; p++) {
            if (p < minP || p > maxP) {
                SetItemStateSafely(hProc, hList, allItems[p].Index, 0, (uint)LVIS_SELECTED);
            }
        }

        for (int p = minP; p <= maxP; p++) {
            uint state = (uint)LVIS_SELECTED;
            uint mask = (uint)LVIS_SELECTED;
            if (p == targetPos) {
                state |= (uint)LVIS_FOCUSED;
                mask |= (uint)LVIS_FOCUSED;
            }
            SetItemStateSafely(hProc, hList, allItems[p].Index, state, mask);
        }

        CloseHandle(hProc);
        return true;
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'DesktopOrganizerDaemon').Type) {
    Add-Type -TypeDefinition $cSharpSource -ReferencedAssemblies @("System.Windows.Forms")
}

if ($DaemonMode) {
    [DesktopOrganizerDaemon]::RunDaemon()
    exit 0
}

if (-not $BatchPath) {
    $BatchPath = Join-Path (Get-Location).Path "DesktopOrganizer_Start.bat"
}

$dataDir = Join-Path $env:LOCALAPPDATA "DesktopOrganizer"
if (-not (Test-Path -LiteralPath $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}
$pidFile = Join-Path $dataDir "desktop_organizer.pid"

# Clean up legacy files
$scriptDir = Split-Path -Parent $BatchPath
if ($scriptDir) {
    $oldPid = Join-Path $scriptDir "desktop_organizer.pid"
    if (Test-Path -LiteralPath $oldPid) { Remove-Item -LiteralPath $oldPid -Force -ErrorAction SilentlyContinue }
}
$startupFolder = [Environment]::GetFolderPath('Startup')
$oldVbs = Join-Path $startupFolder "DesktopOrganizer_Startup.vbs"
if (Test-Path -LiteralPath $oldVbs) {
    Remove-Item -LiteralPath $oldVbs -Force -ErrorAction SilentlyContinue
}

# Stop existing scheduled task & daemon processes
$taskName = "DesktopOrganizerDaemon"
try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch {}
$psProcs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'"
foreach ($proc in $psProcs) {
    if ($proc.ProcessId -eq $PID) { continue }
    $cmd = $proc.CommandLine
    if (-not $cmd) { continue }
    $isTarget = ($cmd -like "*DesktopOrganizer_Start.bat*-DaemonMode*") -or ($cmd -like "*DesktopOrganizerDaemon*")
    if (-not $isTarget -and $cmd -match '-EncodedCommand\s+([A-Za-z0-9+/=]+)') {
        try {
            $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($matches[1]))
            if ($decoded -like "*DesktopOrganizer_Start.bat*") { $isTarget = $true }
        } catch {}
    }
    if ($isTarget) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[1/3] Running immediate 3-column arrangement and Jamo check..."
$summary = [DesktopOrganizerDaemon]::RunOnce()
Write-Host "  [OK] $summary"

Write-Host "[2/3] Registering interactive Windows startup task (no VBS, no black window)..."
$daemonScript = "& { `$p = '$BatchPath'; & ([scriptblock]::Create((Get-Content -LiteralPath `$p -Encoding UTF8 -Raw))) -DaemonMode -BatchPath `$p }"
$bytes = [System.Text.Encoding]::Unicode.GetBytes($daemonScript)
$encoded = [Convert]::ToBase64String($bytes)

# Remove old HKCU Run entry if present (ScheduledTask handles logon cleanly without console flash)
$runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
if (Get-ItemProperty -Path $runKeyPath -Name "DesktopOrganizer" -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKeyPath -Name "DesktopOrganizer" -Force -ErrorAction SilentlyContinue
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "  [OK] Registered Scheduled Task: $taskName"

Write-Host "[3/3] Starting continuous interactive daemon..."
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Milliseconds 1500

$daemonPid = $null
$psAfter = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'"
foreach ($proc in $psAfter) {
    if ($proc.ProcessId -eq $PID) { continue }
    $cmd = $proc.CommandLine
    if ($cmd -and $cmd -match '-EncodedCommand\s+([A-Za-z0-9+/=]+)') {
        try {
            $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($matches[1]))
            if ($decoded -like "*DesktopOrganizer_Start.bat*") {
                $daemonPid = $proc.ProcessId
                break
            }
        } catch {}
    }
}

if ($daemonPid) {
    [System.IO.File]::WriteAllText($pidFile, $daemonPid.ToString(), [System.Text.Encoding]::ASCII)
    Write-Host "  [OK] Continuous daemon active in interactive session (PID: $daemonPid)."
} else {
    Write-Host "  [Warning] Daemon did not stay active. Check $env:TEMP\DesktopOrganizer_daemon.log"
}
