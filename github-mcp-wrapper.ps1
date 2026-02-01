#!/usr/bin/env pwsh
# github-mcp-wrapper.ps1
# Wrapper script to launch GitHub MCP server with environment variable

if (-not $env:GITHUB_PERSONAL_ACCESS_TOKEN) {
    Write-Error "GITHUB_PERSONAL_ACCESS_TOKEN not set in environment"
    exit 1
}

# Run the GitHub MCP Docker container with the token
docker run -i --rm `
    -e "GITHUB_PERSONAL_ACCESS_TOKEN=$env:GITHUB_PERSONAL_ACCESS_TOKEN" `
    ghcr.io/github/github-mcp-server
