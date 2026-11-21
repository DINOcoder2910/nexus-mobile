#!/bin/sh
# Copies the shared cases from a nexus checkout (its dev/shared) into NexusCore's test fixtures, replacing the old copy, so
# SharedCasesTests runs the same folders as the laptop's dev/unit-shared.mjs. Run from anywhere:
#   sh tools/shared-cases/copy.sh ../nexus
set -e
here=$(cd "$(dirname "$0")/../.." && pwd)
nexus=${1:-$here/../nexus}
src="$nexus/dev/shared"
dst="$here/Packages/NexusCore/Tests/NexusCoreTests/Fixtures/shared"
[ -f "$src/README.md" ] || { echo "no shared cases at $src (pass the nexus checkout)"; exit 1; }
rm -rf "$dst"
cp -R "$src" "$dst"
echo "copied $(find "$dst" -type f | wc -l | tr -d ' ') files from $src (nexus $(git -C "$nexus" rev-parse --short HEAD 2>/dev/null || echo '?'))"
