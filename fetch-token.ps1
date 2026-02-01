# fetch-token.ps1
# Fetch GitHub token from Bitwarden and inject into current session

$bws = "C:\Users\Alex\AppData\Local\Programs\Bitwarden\bws.exe"

# Check for BWS_ACCESS_TOKEN
if (-not $env:BWS_ACCESS_TOKEN) {
    Write-Host ">> BWS_ACCESS_TOKEN is required to fetch secrets from Bitwarden." -ForegroundColor Yellow
    $token = Read-Host "Please paste your Bitwarden SM Machine Access Token"
    $env:BWS_ACCESS_TOKEN = $token
}

# Fetch the secret from Bitwarden
Write-Host ">> Fetching GITHUB_PERSONAL_ACCESS_TOKEN from Bitwarden..." -ForegroundColor Cyan
try {
    $secrets = & $bws secret list "5784e91c-974d-4b76-97ad-b3d8002cd4a5" | ConvertFrom-Json

    # Find the GitHub token (check both possible names)
    $ghSecret = $secrets | Where-Object { $_.key -eq "GITHUB_PERSONAL_ACCESS_TOKEN" -or $_.key -eq "github" } | Select-Object -First 1

    if (-not $ghSecret) {
        Write-Error "GitHub token not found in Bitwarden project. Available keys: $($secrets.key -join ', ')"
        exit 1
    }

    # Get the actual secret value
    $secretDetail = & $bws secret get $ghSecret.id | ConvertFrom-Json
    $env:GITHUB_PERSONAL_ACCESS_TOKEN = $secretDetail.value

    Write-Host "✅ Token injected! Length: $($env:GITHUB_PERSONAL_ACCESS_TOKEN.Length)" -ForegroundColor Green
    Write-Host ">> The token is now available for this session." -ForegroundColor Cyan

} catch {
    Write-Error "Failed to fetch secret: $_"
    exit 1
}
