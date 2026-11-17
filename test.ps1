$ErrorActionPreference = 'Stop'
$output = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\status.ps1" -DryRun
if ($LASTEXITCODE -ne 0) { throw 'DryRun failed.' }
$json = $output -join "`n"
$data = $json | ConvertFrom-Json
foreach ($field in @('time', 'boot', 'on_ac', 'battery_pct', 'cpu_pct', 'ram_used_pct', 'disk_free_gb', 'watch', 'version')) {
    if ($data.PSObject.Properties.Name -notcontains $field) { throw "Missing field: $field" }
}
$time = [DateTimeOffset]::Parse($data.time)
if ([Math]::Abs(([DateTimeOffset]::UtcNow - $time).TotalMinutes) -gt 2) { throw 'Report time is not current.' }
foreach ($privateValue in @($env:COMPUTERNAME, $env:USERNAME)) {
    if ($privateValue -and $json.IndexOf($privateValue, [StringComparison]::OrdinalIgnoreCase) -ge 0) { throw 'Private machine or user name found.' }
}
Write-Output 'PASS'
