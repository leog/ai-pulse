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

# README assets are transparent, so they ship as APNG (.png): GIF's 1-bit
# alpha would fringe the LED glow and antialiased capsule edges.
apng() { # apng <input-pattern> <framerate> <output>
    ffmpeg -y -v error -framerate "$2" -i "$1" -f apng -plays 0 "$3"
    echo "wrote $3"
}

gif() { # gif <input-pattern> <framerate> <output>
    ffmpeg -y -v error -framerate "$2" -i "$1" \
        -vf "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" \
        -loop 0 "$3"
    echo "wrote $3"
}

apng "$FRAMES/states/working/f%03d.png"   25     docs/states/working.png
apng "$FRAMES/states/attention/f%03d.png" 20.05  docs/states/attention.png
apng "$FRAMES/states/failure/f%03d.png"   20     docs/states/failure.png
apng "$FRAMES/states/idle/f%03d.png"      2.4934 docs/states/idle.png
cp "$FRAMES/states/success/f000.png" docs/states/success.png
cp "$FRAMES/states/off/f000.png" docs/states/off.png

apng "$FRAMES/cycle/f%04d.png" 20 docs/pulse-demo.png
# The social cut keeps its dark canvas: sharing platforms flatten or
# re-encode alpha unpredictably, and the captions need a dark ground.
gif "$FRAMES/social/f%04d.png" 20 docs/pulse-social.gif
