#!/bin/sh
# Brings the shared Rust core (nexus core/, the code the laptop's new app runs) to the iPad and iPhone, built: NexusCoreFFI.xcframework
# (the core as a static library for the iPad and iPhone, the simulator and the Mac's `swift test`, with its C header) into
# Packages/NexusCore/Rust, and the Swift UniFFI wrote for it into Packages/NexusCore/Sources/NexusRust. Only the built library comes
# here: nexus is private and this repo is public, so the core's source stays there. It builds with nexus core/ffi's own scripts
# (bindings.sh, xcframework.sh; Linux or a Mac with rustup, about 2 minutes), notes the nexus commit (Rust/COMMIT, which the library
# also reports, RustCore.version), and copies the shared cases too (tools/shared-cases/copy.sh), since they move together. CI uses the
# committed library as it is (no Rust on the Mac). Run from anywhere, on a committed nexus checkout:
#   sh tools/rust-core/copy.sh ../nexus
set -e
here=$(cd "$(dirname "$0")/../.." && pwd)
nexus=${1:-$here/../nexus}
ffi="$nexus/core/ffi"
dst="$here/Packages/NexusCore/Rust"
[ -f "$ffi/xcframework.sh" ] || { echo "no core/ffi at $nexus (pass the nexus checkout)"; exit 1; }
[ -z "$(git -C "$nexus" status --porcelain -- core)" ] || echo "warning: nexus core/ has uncommitted changes; COMMIT won't name them"
(cd "$ffi" && sh bindings.sh && sh xcframework.sh)
rm -rf "$dst"
mkdir -p "$dst"
cp -R "$ffi/out/NexusCoreFFI.xcframework" "$dst/"
cp "$ffi/out/COMMIT" "$dst/COMMIT"
cp "$ffi/swift/nexus_core_ffi.swift" "$here/Packages/NexusCore/Sources/NexusRust/"
echo "copied the core from nexus $(cat "$dst/COMMIT") ($(du -sh "$dst/NexusCoreFFI.xcframework" | cut -f1))"
sh "$here/tools/shared-cases/copy.sh" "$nexus"
