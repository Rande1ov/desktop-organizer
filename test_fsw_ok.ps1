$dir = [Environment]::GetFolderPath('Desktop')
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

Write-Output "Watcher started on: $dir"
$testFile = Join-Path $dir "test_fsw_ok.txt"
Set-Content -LiteralPath $testFile -Value "test"
Start-Sleep -Milliseconds 600
Write-Output "Detected after create: $global:Detected ($global:EventName)"

Remove-Item -LiteralPath $testFile -Force
Start-Sleep -Milliseconds 600
Write-Output "Detected after delete: $global:Detected ($global:EventName)"
$fsw.Dispose()
