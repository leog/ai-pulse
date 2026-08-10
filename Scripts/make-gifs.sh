#!/bin/bash
# Renders the README/social light-strip assets into docs/ from deterministic
# headless frames (AIPulse --render-lights). Requires ffmpeg (brew install
# ffmpeg). Frame counts and loop periods live in LightFrameRenderer.swift;
# the frame rates here must match frames/period.
set -euo pipefail
cd "$(dirname "$0")/.."

FRAMES="$(mktemp -d)"
trap 'rm -rf "$FRAMES"' EXIT

swift build > /dev/null
.build/debug/AIPulseApp --render-lights "$FRAMES"
mkdir -p docs/states

gif() { # gif <input-pattern> <framerate> <output>
    ffmpeg -y -v error -framerate "$2" -i "$1" \
        -vf "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
        -loop 0 "$3"
    echo "wrote $3"
}

gif "$FRAMES/states/working/f%03d.png"   25     docs/states/working.gif
gif "$FRAMES/states/attention/f%03d.png" 20.05  docs/states/attention.gif
gif "$FRAMES/states/failure/f%03d.png"   20     docs/states/failure.gif
gif "$FRAMES/states/idle/f%03d.png"      2.4934 docs/states/idle.gif
cp "$FRAMES/states/success/f000.png" docs/states/success.png
cp "$FRAMES/states/off/f000.png" docs/states/off.png

gif "$FRAMES/cycle/f%04d.png"  20 docs/pulse-demo.gif
gif "$FRAMES/social/f%04d.png" 20 docs/pulse-social.gif
