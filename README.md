# atn-secrets-manager
Zero-Touch Secrets Management Pipeline for Antigravity & MCP.

## 🚀 Usage

### 1. Secure Execution
Inject secrets from Bitwarden SM directly into any process without plaintext files.

```powershell
.\atn-bws.ps1 run "antigravity"
```

### 2. Configuration Hardening
Replace hardcoded secrets in `mcp_config.json` with secure environment variable references.

```powershell
.\atn-bws.ps1 harden "C:\path\to\mcp_config.json"
```

## 🔒 Security Model
- **No Disk Storage**: Secrets are injected into memory via `bws run`.
- **Zero-Touch**: Prompts for BWS access token once per session if not in environment.
- **Auditable**: All access is through the official Bitwarden CLI.
