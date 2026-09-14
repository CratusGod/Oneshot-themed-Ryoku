#!/usr/bin/env bash
# Build THE WORLD MACHINE brand art from one pixel grid.
#   usage: build.sh <left-hex> <right-hex> <out.png>
# env:
#   MODE     cover    1920x1080 reload-cover canvas with the SHELL RELOADING caption
#            fallback bare wordmark for the reload cover's own 928x160 box
#            boot     bulb + wordmark lockup, no caption, cropped to the art (Plymouth)
#   CELL     wordmark cell px (18)
#   ALIGN    center | left | right, how line 2 sits under line 1 (center)
#   BULB_PX  lightbulb block px, must divide CELL; 0 = no bulb (9)
set -euo pipefail

LEFT=$1 RIGHT=$2 OUT=$(realpath -m "$3")
HERE=$(cd "$(dirname "$0")" && pwd)
MODE=${MODE:-cover}

CELL=${CELL:-18}
BULB_PX=${BULB_PX:-9}
BULB_SRC=${BULB_SRC:-$HERE/../lockscreen/world-machine/bulb.png}
BULB_CELLS=26                   # the bulb's native grid, measured at 32 px/block
FONT=/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf

COLS=53 ROWS=12                 # the glyph grid mask.py emits
MARK_W=$((COLS * CELL)) MARK_H=$((ROWS * CELL))
GAP=$((CELL * ${GAP_CELLS:-3}))

[ "$MODE" = fallback ] && BULB_PX=0
if [ "$BULB_PX" -gt 0 ]; then
  BULB_W=$((BULB_CELLS * BULB_PX))
  BLOCK_H=$((BULB_W + GAP + MARK_H))
else
  BULB_W=0
  BLOCK_H=$MARK_H
fi

BLOCK_Y=$(((1080 - BLOCK_H) / 2))
MARK_X=$(((1920 - MARK_W) / 2))
MARK_Y=$((BLOCK_Y + BLOCK_H - MARK_H))
CAPTION_Y=$((MARK_Y + MARK_H + 18))   # matches ReloadCover.qml's offset

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

python3 "$HERE/mask.py" "THE WORLD" "MACHINE" 2 "${ALIGN:-center}" > mask.pgm
# Nearest-neighbour upscale keeps the pixel edges hard.
magick mask.pgm -scale "${MARK_W}x${MARK_H}!" mask_big.png
# gradient: runs top-to-bottom; rotate so LEFT lands on the left edge.
magick -size "${MARK_H}x${MARK_W}" "gradient:${RIGHT}-${LEFT}" -rotate 90 grad.png
magick grad.png mask_big.png -alpha off -compose CopyOpacity -composite mark.png

if [ "$MODE" = fallback ]; then
  # The shell draws its own captions and fits the art into a 928x160 box.
  cp mark.png "$OUT"
  exit 0
fi

magick -size 1920x1080 xc:none mark.png -geometry "+${MARK_X}+${MARK_Y}" \
  -compose over -composite canvas.png

if [ "$BULB_PX" -gt 0 ]; then
  # Trim to the art, then downscale so each source block lands on BULB_PX pixels.
  # Sample one pixel per source block first, so any source size lands on the grid.
  magick "$BULB_SRC" -trim +repage -filter point -resize "${BULB_CELLS}x${BULB_CELLS}!" \
    -filter point -resize "${BULB_W}x${BULB_W}!" bulb.png
  magick canvas.png bulb.png -geometry "+$(((1920 - BULB_W) / 2))+${BLOCK_Y}" \
    -compose over -composite canvas.png
fi

case "$MODE" in
  cover)
    magick canvas.png -font "$FONT" -pointsize 11 -kerning 4 -fill '#d8e8f5b8' \
      -gravity North -annotate "+0+${CAPTION_Y}" 'SHELL RELOADING' "$OUT"
    ;;
  boot)
    # Plymouth centres logo.png at native size, so cropping the block to the art
    # lands it exactly where the reload cover draws it on a 1920x1080 screen.
    magick canvas.png -crop "${MARK_W}x${BLOCK_H}+${MARK_X}+${BLOCK_Y}" +repage "$OUT"
    ;;
  *) echo "unknown MODE: $MODE" >&2; exit 2 ;;
esac
