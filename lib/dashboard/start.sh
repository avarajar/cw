#!/usr/bin/env bash
# ── CW Retro Dashboard Launcher ──────────────────────────────
# Usage: bash lib/dashboard/start.sh
# Or via cw: cw arcade
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

G='\033[0;32m' C='\033[0;36m' DIM='\033[2m' NC='\033[0m'

echo -e "${G}[cw]${NC} ${C}Launching CW Station...${NC}"
echo -e "${DIM}     Retro Arcade Dashboard${NC}"
echo ""

python3 "$SCRIPT_DIR/server.py"
