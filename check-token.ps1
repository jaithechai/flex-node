# Reports what the token in .env is allowed to do. Never prints the token.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$config = @{ REPO = 'jaithechai/flex-node' }
if (-not (Test-Path -LiteralPath "$PSScriptRoot\.env")) { Write-Host 'No .env file next to this script.'; exit 1 }
foreach ($line in Get-Content -LiteralPath "$PSScriptRoot\.env") {
    if ($line -match '^\s*([^#=\s]+)\s*=(.*)$') { $config[$matches[1]] = $matches[2].Trim() }
}
$token = $config.GITHUB_TOKEN
if (-not $token) { Write-Host 'GITHUB_TOKEN is empty in .env.'; exit 1 }
$kind = 'unrecognized, probably pasted wrong'
if ($token.StartsWith('github_pat_')) { $kind = 'fine-grained' } elseif ($token.StartsWith('ghp_')) { $kind = 'classic' }
Write-Host "Token kind: $kind, $($token.Length) characters"
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'flex-node' }
function Probe($label, $method, $uri, $body) {
    $request = @{ Method = $method; Uri = $uri; Headers = $headers; TimeoutSec = 30 }
    if ($body) { $request.Body = $body; $request.ContentType = 'application/json' }
    try { $result = Invoke-RestMethod @request; Write-Host "$label : OK"; return $result }
    catch {
        $response = $_.Exception.Response
        if (-not $response) { Write-Host "$label : FAILED, $($_.Exception.Message)"; return }
        Write-Host "$label : FAILED $([int]$response.StatusCode). Needs: $($response.Headers['X-Accepted-GitHub-Permissions']). Classic scopes held: $($response.Headers['X-OAuth-Scopes'])"
    }
}
$user = Probe 'Token owner lookup' GET 'https://api.github.com/user'
if ($user) { Write-Host "  Token belongs to account: $($user.login)" }
$null = Probe "Read $($config.REPO)" GET "https://api.github.com/repos/$($config.REPO)"
# Creating a blob is the first write status.ps1 makes; an unreferenced blob is harmless.
$null = Probe "Write to $($config.REPO)" POST "https://api.github.com/repos/$($config.REPO)/git/blobs" '{"content":"probe","encoding":"utf-8"}'
