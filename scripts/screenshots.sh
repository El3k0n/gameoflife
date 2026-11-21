#!/usr/bin/env bash
# Rebuilds the README images in docs/ by running the app with --snapshot
# (Sources/Genesis/App/Snapshot.swift). Run it on a Retina display; the animation needs ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh >/dev/null
mkdir -p docs
frames="$(mktemp -d)"
trap 'rm -rf "$frames"' EXIT

shot() {
    build/Genesis.app/Contents/MacOS/Genesis "$@" -AppleLanguages '(en)' -AppleLocale en_US
}

shot --snapshot docs/genesis.png --grid 256 --generations 250 --inspector on --dark
shot --snapshot docs/day-and-night.png --grid 256 --symmetry quad --density 0.5 --rule B3678/S34678 \
     --palette synth --generations 40 --inspector on --dark
shot --snapshot docs/ink-and-paper.png --grid 128 --palette ink --generations 150 --inspector on

# The Gosper gun repeats every 30 generations, so 30 frames loop without a seam once the stream
# of gliders runs off the edge.
shot --snapshot "$frames/gun.png" --pattern gosper --palette ember --zoom 0.7 --generations 300 \
     --size 900x760 --inspector off --frames 30 --dark
ffmpeg -v error -y -framerate 12 -i "$frames/gun-%03d.png" \
    -vf "crop=trunc(iw*0.88/2)*2:trunc(ih*0.8/2)*2:0:trunc(ih*0.2),split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none" \
    -loop 0 docs/gosper-gun.gif

# ImageIO writes an eXIf chunk into every PNG: keep only the chunks that draw the picture.
python3 - docs/*.png <<'EOF'
import struct, sys
keep = {b'IHDR', b'PLTE', b'tRNS', b'sRGB', b'IDAT', b'IEND'}
for path in sys.argv[1:]:
    data = open(path, 'rb').read()
    out, i = [data[:8]], 8
    while i < len(data):
        n, = struct.unpack('>I', data[i:i + 4])
        if data[i + 4:i + 8] in keep:
            out.append(data[i:i + 12 + n])
        i += 12 + n
    open(path, 'wb').write(b''.join(out))
EOF
ls -l docs
