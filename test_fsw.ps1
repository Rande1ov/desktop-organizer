$dir = "C:\Users\guswn\OneDrive\바탕 화면"
$fsw = New-Object System.IO.FileSystemWatcher
$fsw.Path = $dir
$fsw.EnableRaisingEvents = $true

$global:Detected = $false
$global:EventName = ""

$handler = {
    param($s, $e)
    $global:Detected = $true
    $global:EventName = "$($e.ChangeType): $($e.Name)"
}

$fsw.add_Created($handler)
$fsw.add_Deleted($handler)
$fsw.add_Renamed($handler)

Write-Output "Watcher started on $dir"
$testFile = Join-Path $dir "test_fsw_trigger.tmp.txt"
Set-Content -LiteralPath $testFile -Value "test"
Start-Sleep -Seconds 1
Write-Output "Detected after create: $global:Detected ($global:EventName)"

Remove-Item -LiteralPath $testFile -Force
Start-Sleep -Seconds 1
Write-Output "Detected after delete: $global:Detected ($global:EventName)"
$fsw.Dispose()
