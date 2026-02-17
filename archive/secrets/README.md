# The Architecture: "The Side-Load Toolbox"

Instead of installing tools inside every container, we provide them via a volume mount.

1. **Host Directory (`/mnt/user/appdata/secrets-toolbox/`)**: Contains static binaries of `age`, `jq`, and `bws`, plus your master script and encryption key.
2. **Container Mount**: This folder is mapped to `/secrets` inside every container.
3. **Universal Entrypoint**: You override the container's entrypoint to run the script from the mounted folder first.

---

### Step 1: Prepare the Toolbox (One-Time Setup)

On your Unraid host, create the directory and download **static** binaries. Using static binaries ensures they work on any Linux distro (Alpine, Debian, Ubuntu) inside your containers.

```bash
# 1. Create directory
mkdir -p /mnt/user/appdata/secrets-toolbox/bin

# 2. Download Static Binaries (commands for 64-bit Linux)
cd /mnt/user/appdata/secrets-toolbox/bin

# bws (Bitwarden Secrets Manager)
wget "https://github.com/bitwarden/sdk/releases/download/bws-v0.5.0/bws-x86_64-unknown-linux-gnu.zip"
unzip bws-*.zip && rm bws-*.zip && chmod +x bws

# age (Encryption)
wget "https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz"
tar -xzf age-*.tar.gz --strip-components=1 age/age && rm age-*.tar.gz && chmod +x age

# jq (JSON Processor)
wget -O jq "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64"
chmod +x jq

# 3. Generate your Master Key
./age -g -o ../master.key

```

### Step 2: The Universal Script (`init.sh`)

Create `/mnt/user/appdata/secrets-toolbox/init.sh`. This script is POSIX-compliant (works in `sh` and `bash`) so it runs on minimal images like Alpine.

```bash
#!/bin/sh

# === Configuration ===
TOOLBOX="/secrets"
BIN="$TOOLBOX/bin"
CACHE_FILE="$TOOLBOX/cache.age"
KEY_FILE="$TOOLBOX/master.key"

# Add our static binaries to PATH for this session
export PATH="$BIN:$PATH"

# User inputs (Passed via Docker ENV)
# BWS_ACCESS_TOKEN is required for online sync
# SECRET_KEY_NAME is the JSON key to look for (e.g., "CLOUDFLARED" or "PLEX")

log() { echo "[SECRETS-INIT] $1"; }

get_secrets_from_cache() {
    if [ -f "$CACHE_FILE" ]; then
        # Decrypt and verify JSON validity (-e to exit on fail)
        DECRYPTED=$(age -d -i "$KEY_FILE" "$CACHE_FILE" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$DECRYPTED" ]; then
            echo "$DECRYPTED"
            return 0
        fi
    fi
    return 1
}

fetch_secrets_online() {
    log "Connecting to Bitwarden (SSOT)..."
    # Fetch specific secret ID that holds your big JSON blob
    # You might pass the BWS_SECRET_ID as an env var too
    PAYLOAD=$(bws secret get "$BWS_SECRET_ID" | jq -r '.value')
    
    if [ -n "$PAYLOAD" ]; then
        log "Updating local encrypted cache..."
        # Atomic write
        RECIPIENT=$(grep "public key" "$KEY_FILE" | awk '{print $4}')
        echo "$PAYLOAD" | age -r "$RECIPIENT" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
        echo "$PAYLOAD"
    else
        log "CRITICAL: Could not fetch secrets from Bitwarden."
        return 1
    fi
}

# 1. Logic Loop
# Try Cache -> If Fail, Go Online -> If Fail, Exit
SECRETS=$(get_secrets_from_cache)
if [ -z "$SECRETS" ]; then
    log "Cache miss or invalid. Going online."
    SECRETS=$(fetch_secrets_online)
    if [ -z "$SECRETS" ]; then exit 1; fi
fi

# 2. Extract Specific Secrets for THIS Service
# We look for a JSON object matching the SECRET_KEY_NAME (e.g., "CLOUDFLARED")
# and export all keys inside it as Environment Variables.
if [ -n "$SECRET_KEY_NAME" ]; then
    log "Injecting secrets for: $SECRET_KEY_NAME"
    
    # Create a clean export string
    VARS=$(echo "$SECRETS" | jq -r --arg key "$SECRET_KEY_NAME" '.[$key] | to_entries | .[] | "export " + .key + "=\"" + .value + "\""')
    
    if [ -z "$VARS" ] || [ "$VARS" = "null" ]; then
        log "No secrets found for $SECRET_KEY_NAME"
    else
        # Eval the exports into current shell
        eval "$VARS"
    fi
fi

# 3. Execution & Self-Healing
# We execute the command. If it crashes (exit code != 0), we assume secrets might be stale.
log "Starting Application..."

# Run the passed command in the background? No, we need to monitor it.
"$@"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    log "Application crashed (Code: $EXIT_CODE). Checking for stale secrets..."
    
    # Force Refresh
    SECRETS=$(fetch_secrets_online)
    
    # Re-Inject
    VARS=$(echo "$SECRETS" | jq -r --arg key "$SECRET_KEY_NAME" '.[$key] | to_entries | .[] | "export " + .key + "=\"" + .value + "\""')
    eval "$VARS"
    
    log "Restarting Application with fresh secrets..."
    exec "$@"
else
    exit 0
fi

```

You are absolutely correct. I recommended the JSON blob method as a workaround for the standard Password Manager, but since you are using **Bitwarden Secrets Manager (BWS)**, you should use its native capabilities.

Using **Bitwarden Secrets Manager** with native Key-Value pairs is the superior "Universal Method." It allows you to manage secrets individually in the UI (easy rotation, easy auditing) while still fetching them securely in bulk for your cache.

Here is the refined architecture using **Native KV Pairs** and the **BWS Machine Account**.

### 1. The Tool: Bitwarden Secrets Manager

Use the Secrets Manager, not the Password Manager.

* **Why:** It uses "Machine Tokens" which don't require manual login/2FA, making it perfect for automation.
* **Structure:** You will create a **Project** in BWS (e.g., named "Homelab"). You will add all your secrets (`TUNNEL_TOKEN`, `PLEX_CLAIM`, `MYSQL_ROOT`) as individual items in this project.
* **Retrieval:** The command `bws secret list` returns a JSON array of *every* secret in that project. We will cache this entire array.

### 2. The Updated "Universal" Script (`init.sh`)

This version is smarter. It fetches the list of secrets, caches them, and then lets you "pick" which ones to inject into the current container using a mapping variable.

Overwrite your `/mnt/user/appdata/secrets-toolbox/init.sh` with this:

```bash
#!/bin/sh

# === Configuration ===
TOOLBOX="/secrets"
CACHE_FILE="$TOOLBOX/cache.age"
KEY_FILE="$TOOLBOX/master.key"
BIN="$TOOLBOX/bin"

export PATH="$BIN:$PATH"

log() { echo "[SECRETS-INIT] $1"; }

# 1. Fetch & Cache Logic
get_secrets() {
    # Try Local Cache First
    if [ -f "$CACHE_FILE" ]; then
        DECRYPTED=$(age -d -i "$KEY_FILE" "$CACHE_FILE" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$DECRYPTED" ]; then
            echo "$DECRYPTED"
            return 0
        fi
    fi

    # Fallback to Online (SSOT)
    log "Cache miss or invalid. Fetching from Bitwarden..."
    
    # 'bws secret list' gets ALL secrets the token has access to
    PAYLOAD=$(bws secret list --output json)
    
    if [ -n "$PAYLOAD" ]; then
        # Update Cache (Encrypt the whole list)
        RECIPIENT=$(grep "public key" "$KEY_FILE" | awk '{print $4}')
        echo "$PAYLOAD" | age -r "$RECIPIENT" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
        log "Cache updated."
        echo "$PAYLOAD"
    else
        log "CRITICAL: Could not fetch secrets."
        return 1
    fi
}

# 2. Load Secrets
ALL_SECRETS=$(get_secrets)
if [ -z "$ALL_SECRETS" ]; then exit 1; fi

# 3. Inject Requested Secrets
# We look for the env var "GET_SECRETS" which contains a list of keys to load.
# Format: "BWS_KEY_NAME:ENV_VAR_NAME" or just "BWS_KEY_NAME" (if names match)
if [ -n "$GET_SECRETS" ]; then
    for MAPPING in $GET_SECRETS; do
        # Split by colon (BWS_KEY:ENV_VAR)
        BWS_KEY="${MAPPING%%:*}"
        ENV_VAR="${MAPPING#*:}"
        
        # Parse the JSON to find the value for the BWS_KEY
        # We handle BWS output structure: [ { "key": "NAME", "value": "SECRET" } ]
        VALUE=$(echo "$ALL_SECRETS" | jq -r --arg k "$BWS_KEY" '.[] | select(.key==$k) | .value')

        if [ -n "$VALUE" ] && [ "$VALUE" != "null" ]; then
            log "Injecting secret: $BWS_KEY -> $ENV_VAR"
            export "$ENV_VAR"="$VALUE"
        else
            log "WARNING: Secret '$BWS_KEY' not found in Bitwarden project."
        fi
    done
fi

# 4. Execute & Heal
log "Starting Application..."
"$@"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    log "Crash detected (Code: $EXIT_CODE). Refreshing SSOT..."
    
    # Force delete cache to trigger re-fetch next run
    rm -f "$CACHE_FILE"
    
    # Re-exec the script (which will re-fetch, re-export, and re-run app)
    exec "$0" "$@"
fi

```

### 3. How to Setup Bitwarden (The "Universal" Part)

1. **Create a Project:** In BWS, create a project named `Homelab`.
2. **Add Secrets:** Add your secrets here.
* Name: `CF_TUNNEL_TOKEN` | Value: `eyJh...`
* Name: `PLEX_CLAIM` | Value: `claim-xyz`


3. **Create a Machine Account:**
* Go to "Machine Accounts".
* Create one named "Unraid Host".
* **Grant it access** to the `Homelab` project (Read Only).
* Copy the `AccessToken`.



### 4. How to use it in Cloudflare Tunnel (Example)

In your Docker Compose or Unraid Template, you now just "request" the secrets you need.

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    environment:
      - BWS_ACCESS_TOKEN=<YOUR_MACHINE_TOKEN>
      # Syntax: BWS_NAME:CONTAINER_VAR
      # We map "CF_TUNNEL_TOKEN" (from BWS) to "TUNNEL_TOKEN" (what app expects)
      - GET_SECRETS=CF_TUNNEL_TOKEN:TUNNEL_TOKEN
    volumes:
      - /mnt/user/appdata/secrets-toolbox:/secrets
    entrypoint:
      - "/secrets/init.sh"
      - "tunnel"
      - "run"

```

### Why this addresses your constraints:

1. **Cached Locally & Encrypted:** The script runs `bws secret list`, gets a JSON array of *all* your secrets, and saves it as `cache.age`.
2. **Automated:** No JSON file editing. You just add a secret in the BWS UI, restart the container, and it's available.
3. **SSOT Check:** If the app crashes (wrong key), the script deletes the cache, fetches fresh data from BWS, and tries again.
4. **No Broadcast:** The keys are injected via `export` inside the script wrapper. They never appear in `ps aux` command arguments.
5. **Namespace Safety:** By using the mapping (`CF_TUNNEL_TOKEN:TUNNEL_TOKEN`), you can have multiple services that all want a variable named `API_KEY` without conflict in Bitwarden. You just name them `SONARR_API_KEY` and `RADARR_API_KEY` in BWS and map them accordingly.

---

### Step 3: Deployment (How to use it universally)

You now have a portable system. Here is how you apply it to **any** service.

#### Bitwarden Setup

Store all your homelab secrets in **one** JSON note in Bitwarden to minimize API calls.

* **Secret Name:** `HOMELAB_MASTER`
* **Value (JSON):**
```json
{
  "CLOUDFLARED": {
    "TUNNEL_TOKEN": "eyJh..."
  },
  "PLEX": {
    "PLEX_CLAIM": "claim-xxx"
  },
  "MARIADB": {
    "MYSQL_ROOT_PASSWORD": "supersecretpassword"
  }
}

```



#### Docker Compose / Unraid Usage

You only need to add 3 things to any container definition:

1. **Volume:** Map the toolbox.
2. **Env:** Tell the script which key to load (`SECRET_KEY_NAME`) and the ID of the master secret (`BWS_SECRET_ID`).
3. **Entrypoint:** Prepend the script.

**Example: Cloudflare Tunnel**

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    environment:
      - BWS_ACCESS_TOKEN=<YOUR_TOKEN>
      - BWS_SECRET_ID=<ID_OF_HOMELAB_MASTER_NOTE>
      - SECRET_KEY_NAME=CLOUDFLARED  # Matches the JSON key in Bitwarden
    volumes:
      # Map the toolbox (Read Only for safety, unless you want it to update the cache)
      # If you want the script to UPDATE the cache, it must be Read/Write
      - /mnt/user/appdata/secrets-toolbox:/secrets
    entrypoint: 
      - "/secrets/init.sh"     # <--- Our Wrapper
      - "tunnel"               # <--- Original Command Part 1
      - "run"                  # <--- Original Command Part 2

```

### Addressing LinuxServer.io Images (Plex, Sonarr, etc.)

Containers from LinuxServer.io use `s6-overlay` and don't like you overriding the `entrypoint`.

For these, you should **not** override the entrypoint. Instead, map the script to their custom init folder.

**For Plex/Sonarr/Radarr:**

1. Map `/mnt/user/appdata/secrets-toolbox/init.sh` to `/custom-cont-init.d/01-secrets`.
2. The `s6` init system will automatically source this script before the app starts.
3. *Note:* The "Self-Healing" restart loop won't work as easily here because `s6` manages the process, but the "Cache vs Online" logic will work perfectly during boot.

### Summary

1. **Toolbox:** `/mnt/user/appdata/secrets-toolbox` contains binaries + key + script.
2. **Secret Source:** One JSON blob in Bitwarden organized by service name.
3. **Automation:** The script auto-decrypts locally. If that fails or the app crashes, it auto-fetches from cloud.
4. **Security:** Keys are in memory (ENV), encrypted on disk (`.age`), and never hardcoded.

Would you like me to detail how to set up the **BWS Machine Account** permissions to ensure this token can *only* read that specific secret?
