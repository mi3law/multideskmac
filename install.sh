#!/bin/bash
# Installs MultiDeskMac into Hammerspoon: builds the Swift helper, links the module into
# ~/.hammerspoon, and creates ~/.hammerspoon/init.lua from init.example.lua if you don't have one.
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
hsdir="$HOME/.hammerspoon"
link="$hsdir/multideskmac"

if [ ! -d /Applications/Hammerspoon.app ]; then
  echo "Hammerspoon isn't installed. Install it first:  brew install --cask hammerspoon" >&2
  exit 1
fi
if ! command -v swiftc >/dev/null; then
  echo "swiftc not found. Install the Xcode Command Line Tools:  xcode-select --install" >&2
  exit 1
fi

echo "Building deskhelper…"
mkdir -p "$repo/multideskmac/bin"
swiftc -O "$repo/multideskmac/helper/deskhelper.swift" -o "$repo/multideskmac/bin/deskhelper"

mkdir -p "$hsdir"
if [ -e "$link" ] && [ ! -L "$link" ]; then
  echo "$link exists and isn't a symlink; move it aside and re-run." >&2
  exit 1
fi
ln -sfn "$repo/multideskmac" "$link"
echo "Linked $link -> $repo/multideskmac"

if [ ! -f "$hsdir/init.lua" ]; then
  cp "$repo/init.example.lua" "$hsdir/init.lua"
  echo "Created $hsdir/init.lua"
elif ! grep -q 'require("multideskmac")' "$hsdir/init.lua"; then
  echo
  echo "Add this to $hsdir/init.lua (see init.example.lua for all options):"
  echo
  sed -n '/^multideskmac = /,$p' "$repo/init.example.lua"
  echo
fi

if pgrep -x Hammerspoon >/dev/null; then
  echo "Reload Hammerspoon's config (hammer menu → Reload Config) to pick up changes."
else
  open -a Hammerspoon
fi
cat <<'EOF'

Then give Hammerspoon Accessibility access:
  System Settings → Privacy & Security → Accessibility → Hammerspoon
Optional, for faster desktop switching:
  System Settings → Keyboard → Keyboard Shortcuts… → Mission Control → "Switch to Desktop N"
EOF
