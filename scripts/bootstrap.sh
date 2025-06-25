#!/usr/bin/env bash
# sopswarden-bootstrap - Generate encrypted secrets file from Bitwarden
set -euo pipefail

echo "🚀 sopswarden bootstrap - Setting up encrypted secrets"
echo ""
echo "Delegating to sopswarden-sync for reliable secret fetching..."
echo ""

exec sopswarden-sync