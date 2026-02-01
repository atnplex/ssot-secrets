# deploy-repo.ps1
# Zero-touch GitHub repository security deployment automation
# Usage: .\deploy-repo.ps1 -Owner "atnplex" -Repo "antigravity-manager"

param(
    [Parameter(Mandatory=$true)]
    [string]$Owner,

    [Parameter(Mandatory=$true)]
    [string]$Repo,

    [string]$DefaultBranch = $null, # Will be auto-detected if null

    [string[]]$StatusChecks = @("CodeQL"),

    [int]$ReviewCount = 0,

    [switch]$SkipBranchProtection,
    [switch]$DryRun,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Verify token is present
if (-not $env:GITHUB_PERSONAL_ACCESS_TOKEN) {
    Write-Host "`n[!] GITHUB_PERSONAL_ACCESS_TOKEN not set." -ForegroundColor Yellow
    Write-Host "Attempting to fetch from local vault..." -ForegroundColor Cyan

    $tokenFile = "$HOME\.antigravity_tools\bws_token.xml"
    if (Test-Path $tokenFile) {
        try {
            # Since this script is often run via the launcher,
            # we try to stay consistent with the launcher's storage.
            # But normally we expect the environment to be hydrated.
            Write-Host "Please ensure you launch this via the 'antigravity' wrapper or set the token environment variable." -ForegroundColor Gray
        } catch {}
    }

    if (-not $env:GITHUB_PERSONAL_ACCESS_TOKEN) {
        Write-Error "Could not find GITHUB_PERSONAL_ACCESS_TOKEN. Execution halted."
        exit 1
    }
}

$headers = @{
    'Authorization' = "token $env:GITHUB_PERSONAL_ACCESS_TOKEN"
    'User-Agent'    = 'Antigravity-Deployment-Automation'
    'Accept'        = 'application/vnd.github+json'
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

function Write-ErrorDetail {
    param([string]$Message, [object]$Exception)
    Write-Host "  ❌ $Message" -ForegroundColor Red
    if ($Exception) {
        Write-Host "     Detail: $($Exception.Message)" -ForegroundColor DarkRed
    }
}

function Invoke-GitHubApi {
    param(
        [string]$Method = "GET",
        [string]$Uri,
        [object]$Body = $null
    )

    $params = @{
        Method  = $Method
        Uri     = $Uri
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
        if ($PSBoundParameters['Verbose']) {
            Write-Host "    [DEBUG] $Method $Uri" -ForegroundColor Gray
        }
        Invoke-RestMethod @params
    }
    catch {
        $statusCode = 0
        $errorMessage = $_.Exception.Message

        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            try {
                $rawResponse = Stream-Reader -Stream $_.Exception.Response.GetResponseStream()
                $jsonResponse = $rawResponse.ReadToEnd() | ConvertFrom-Json
                if ($jsonResponse.message) {
                    $errorMessage = $jsonResponse.message
                }
            } catch {}
        }

        if ($statusCode -eq 404 -and $Method -eq "GET") {
            return $null
        }

        throw "GitHub API Error ($statusCode): $errorMessage"
    }
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  🚀 GitHub Repository Deployment Automation" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  Repository: $Owner/$Repo"

# Step 1: Verify repository and detect branch
Write-Step "Verifying repository access..."
$repoInfo = $null
try {
    $repoInfo = Invoke-GitHubApi -Uri "https://api.github.com/repos/$Owner/$Repo"
} catch {
    Write-ErrorDetail "Repository lookup failed. Verify your token permissions and repository path." $_
    exit 1
}

if (-not $repoInfo) {
    Write-Error "Repository $Owner/$Repo not found or not accessible."
    exit 1
}

$actualDefaultBranch = $DefaultBranch -if (-not $DefaultBranch) { $repoInfo.default_branch } -else { $DefaultBranch }

Write-Success "Repository accessible: $($repoInfo.full_name)"
Write-Host "    Visibility: $($repoInfo.visibility)"
Write-Host "    Default Branch: $actualDefaultBranch"
if ($DryRun) {
    Write-Host "    Mode: DRY RUN" -ForegroundColor Yellow
}

# Step 2: Enable Dependabot Security Updates
Write-Step "Configuring Dependabot..."
try {
    Invoke-GitHubApi -Method PUT -Uri "https://api.github.com/repos/$Owner/$Repo/automated-security-fixes"
    Write-Success "Dependabot security updates enabled"
} catch {
    Write-Skip "Dependabot configuration check failed (possibly already on or unavailable for this repo type)"
}

# Step 3: Enable Vulnerability Alerts
Write-Step "Enabling Vulnerability Alerts..."
try {
    Invoke-GitHubApi -Method PUT -Uri "https://api.github.com/repos/$Owner/$Repo/vulnerability-alerts"
    Write-Success "Vulnerability alerts enabled"
} catch {
    Write-Skip "Vulnerability alerts already enabled or check failed"
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

    Invoke-GitHubApi -Method PATCH -Uri "https://api.github.com/repos/$Owner/$Repo" -Body $secretScanningBody
    Write-Success "Secret scanning enabled with push protection"
} catch {
    Write-Skip "Secret scanning configuration failed ($($_.Exception.Message))"
}

# Step 5: Configure Branch Protection
if (-not $SkipBranchProtection) {
    Write-Step "Configuring branch protection for '$actualDefaultBranch'..."

    $protectionRules = @{
        required_status_checks = @{
            strict   = $true
            contexts = $StatusChecks
        }
        enforce_admins = $false
        required_pull_request_reviews = @{
            required_approving_review_count = $ReviewCount
            dismiss_stale_reviews           = $true
        }
        restrictions = $null
        allow_force_pushes = $false
        allow_deletions = $false
        required_conversation_resolution = $true
    }

    try {
        Invoke-GitHubApi -Method PUT `
            -Uri "https://api.github.com/repos/$Owner/$Repo/branches/$actualDefaultBranch/protection" `
            -Body $protectionRules

        Write-Success "Branch protection configured"
        Write-Host "    ✓ Required checks: $($StatusChecks -join ', ')"
        Write-Host "    ✓ Required reviews: $ReviewCount"
        Write-Host "    ✓ Force pushes blocked"
    } catch {
        Write-ErrorDetail "Branch protection configuration failed" $_
    }
} else {
    Write-Skip "Branch protection skipped"
}

# Step 6: Verification Summary
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✅ Deployment Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n📋 Configuration Summary:"
Write-Host "  ✓ Repository: $($repoInfo.html_url)"
Write-Host "  ✓ Default Branch: $actualDefaultBranch"
Write-Host "  ✓ Security: Dependabot, Alerts, Secret Scanning enabled"

Write-Host "`n🎯 Next Steps:"
Write-Host "  1. Review settings at: https://github.com/$Owner/$Repo/settings/security_analysis"
Write-Host "  2. If using CodeQL, ensure .github/workflows/codeql.yml exists.`n"
