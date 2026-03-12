#!/bin/bash
# Records a demo of CW using the mock script and generates a GIF
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CAST_FILE="$SCRIPT_DIR/demo.cast"
GIF_FILE="$SCRIPT_DIR/demo.gif"
MOCK_CW="$SCRIPT_DIR/cw"

# Colors
C='\033[0;36m'
NC='\033[0m'

echo -e "${C}▸${NC} Recording demo..."

# Use the mock cw
export PATH="$SCRIPT_DIR:$PATH"

# Record with asciinema using a scripted session
asciinema rec "$CAST_FILE" --overwrite --cols 100 --rows 25 -c "bash $SCRIPT_DIR/demo-script.sh"

echo -e "${C}▸${NC} Generating GIF..."

# Convert to GIF
agg "$CAST_FILE" "$GIF_FILE" \
  --theme monokai \
  --font-size 16 \
  --cols 100 \
  --rows 25 \
  --speed 1

echo -e "${C}✓${NC} Demo GIF created at: $GIF_FILE"
echo -e "${C}▸${NC} Open with: open $GIF_FILE"
