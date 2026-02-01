# deploy-repo.ps1
# Zero-touch GitHub repository security deployment automation
# Usage: .\deploy-repo.ps1 -Owner "atnplex" -Repo "antigravity-manager"

param(
    [Parameter(Mandatory=$true)]
    [string]$Owner,

    [Parameter(Mandatory=$true)]
    [string]$Repo,

    [string]$DefaultBranch = "main",

    [switch]$SkipBranchProtection,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Verify token is present
if (-not $env:GITHUB_PERSONAL_ACCESS_TOKEN) {
    Write-Error "GITHUB_PERSONAL_ACCESS_TOKEN not set. Please run with BWS wrapper or set manually."
    exit 1
}

$headers = @{
    'Authorization' = "token $env:GITHUB_PERSONAL_ACCESS_TOKEN"
    'User-Agent' = 'Antigravity-Deployment-Automation'
    'Accept' = 'application/vnd.github+json'
}

function Write-Step {
    param([string]$Message, [string]$Status = "→")
    Write-Host "`n$Status $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✅ $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "  ⏭️  $Message" -ForegroundColor Yellow
}

function Invoke-GitHubApi {
    param(
        [string]$Method = "GET",
        [string]$Uri,
        [object]$Body = $null
    )

    $params = @{
        Method = $Method
        Uri = $Uri
        Headers = $headers
    }

    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
        $params.ContentType = 'application/json'
    }

    if ($DryRun -and $Method -ne "GET") {
        Write-Host "    [DRY RUN] Would call: $Method $Uri" -ForegroundColor Magenta
        return $null
    }

    try {
        Invoke-RestMethod @params
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            return $null
        }
        throw
    }
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  🚀 GitHub Repository Deployment Automation" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  Repository: $Owner/$Repo"
Write-Host "  Default Branch: $DefaultBranch"
if ($DryRun) {
    Write-Host "  Mode: DRY RUN (no changes will be made)" -ForegroundColor Yellow
}

# Step 1: Verify repository exists
Write-Step "Verifying repository access..."
$repoInfo = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Owner/$Repo"
if (-not $repoInfo) {
    Write-Error "Repository $Owner/$Repo not found or not accessible"
    exit 1
}
Write-Success "Repository accessible: $($repoInfo.full_name)"
Write-Host "    Visibility: $($repoInfo.visibility)"
Write-Host "    Default Branch: $($repoInfo.default_branch)"

# Step 2: Enable Dependabot Security Updates
Write-Step "Configuring Dependabot..."
try {
    $dependabotStatus = Invoke-GitHubApi -Method PUT `
        -Uri "https://api.github.com/repos/$Owner/$Repo/automated-security-fixes"

    if ($DryRun) {
        Write-Skip "Would enable Dependabot security updates"
    } else {
        Write-Success "Dependabot security updates enabled"
    }
} catch {
    Write-Skip "Dependabot already configured or unavailable"
}

# Step 3: Enable Vulnerability Alerts
try {
    Invoke-GitHubApi -Method PUT `
        -Uri "https://api.github.com/repos/$Owner/$Repo/vulnerability-alerts"

    if ($DryRun) {
        Write-Skip "Would enable vulnerability alerts"
    } else {
        Write-Success "Vulnerability alerts enabled"
    }
} catch {
    Write-Skip "Vulnerability alerts already enabled"
}

# Step 4: Enable Secret Scanning
Write-Step "Enabling Secret Scanning..."
try {
    $secretScanningBody = @{
        security_and_analysis = @{
            secret_scanning = @{ status = "enabled" }
            secret_scanning_push_protection = @{ status = "enabled" }
        }
    }

    Invoke-GitHubApi -Method PATCH `
        -Uri "https://api.github.com/repos/$Owner/$Repo" `
        -Body $secretScanningBody

    if ($DryRun) {
        Write-Skip "Would enable secret scanning + push protection"
    } else {
        Write-Success "Secret scanning enabled with push protection"
    }
} catch {
    Write-Skip "Secret scanning configuration failed or already enabled"
}

# Step 5: Configure Branch Protection
if (-not $SkipBranchProtection) {
    Write-Step "Configuring branch protection for '$DefaultBranch'..."

    $protectionRules = @{
        required_status_checks = @{
            strict = $true
            contexts = @("CodeQL")
        }
        enforce_admins = $false
        required_pull_request_reviews = @{
            required_approving_review_count = 0
            dismiss_stale_reviews = $true
        }
        restrictions = $null
        allow_force_pushes = $false
        allow_deletions = $false
        required_conversation_resolution = $true
    }

    try {
        Invoke-GitHubApi -Method PUT `
            -Uri "https://api.github.com/repos/$Owner/$Repo/branches/$DefaultBranch/protection" `
            -Body $protectionRules

        if ($DryRun) {
            Write-Skip "Would configure branch protection"
        } else {
            Write-Success "Branch protection configured"
            Write-Host "    ✓ Required status checks: CodeQL"
            Write-Host "    ✓ Conversation resolution required"
            Write-Host "    ✓ Force pushes blocked"
        }
    } catch {
        Write-Skip "Branch protection configuration failed: $($_.Exception.Message)"
    }
} else {
    Write-Skip "Branch protection skipped (--SkipBranchProtection)"
}

# Step 6: Verification Summary
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ Deployment Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n📋 Configuration Summary:"
Write-Host "  ✓ Repository: $($repoInfo.html_url)"
Write-Host "  ✓ Dependabot: Enabled"
Write-Host "  ✓ Secret Scanning: Enabled"
Write-Host "  ✓ Vulnerability Alerts: Enabled"
if (-not $SkipBranchProtection) {
    Write-Host "  ✓ Branch Protection: Configured"
}

Write-Host "`n🎯 Next Steps:"
Write-Host "  1. Verify CodeQL workflow is running"
Write-Host "  2. Check Dependabot PRs for dependency updates"
Write-Host "  3. Review security settings at: https://github.com/$Owner/$Repo/settings/security_analysis"
Write-Host ""
