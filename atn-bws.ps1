# atn-bws.ps1
# Centralized Zero-Touch Secrets Pipeline CLI

$bws = "C:\Users\Alex\AppData\Local\Programs\Bitwarden\bws.exe"

function Write-Step ([string]$msg) {
    Write-Host "`n>> $msg" -ForegroundColor Cyan
}

function Get-BwsToken {
    if (-not $env:BWS_ACCESS_TOKEN) {
        Write-Host ">> BWS_ACCESS_TOKEN missing." -ForegroundColor Yellow
        $token = Read-Host "Paste Bitwarden SM Machine Access Token"
        $env:BWS_ACCESS_TOKEN = $token
    }
}

function Invoke-AtnSecureRun {
    param([string]$Command)
    Get-BwsToken
    Write-Step "Injecting secrets and running: $Command"
    & $bws run -- powershell -c "$Command"
}

function Update-AtnMcpConfig {
    param([string]$Path = "C:\Users\Alex\.gemini\antigravity\mcp_config.json")
    Write-Step "Hardening config: $Path"
    $config = Get-Content $Path | ConvertFrom-Json

    # Process GitHub
    if ($config.mcpServers."github-mcp-server") {
        $config.mcpServers."github-mcp-server".env.GITHUB_PERSONAL_ACCESS_TOKEN = '${env:GITHUB_PERSONAL_ACCESS_TOKEN}'
    }

    # Process Perplexity
    if ($config.mcpServers."perplexity-ask") {
        $config.mcpServers."perplexity-ask".env.PERPLEXITY_API_KEY = '${env:PERPLEXITY_API_KEY}'
    }

    $config | ConvertTo-Json -Depth 10 | Out-File $Path -Encoding UTF8
    Write-Host "✅ Config hardened (References injected env vars only)." -ForegroundColor Green
}

function Install-AtnAlias {
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (-not $profilePath) { $profilePath = $PROFILE }

    $aliasCode = @"

# --- ATN SECRETS PIPELINE ---
function antigravity {
    param([Parameter(ValueFromRemainingArguments=`$true)]$`RemainingArgs)
    & "C:\Users\Alex\atn-secrets-manager\atn-bws.ps1" run "antigravity `$RemainingArgs"
}
# ----------------------------
"@

    if (Test-Path $profilePath) {
        $content = Get-Content $profilePath -Raw
        if ($content -like "*ATN SECRETS PIPELINE*") {
            Write-Host ">> Alias already exists in $profilePath" -ForegroundColor Yellow
            return
        }
    }

    Write-Step "Installing secure alias to $profilePath..."
    Add-Content -Path $profilePath -Value $aliasCode
    Write-Host "✅ Secure alias installed!" -ForegroundColor Green
    Write-Host ">> Restart your terminal or run: . `$PROFILE" -ForegroundColor Cyan
}

# CLI Router
if ($args.Count -eq 0) {
    Write-Host "atn-bws Secrets Manager CLI"
    Write-Host "Usage: .\atn-bws.ps1 [run|harden|install-alias] [args]"
    exit
}

switch ($args[0]) {
    "run" { Invoke-AtnSecureRun -Command ($args[1..($args.Count - 1)] -join " ") }
    "harden" { Update-AtnMcpConfig -Path $args[1] }
    "install-alias" { Install-AtnAlias }
    default { Write-Host "Unknown command: $($args[0])" }
}
