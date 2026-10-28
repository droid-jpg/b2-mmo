#!/usr/bin/env bash
# Bundles the Lua client, the relay server and the installer: dist/b2-mmo-<version>-windows.zip
# Run after scripts/build.sh: bash scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."
ver="$(sed -n 's/^local VERSION = "\(.*\)"/\1/p' lua/b2mmo.lua)"
name="b2-mmo-$ver-windows"
out="dist/$name"
rm -rf "$out" "dist/$name.zip"
mkdir -p "$out/lua" "$out/server" "$out/tools"
cp lua/b2mmo.lua lua/mmo_code.lua lua/pkm.lua lua/zones.lua lua/species.lua "$out/lua/"
cp server/server.mjs "$out/server/"
cp tools/fakefriend.mjs "$out/tools/"
cp package/install.ps1 package/*.bat package/README.txt "$out/"
if command -v zip >/dev/null; then (cd dist && zip -qr "$name.zip" "$name"); else (cd dist && python3 -m zipfile -c "$name.zip" "$name"); fi
ls -l "dist/$name.zip"
