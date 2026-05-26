#!/usr/bin/env bash
# Fetches the latest Claude Code version and SRI hashes for the Nix derivation.
#
# Usage:
#   ./update.sh                  # Show stable + latest channels
#   ./update.sh 2.1.58           # Show stable + specific version
#   ./update.sh --list           # List all available versions

set -euo pipefail

GCS_BUCKET=$(curl -fsSL https://claude.ai/install.sh | grep -oP 'GCS_BUCKET="\K[^"]+')
GCS_ORIGIN="${GCS_BUCKET%/claude-code-releases}"

hex_to_sri() {
    python3 -c "import sys,base64,binascii; print('sha256-' + base64.b64encode(binascii.unhexlify('$1')).decode())"
}

list_versions() {
    curl -fsSL "$GCS_ORIGIN?prefix=claude-code-releases/&delimiter=/" |
        grep -oP '<Prefix>claude-code-releases/\K[0-9][^/]+' |
        sort -V
}

print_channel() {
    local channel="$1"

    # Resolve version
    if [[ "$channel" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        version="$channel"
    else
        version=$(curl -fsSL "$GCS_BUCKET/$channel")
    fi

    manifest=$(curl -fsSL "$GCS_BUCKET/$version/manifest.json")
    get_hash() { hex_to_sri "$(echo "$manifest" | jq -r ".platforms[\"$1\"].checksum")"; }

    cat <<EOF
[$channel]
version = "$version"
x86_64-linux   (linux-x64):    $(get_hash "linux-x64")
aarch64-darwin (darwin-arm64): $(get_hash "darwin-arm64")
x86_64-darwin  (darwin-x64):   $(get_hash "darwin-x64")
EOF
}

if [[ "${1:-}" == "--list" ]]; then
    list_versions
    exit 0
fi

TARGET="${1:-latest}"
print_channel stable
echo
print_channel "$TARGET"
