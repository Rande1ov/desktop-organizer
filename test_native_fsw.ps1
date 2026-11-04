$code = @'
using System;
using System.IO;
using System.Threading;

public class NativeWatcher {
    private static FileSystemWatcher _fsw;
    private static System.Threading.Timer _timer;
    public static bool Triggered = false;
    public static string LastEvent = "";

    public static void Start(string path) {
        _timer = new System.Threading.Timer(OnTimerElapsed, null, Timeout.Infinite, Timeout.Infinite);

        _fsw = new FileSystemWatcher(path);
        _fsw.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite;
        _fsw.Created += OnChanged;
        _fsw.Deleted += OnChanged;
        _fsw.Renamed += OnRenamed;
        _fsw.EnableRaisingEvents = true;
    }

    private static void OnChanged(object sender, FileSystemEventArgs e) {
        LastEvent = e.ChangeType + ": " + e.Name;
        _timer.Change(500, Timeout.Infinite);
    }

    private static void OnRenamed(object sender, RenamedEventArgs e) {
        LastEvent = "Renamed: " + e.Name;
        _timer.Change(500, Timeout.Infinite);
    }

    private static void OnTimerElapsed(object state) {
        Triggered = true;
    }
}
'@

Add-Type -TypeDefinition $code
$dir = [Environment]::GetFolderPath('Desktop')
[NativeWatcher]::Start($dir)
Write-Output "NativeWatcher started on: $dir"

$testFile = Join-Path $dir "test_native_fsw.txt"
Set-Content -LiteralPath $testFile -Value "abc"
Start-Sleep -Seconds 1
Write-Output "Triggered after create: $([NativeWatcher]::Triggered) | Event: $([NativeWatcher]::LastEvent)"

[NativeWatcher]::Triggered = $false
Remove-Item -LiteralPath $testFile -Force
Start-Sleep -Seconds 1
Write-Output "Triggered after delete: $([NativeWatcher]::Triggered) | Event: $([NativeWatcher]::LastEvent)"
