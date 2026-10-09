#!/usr/bin/env bash
# Fails if a hard-coded `Color(0x…)` appears outside lib/theme/.
# Screens read colours from the theme: context.palette.* or
# Theme.of(context).colorScheme. See docs/ui/HANDOVER.md.
#
# Usage (from anywhere): bash frontend/tool/check_colors.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# Files allowed to keep literal colours.
allowlist=(
  lib/features/developer/presentation/developer_diagnostics_screen.dart # dev tool
)

hits=$(grep -rnE 'Color\(0x' lib --include='*.dart' | grep -v '^lib/theme/' || true)
for f in "${allowlist[@]}"; do
  hits=$(printf '%s\n' "$hits" | grep -v "^$f:" || true)
done

if [ -n "$hits" ]; then
  echo "Hard-coded colours found. Use context.palette.* or the theme instead:"
  echo "$hits"
  exit 1
fi
echo "check_colors: OK"
