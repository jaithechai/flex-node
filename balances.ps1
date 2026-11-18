param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$config = @{ REPO = 'jaithechai/flex-node' }
if (Test-Path -LiteralPath "$PSScriptRoot\.env") {
    foreach ($line in Get-Content -LiteralPath "$PSScriptRoot\.env") {
        if ($line -match '^\s*([^#=\s]+)\s*=(.*)$') { $config[$matches[1]] = $matches[2].Trim() }
    }
}
function Get-Balance($name, $token, $uri) {
    $app = [ordered]@{ name = $name; usd = $null; error = $null }
    if (-not $token) { $app.error = 'no token'; return $app }
    try {
        $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'User-Agent' = 'flex-node' }
        $data = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -TimeoutSec 30
    } catch {
        $app.error = 'request failed'
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            $app.error = if ($code -eq 401) { 'token expired' } else { "HTTP $code" }
        }
        return $app
    }
    $value = if ($name -eq 'Honeygain') {
        if ($null -ne $data.data.payout.usd_cents) { $data.data.payout.usd_cents }
        else { $data.data.payout.total_usd_cents }
    } else { $data.balance }
    [double]$number = 0
    if ($null -eq $value -or $value -is [bool] -or
        -not [double]::TryParse([string]$value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or
        [double]::IsNaN($number) -or [double]::IsInfinity($number)) {
        $app.error = 'unexpected response'
    } else {
        if ($name -eq 'Honeygain') { $number /= 100 }
        $app.usd = [Math]::Round($number, 2)
    }
    return $app
}
$json = [ordered]@{
    time = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
    apps = @(
        Get-Balance 'Honeygain' $config.HONEYGAIN_TOKEN 'https://dashboard.honeygain.com/api/v1/users/balances'
        Get-Balance 'Pawns' $config.PAWNS_TOKEN 'https://api.pawns.app/api/v1/users/me/balance-dashboard'
    )
    version = 1
} | ConvertTo-Json -Depth 4
if ($DryRun) { Write-Output $json; exit 0 }
try {
    if ($config.REPO -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid repository.' }
    $null = Get-Command gh -ErrorAction Stop
    $api = "repos/$($config.REPO)/git"
    function Send-Git($method, $endpoint, $body) {
        $ErrorActionPreference = 'Continue'
        $result = ($body | ConvertTo-Json -Depth 6 -Compress) | gh api --method $method "$api/$endpoint" --input - --jq .sha 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }
        return $result
    }
    $blob = Send-Git POST 'blobs' @{ content = $json; encoding = 'utf-8' }
    if (-not $blob) { throw 'Missing blob.' }
    $tree = Send-Git POST 'trees' @{ tree = @(@{ path = 'balances.json'; mode = '100644'; type = 'blob'; sha = $blob }) }
    if (-not $tree) { throw 'Missing tree.' }
    $author = @{ name = 'flex-node'; email = 'flex-node@example.invalid' }
    $commit = Send-Git POST 'commits' @{ message = 'Report balances'; tree = $tree; parents = @(); author = $author; committer = $author }
    if (-not $commit) { throw 'Missing commit.' }
    try { $null = Send-Git PATCH 'refs/heads/balances' @{ sha = $commit; force = $true } }
    catch { $null = Send-Git POST 'refs' @{ ref = 'refs/heads/balances'; sha = $commit } }
} catch {
    [Console]::Error.WriteLine('Balance publish failed.'); exit 1
}
exit 0
