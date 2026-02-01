# inject-and-restart.ps1
# Fetch token from Bitwarden and restart Antigravity with it injected

$bws = "C:\Users\Alex\AppData\Local\Programs\Bitwarden\bws.exe"
$projectId = "5784e91c-974d-4b76-97ad-b3d8002cd4a5"

Write-Host ">> Fetching GitHub token from Bitwarden..." -ForegroundColor Cyan

# Check for BWS_ACCESS_TOKEN
if (-not $env:BWS_ACCESS_TOKEN) {
  Write-Host ">> BWS_ACCESS_TOKEN is required." -ForegroundColor Yellow
  $token = Read-Host "Please paste your Bitwarden SM Machine Access Token"
  $env:BWS_ACCESS_TOKEN = $token
}

try {
  # Fetch secrets
  $secrets = & $bws secret list $projectId | ConvertFrom-Json
  $ghSecret = $secrets | Where-Object { $_.key -eq "GITHUB_PERSONAL_ACCESS_TOKEN" } | Select-Object -First 1

  if (-not $ghSecret) {
    Write-Error "GITHUB_PERSONAL_ACCESS_TOKEN not found in Bitwarden"
    exit 1
  }

  # Get secret value
  $secretDetail = & $bws secret get $ghSecret.id | ConvertFrom-Json
  $githubToken = $secretDetail.value

  Write-Host "✅ Token fetched! Length: $($githubToken.Length)" -ForegroundColor Green

  # Close current Antigravity
  Write-Host "`n>> Closing current Antigravity session..." -ForegroundColor Yellow
  Stop-Process -Name "Code" -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2

  # Launch Antigravity with token injected
  Write-Host ">> Launching Antigravity with token injected..." -ForegroundColor Cyan
  $env:GITHUB_PERSONAL_ACCESS_TOKEN = $githubToken
  & code

  Write-Host "`n✅ Antigravity launched with secure token!" -ForegroundColor Green
  Write-Host ">> The token is now available in the new session." -ForegroundColor Cyan

}
catch {
  Write-Error "Failed: $_"
  exit 1
}
