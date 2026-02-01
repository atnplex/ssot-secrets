# ATN Secrets Manager 🛡️

The ultimate zero-touch security and automation pipeline for the Antigravity ecosystem. This repository manages secret injection, repository hardening, and AI account rotation.

## 🚀 Core Features

- **Secure Launcher**: Automatically injects GitHub tokens from Bitwarden into Antigravity.
- **AI Rotation Proxy**: Seamlessly switch between multiple accounts (Claude/Gemini) to bypass rate limits.
- **Zero-Touch Deployment**: Harden any new repository with Dependabot, Secret Scanning, and Branch Protection in one command.
- **Self-Healing**: Automatically detects paths and valid tokens.

---

## 📖 Usage Guide

### 1. Launch Antigravity

Launch Antigravity with full GitHub API access and AI rotation enabled:

```powershell
antigravity
```

* **First Run**: Prompts for `BWS_ACCESS_TOKEN`.
- **Subsequent Runs**: Uses cached session token.
- **Force Refresh**: Use `antigravity -Force`.

### 2. Deploy a New Repository

Automatically configure security settings for any `atnplex` repo:

```powershell
& "C:\Users\Alex\atn-secrets-manager\deploy-repo.ps1" -Owner "atnplex" -Repo "my-new-repo"
```

### 3. AI Account Rotation (Antigravity Manager)

The manager is running in Docker and handles automatic rotation.

- **Management UI**: [http://localhost:8045](http://localhost:8045)
- **Credentials**: See your `.env` file in `src/antigravity-manager/docker`.

---

## ❓ FAQ & Troubleshooting

### Q: Why am I getting "401 Bad Credentials" on GitHub?

**A**: This usually means the token in Bitwarden has expired or lacks permissions.

1. Verify the token in the GitHub Settings UI.
2. Update the secret in Bitwarden Project `5784e91c-974d-4b76-97ad-b3d8002cd4a5`.
3. Run `antigravity -Force` to refresh.

### Q: How do I add more AI accounts for rotation?

**A**:

1. Open [http://localhost:8045](http://localhost:8045).
2. Go to **Accounts** → **Add Account** → **OAuth**.
3. The launcher automatically points your agent to this proxy.

### Q: What if `antigravity` opens the wrong application?

**A**: The launcher dynamically searches for `Antigravity.exe`. If it fails, ensure Antigravity is installed in `%LOCALAPPDATA%\Programs\Antigravity`.

### Q: How do I change the web manager password?

**A**: Edit `C:\Users\Alex\src\antigravity-manager\docker\.env` and restart the container:

```powershell
docker compose down; docker compose up -d
```

### Q: Why is my GITHUB_PERSONAL_ACCESS_TOKEN missing?

**A**: Ensure you have set your `BWS_ACCESS_TOKEN` in the current terminal session. The launcher will prompt you if it's missing.

---

## 📁 Repository Structure

- `launch-antigravity.ps1`: The primary entry point.
- `deploy-repo.ps1`: Repository hardening script.
- `github-mcp-wrapper.ps1`: Fixes Docker env-var expansion issues for GitHub MCP.
- `install-launcher.ps1`: Installs the `antigravity` command to your PowerShell profile.
