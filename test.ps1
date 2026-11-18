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
$temp = Join-Path $PSScriptRoot ([Guid]::NewGuid().ToString())
try {
    $null = New-Item -ItemType Directory -Path $temp
    Copy-Item -LiteralPath "$PSScriptRoot\balances.ps1" -Destination $temp
    $output = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$temp\balances.ps1" -DryRun
    if ($LASTEXITCODE -ne 0) { throw 'Balances DryRun failed.' }
    $data = ($output -join "`n") | ConvertFrom-Json
    foreach ($field in @('time', 'version', 'apps')) {
        if ($data.PSObject.Properties.Name -notcontains $field) { throw "Missing balance field: $field" }
    }
    if ($data.version -ne 1 -or -not $data.time -or $data.apps -isnot [array] -or $data.apps.Count -ne 2) { throw 'Invalid balances report.' }
    $null = [DateTimeOffset]::Parse($data.time)
    for ($i = 0; $i -lt 2; $i++) {
        $app = $data.apps[$i]
        if ($app.name -ne @('Honeygain', 'Pawns')[$i] -or $app.PSObject.Properties.Name -notcontains 'usd' -or
            $null -ne $app.usd -or $app.error -ne 'no token') { throw 'Invalid no-token balance.' }
    }
} finally {
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($temp)) -ne $PSScriptRoot) { throw 'Invalid temp folder.' }
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Output 'PASS'
