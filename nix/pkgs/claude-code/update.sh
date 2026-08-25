#!/usr/bin/env bash
# Fetches the latest Claude Code version and SRI hashes for the Nix derivation.
#
# Usage:
#   ./update.sh                  # Show stable + latest channels
#   ./update.sh 2.1.58           # Show stable + specific version

set -euo pipefail

# Canonical download host, scraped from the official installer so it tracks
# upstream if they move it again. Was a public GCS bucket (GCS_BUCKET=...) until
# ~2.1.231; the installer now points at downloads.claude.ai via DOWNLOAD_BASE_URL.
# `|| true` keeps the empty-result case from tripping `set -e` silently, so the
# guard below can report a clear error if the installer format changes again.
BASE_URL=$(curl -fsSL https://claude.ai/install.sh | grep -oP 'DOWNLOAD_BASE_URL="\K[^"]+' || true)

if [[ -z "$BASE_URL" ]]; then
    echo "Could not find DOWNLOAD_BASE_URL in https://claude.ai/install.sh" >&2
    echo "(the installer format probably changed; update this script's grep)." >&2
    exit 1
fi

hex_to_sri() {
    python3 -c "import sys,base64,binascii; print('sha256-' + base64.b64encode(binascii.unhexlify('$1')).decode())"
}

print_channel() {
    local channel="$1"
    local version

    # Resolve version
    if [[ "$channel" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        version="$channel"
    else
        version=$(curl -fsSL "$BASE_URL/$channel")
    fi

    local manifest
    manifest=$(curl -fsSL "$BASE_URL/$version/manifest.json")
    get_hash() { hex_to_sri "$(echo "$manifest" | jq -r ".platforms[\"$1\"].checksum")"; }

    cat <<EOF
[$channel]
version = "$version"
x86_64-linux   (linux-x64):    $(get_hash "linux-x64")
aarch64-darwin (darwin-arm64): $(get_hash "darwin-arm64")
x86_64-darwin  (darwin-x64):   $(get_hash "darwin-x64")
EOF
}

TARGET="${1:-latest}"
print_channel stable
echo
print_channel "$TARGET"
