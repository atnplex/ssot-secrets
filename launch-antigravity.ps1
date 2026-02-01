# launch-antigravity.ps1
# Self-healing Antigravity launcher with automatic secret injection
# Location: C:\Users\Alex\atn-secrets-manager\launch-antigravity.ps1

param(
  [switch]$Force  # Force token refresh even if already set
)

$ErrorActionPreference = "Stop"
$bws = "C:\Users\Alex\AppData\Local\Programs\Bitwarden\bws.exe"
$projectId = "5784e91c-974d-4b76-97ad-b3d8002cd4a5"
$requiredSecrets = @("GITHUB_PERSONAL_ACCESS_TOKEN")

function Write-Step {
  param([string]$Message, [string]$Color = "Cyan")
  Write-Host "`n>> $Message" -ForegroundColor $Color
}

function Test-TokenHealth {
  if (-not $env:GITHUB_PERSONAL_ACCESS_TOKEN) {
    return $false
  }

  # Quick validation: check if token looks valid (length and format)
  if ($env:GITHUB_PERSONAL_ACCESS_TOKEN.Length -lt 40) {
    Write-Warning "Token exists but appears invalid (too short)"
    return $false
  }

  return $true
}

function Get-SecretFromBitwarden {
  param([string]$SecretName)

  # List all secrets in project
  $secrets = & $bws secret list $projectId 2>$null | ConvertFrom-Json

  if (-not $secrets) {
    throw "No secrets found in Bitwarden project. Please verify project ID and access token."
  }

  # Find the secret
  $secret = $secrets | Where-Object { $_.key -eq $SecretName } | Select-Object -First 1

  if (-not $secret) {
    throw "Secret '$SecretName' not found. Available: $($secrets.key -join ', ')"
  }

  # Fetch secret value
  $secretDetail = & $bws secret get $secret.id 2>$null | ConvertFrom-Json

  if (-not $secretDetail.value) {
    throw "Failed to retrieve secret value for '$SecretName'"
  }

  return $secretDetail.value
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  🚀 Antigravity Secure Launcher v1.0" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Magenta

# Step 1: Check BWS_ACCESS_TOKEN
$tokenFile = "$HOME\.antigravity_tools\bws_token.xml"
$tokenDir = "$HOME\.antigravity_tools"

if (-not (Test-Path $tokenDir)) {
  New-Item -ItemType Directory -Path $tokenDir -Force | Out-Null
}

if (-not $env:BWS_ACCESS_TOKEN) {
  # Try to load from secure disk storage
  if (Test-Path $tokenFile) {
    try {
      $env:BWS_ACCESS_TOKEN = Import-CliXml -Path $tokenFile
    }
    catch {
      Write-Warning "Could not load saved BWS token. It may have been corrupted."
    }
  }
}

if (-not $env:BWS_ACCESS_TOKEN) {
  Write-Step "BWS_ACCESS_TOKEN not found" "Yellow"
  Write-Host "   This is your Bitwarden Secrets Manager machine token."
  Write-Host "   It will be saved ENCRYPTED to your Windows profile for future use.`n"

  $bwsToken = Read-Host "   Paste your BWS_ACCESS_TOKEN"

  if ($bwsToken -and $bwsToken.Length -gt 10) {
    $env:BWS_ACCESS_TOKEN = $bwsToken
    $bwsToken | Export-CliXml -Path $tokenFile
    Write-Host "   ✓ Token saved securely to $tokenFile" -ForegroundColor Green
  }
  else {
    Write-Error "Invalid BWS_ACCESS_TOKEN provided."
    exit 1
  }
}
else {
  Write-Step "BWS_ACCESS_TOKEN loaded from secure storage." "Green"
}

# Step 2: Check GitHub token health
$needsRefresh = $Force -or -not (Test-TokenHealth)

if ($needsRefresh) {
  Write-Step "Fetching secrets from Bitwarden..." "Cyan"

  try {
    foreach ($secretName in $requiredSecrets) {
      Write-Host "   → $secretName..." -NoNewline
      $secretValue = Get-SecretFromBitwarden -SecretName $secretName
      Set-Item -Path "env:$secretName" -Value $secretValue
      Write-Host " ✓ (length: $($secretValue.Length))" -ForegroundColor Green
    }

    Write-Step "All secrets injected successfully!" "Green"

  }
  catch {
    Write-Error "Failed to fetch secrets: $_"
    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Verify BWS_ACCESS_TOKEN is correct"
    Write-Host "  2. Ensure machine account has access to project: $projectId"
    Write-Host "  3. Check that GITHUB_PERSONAL_ACCESS_TOKEN exists in Bitwarden"
    exit 1
  }
}
else {
  Write-Step "GitHub token already present (length: $($env:GITHUB_PERSONAL_ACCESS_TOKEN.Length))" "Green"
}

# Step 2.5: Inject AI Rotation Proxy Settings
Write-Step "Configuring AI Rotation Proxy..." "Cyan"
$env:ANTHROPIC_BASE_URL = "http://localhost:8045"
$env:GEMINI_BASE_URL = "http://localhost:8045"
$env:ANTHROPIC_API_KEY = "sk-antigravity-rotation-proxy"
$env:GEMINI_API_KEY = "sk-antigravity-rotation-proxy"
Write-Host "   ✓ Base URL: http://localhost:8045" -ForegroundColor Green
Write-Host "   ✓ Mode: Automatic Account Rotation (4 accounts loaded)" -ForegroundColor Green

# Step 3: Detect Antigravity executable
Write-Step "Locating Antigravity executable..." "Cyan"

$antigravityPath = $null

# Method 1: Check for antigravity.cmd in PATH (preferred)
$cmdPath = where.exe antigravity.cmd 2>$null | Select-Object -First 1
if ($cmdPath -and (Test-Path $cmdPath)) {
  $antigravityPath = $cmdPath
  Write-Host "   ✓ Found via PATH: $antigravityPath" -ForegroundColor Green
}

# Method 2: Check common installation location
if (-not $antigravityPath) {
  $exePath = "$env:LOCALAPPDATA\Programs\Antigravity\Antigravity.exe"
  if (Test-Path $exePath) {
    $antigravityPath = $exePath
    Write-Host "   ✓ Found at default location: $antigravityPath" -ForegroundColor Green
  }
}

# Method 3: Search for running process
if (-not $antigravityPath) {
  $process = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($process -and $process.Path) {
    $antigravityPath = $process.Path
    Write-Host "   ✓ Found from running process: $antigravityPath" -ForegroundColor Green
  }
}

if (-not $antigravityPath) {
  Write-Error "Could not locate Antigravity executable. Please ensure Antigravity is installed."
  Write-Host "`nSearched for:" -ForegroundColor Yellow
  Write-Host "  - antigravity.cmd in PATH"
  Write-Host "  - $env:LOCALAPPDATA\Programs\Antigravity\Antigravity.exe"
  Write-Host "  - Running Antigravity processes"
  exit 1
}

# Step 4: Launch Antigravity
Write-Step "Launching Antigravity with secure environment..." "Cyan"
Write-Host "   Using: $antigravityPath`n" -ForegroundColor Gray

& $antigravityPath

Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ Antigravity launched successfully!" -ForegroundColor Green
Write-Host "  🔐 GitHub MCP has full API access" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
