#!/usr/bin/env bash
# Sync server config backup to local .openclaw/ directory
# Usage: ./sync.sh [hostname]
#   hostname defaults to "openclaw" (assumes SSH config alias)

set -euo pipefail

HOST="${1:-openclaw}"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.openclaw"

mkdir -p "$LOCAL_DIR"

echo "Syncing from $HOST:/root/.openclaw/ → $LOCAL_DIR/"
rsync -avz --delete "root@$HOST:/root/.openclaw/" "$LOCAL_DIR/"
echo "Done."
