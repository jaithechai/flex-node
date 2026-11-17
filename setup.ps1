param([switch]$SkipApps)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run setup in an elevated PowerShell window.' }
function Set-Power($arguments) {
    & powercfg.exe @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Power configuration failed.' }
}
Set-Power @('/change', 'standby-timeout-ac', '0')
Set-Power @('/change', 'hibernate-timeout-ac', '0')
Set-Power @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_BUTTONS', 'LIDACTION', '0')
Set-Power @('/setactive', 'SCHEME_CURRENT')
if (-not $SkipApps) {
    foreach ($id in @('Tailscale.Tailscale', 'Google.ChromeRemoteDesktopHost')) {
        & winget.exe install -e --id $id
        if ($LASTEXITCODE -ne 0) {
            # Winget also returns nonzero when an installed app has no upgrade.
            & winget.exe list -e --id $id
            if ($LASTEXITCODE -ne 0) { throw "App installation failed: $id" }
        }
    }
}
if (-not (Test-Path -LiteralPath "$PSScriptRoot\.env")) { Copy-Item -LiteralPath "$PSScriptRoot\.env.example" -Destination "$PSScriptRoot\.env" }
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSScriptRoot\status.ps1`""
# Omitting RepetitionDuration keeps the ten-minute trigger running indefinitely.
$triggers = @(
    New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10)
    New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
)
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName 'flex-node-status' -Action $action -Trigger $triggers -Principal $taskPrincipal -Settings $settings -Force | Out-Null
Write-Output 'Setup complete. Fill in .env and finish the manual steps in README.md.'
