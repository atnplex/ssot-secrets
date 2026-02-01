# install-launcher.ps1
# Install the Antigravity launcher as a PowerShell function

$launcherPath = "C:\Users\Alex\atn-secrets-manager\launch-antigravity.ps1"

$functionDefinition = @"

# ═══════════════════════════════════════════════════════════════════════════
# ATN SECRETS MANAGER - Auto-injected on $(Get-Date -Format 'yyyy-MM-dd')
# ═══════════════════════════════════════════════════════════════════════════

function antigravity {
    <#
    .SYNOPSIS
        Launch Antigravity with automatic Bitwarden secret injection
    .DESCRIPTION
        Self-healing launcher that ensures GitHub tokens are always present
    .PARAMETER Force
        Force refresh token even if already set
    #>
    param([switch]`$Force)

    & "$launcherPath" -Force:`$Force
}

# Alias for convenience
Set-Alias -Name ag -Value antigravity -Force -Description "Short alias for Antigravity launcher"

Write-Host "✓ Antigravity launcher ready. Type 'antigravity' to launch." -ForegroundColor Green

"@

# Detect profile path
if (-not $PROFILE) {
  Write-Error "PowerShell profile path not found"
  exit 1
}

Write-Host "`n>> Installing Antigravity launcher to PowerShell profile..." -ForegroundColor Cyan
Write-Host "   Profile: $PROFILE`n"

# Create profile if it doesn't exist
if (-not (Test-Path $PROFILE)) {
  New-Item -Path $PROFILE -ItemType File -Force | Out-Null
  Write-Host "   ✓ Created new profile file" -ForegroundColor Green
}

# Read existing profile
$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue

# Remove old ATN SECRETS MANAGER block if exists
if ($profileContent -match "(?s)# ═+\s*ATN SECRETS MANAGER.*?# ═+") {
  Write-Host "   → Removing old launcher definition..." -ForegroundColor Yellow
  $profileContent = $profileContent -replace "(?s)# ═+\s*ATN SECRETS MANAGER.*?# ═+\s*", ""
}

# Append new function
$newContent = $profileContent.TrimEnd() + "`n`n" + $functionDefinition

Set-Content -Path $PROFILE -Value $newContent -Force

Write-Host "   ✓ Launcher installed successfully!`n" -ForegroundColor Green

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""
Write-Host "  🎯 Next steps:" -ForegroundColor Cyan
Write-Host "     1. Close this Antigravity window"
Write-Host "     2. Open a new terminal"
Write-Host "     3. Type: antigravity"
Write-Host ""
Write-Host "  The launcher will automatically:"
Write-Host "     ✓ Check for GitHub token"
Write-Host "     ✓ Fetch from Bitwarden if missing"
Write-Host "     ✓ Launch Antigravity with full API access"
Write-Host ""
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Magenta
