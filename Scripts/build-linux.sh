#!/usr/bin/env bash
# Build a self-contained static Linux binary of eqrouter and stage it, with
# its profiles resource, into dist/. Run from the package root.
#
# Requires the Swift static-Linux SDK to be installed (see README). Verify
# with `swift sdk list` — it should show a `*_static-linux-*` entry.
set -euo pipefail

TRIPLE="${1:-x86_64-swift-linux-musl}"
CONFIG="release"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Building eqrouter ($CONFIG, $TRIPLE)"
swift build -c "$CONFIG" --swift-sdk "$TRIPLE" --product eqrouter

BIN_DIR="$(swift build -c "$CONFIG" --swift-sdk "$TRIPLE" --product eqrouter --show-bin-path)"
OUT="$ROOT/dist/eqrouter-linux"
mkdir -p "$OUT"

cp "$BIN_DIR/eqrouter" "$OUT/eqrouter"
# Keep the resources dir next to the binary so the profile catalog loads.
if [ -d "$BIN_DIR/EQRouter_EQRouterCore.resources" ]; then
  rm -rf "$OUT/EQRouter_EQRouterCore.resources"
  cp -R "$BIN_DIR/EQRouter_EQRouterCore.resources" "$OUT/"
fi

# Strip debug info for a much smaller artifact (optional; ignore if absent).
if command -v llvm-strip >/dev/null 2>&1; then llvm-strip "$OUT/eqrouter" || true
elif command -v strip >/dev/null 2>&1; then strip "$OUT/eqrouter" 2>/dev/null || true; fi

echo "==> Staged to $OUT"
ls -lh "$OUT"
echo "==> Run on Linux with:  ./eqrouter serve"
