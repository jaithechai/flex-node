param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$config = @{ REPO = 'jaithechai/flex-node'; WATCH = '' }
if (-not $DryRun -and (Test-Path -LiteralPath "$PSScriptRoot\.env")) {
    foreach ($line in Get-Content -LiteralPath "$PSScriptRoot\.env") {
        if ($line -match '^\s*([^#=\s]+)\s*=(.*)$') { $config[$matches[1]] = $matches[2].Trim() }
    }
}
Add-Type -AssemblyName System.Windows.Forms
if (-not ('FlexMetrics' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FlexMetrics {
    [StructLayout(LayoutKind.Sequential)] public struct Memory {
        public uint Length, Load;
        public ulong TotalPhys, AvailPhys, TotalPage, AvailPage, TotalVirtual, AvailVirtual, Extended;
    }
    [DllImport("kernel32.dll")] public static extern ulong GetTickCount64();
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GlobalMemoryStatusEx(ref Memory memory);
}
'@
}
[long]$idle1 = 0; [long]$kernel1 = 0; [long]$user1 = 0
[long]$idle2 = 0; [long]$kernel2 = 0; [long]$user2 = 0
if (-not [FlexMetrics]::GetSystemTimes([ref]$idle1, [ref]$kernel1, [ref]$user1)) { throw 'CPU measurement failed.' }
Start-Sleep -Milliseconds 250
if (-not [FlexMetrics]::GetSystemTimes([ref]$idle2, [ref]$kernel2, [ref]$user2)) { throw 'CPU measurement failed.' }
$total = ($kernel2 - $kernel1) + ($user2 - $user1)
$cpu = 0
if ($total -gt 0) { $cpu = [int][Math]::Round(100 * (1 - ($idle2 - $idle1) / $total)) }
$memory = New-Object FlexMetrics+Memory
$memory.Length = [System.Runtime.InteropServices.Marshal]::SizeOf($memory)
if (-not [FlexMetrics]::GlobalMemoryStatusEx([ref]$memory)) { throw 'RAM measurement failed.' }
$power = [System.Windows.Forms.SystemInformation]::PowerStatus
$battery = $null
if (([int]$power.BatteryChargeStatus -band 128) -eq 0 -and $power.BatteryLifePercent -ge 0 -and $power.BatteryLifePercent -le 1) {
    $battery = [int][Math]::Round(100 * $power.BatteryLifePercent)
}
$watch = @(foreach ($name in ($config.WATCH -split ',')) {
    $name = $name.Trim()
    if ($name) { @{ name = $name; running = [bool](Get-Process -Name $name -ErrorAction SilentlyContinue) } }
})
$now = [DateTime]::UtcNow
$json = [ordered]@{
    time = $now.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
    boot = $now.AddMilliseconds(-[double][FlexMetrics]::GetTickCount64()).ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
    on_ac = ($power.PowerLineStatus -eq 'Online')
    battery_pct = $battery
    cpu_pct = $cpu
    ram_used_pct = [int]$memory.Load
    disk_free_gb = [Math]::Round(([System.IO.DriveInfo]::new($env:SystemDrive)).AvailableFreeSpace / 1GB, 1)
    watch = $watch
    version = 1
} | ConvertTo-Json -Depth 4
if ($DryRun) { Write-Output $json; exit 0 }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$failed = $false
try {
    if (-not $config.GITHUB_TOKEN) { throw 'Missing token.' }
    if ($config.REPO -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid repository.' }
    $headers = @{ Authorization = "Bearer $($config.GITHUB_TOKEN)"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'flex-node' }
    $api = "https://api.github.com/repos/$($config.REPO)/git"
    function Send-Git($method, $endpoint, $body) {
        Invoke-RestMethod -Method $method -Uri "$api/$endpoint" -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 6 -Compress) -TimeoutSec 30
    }
    $blob = Send-Git POST 'blobs' @{ content = $json; encoding = 'utf-8' }
    $tree = Send-Git POST 'trees' @{ tree = @(@{ path = 'status.json'; mode = '100644'; type = 'blob'; sha = $blob.sha }) }
    $author = @{ name = 'flex-node'; email = 'flex-node@example.invalid' }
    $commit = Send-Git POST 'commits' @{ message = 'Report status'; tree = $tree.sha; parents = @(); author = $author; committer = $author }
    try { $null = Send-Git PATCH 'refs/heads/status' @{ sha = $commit.sha; force = $true } }
    catch {
        # GitHub answers 422, not 404, when the branch does not exist yet.
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -in 404, 422) {
            $null = Send-Git POST 'refs' @{ ref = 'refs/heads/status'; sha = $commit.sha }
        } else { throw }
    }
} catch { [Console]::Error.WriteLine('Status publish failed.'); $failed = $true }
if ($config.HEALTHCHECK_URL) {
    try {
        if (@($watch | Where-Object { -not $_.running }).Count) {
            $null = Invoke-WebRequest -UseBasicParsing -Method POST -Uri ($config.HEALTHCHECK_URL.TrimEnd('/') + '/fail') -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30
        } else {
            $null = Invoke-WebRequest -UseBasicParsing -Method GET -Uri $config.HEALTHCHECK_URL -TimeoutSec 30
        }
    } catch { [Console]::Error.WriteLine('Healthcheck ping failed.'); $failed = $true }
}
if ($failed) { exit 1 }
exit 0
