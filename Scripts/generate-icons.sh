#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESIGN="$ROOT/Design"
ASSETS="$ROOT/Sources/App/Assets.xcassets"
APPICON="$ASSETS/AppIcon.appiconset"
ABOUTHERO="$ASSETS/AboutHeroIcon.imageset"

small="$DESIGN/fancurve-tier1-favicon.svg"
menubar="$DESIGN/fancurve-tier2-menubar.svg"
dock="$DESIGN/fancurve-tier3-dock.svg"
full="$DESIGN/fancurve-tier4-full.svg"

for f in "$small" "$menubar" "$dock" "$full"; do
  [[ -f "$f" ]] || { echo "missing icon source: $f" >&2; exit 1; }
done

mkdir -p "$APPICON" "$ABOUTHERO"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$ABOUTHERO/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "AboutHeroIcon.png",
      "idiom" : "universal",
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

# About hero: always the full detailed icon.
sips -s format png "$full" --out "$ABOUTHERO/AboutHeroIcon.png" >/dev/null

# App icon reps: trim the transparent outer margin from the canonical SVGs
# before sizing them. This avoids both the white system plate and the fake
# outer border caused by painting the full transparent canvas opaque.
render_trimmed_master() {
  local source="$1"
  local name="$2"
  local raw="$tmpdir/$name-raw.png"
  local trimmed="$tmpdir/$name-trimmed.png"
  sips -s format png "$source" --out "$raw" >/dev/null
  magick "$raw" -trim +repage "$trimmed"
}

resize_icon() {
  local source="$1"
  local size="$2"
  local dest="$3"
  magick "$source" -filter Lanczos -resize "${size}x${size}!" "$dest"
}

render_trimmed_master "$small" small
render_trimmed_master "$menubar" menubar
render_trimmed_master "$dock" dock
render_trimmed_master "$full" full

# Canonical app icon rep ladder:
# tier1 favicon = smallest
# tier2 menubar = next
# tier3 dock = dock / medium-large
# tier4 full = largest
resize_icon "$tmpdir/small-trimmed.png"   16   "$APPICON/AppIcon-16.png"
resize_icon "$tmpdir/small-trimmed.png"   32   "$APPICON/AppIcon-16@2x.png"
resize_icon "$tmpdir/menubar-trimmed.png" 32   "$APPICON/AppIcon-32.png"
resize_icon "$tmpdir/menubar-trimmed.png" 64   "$APPICON/AppIcon-32@2x.png"
resize_icon "$tmpdir/dock-trimmed.png"    128  "$APPICON/AppIcon-128.png"
resize_icon "$tmpdir/dock-trimmed.png"    256  "$APPICON/AppIcon-128@2x.png"
resize_icon "$tmpdir/dock-trimmed.png"    256  "$APPICON/AppIcon-256.png"
resize_icon "$tmpdir/dock-trimmed.png"    512  "$APPICON/AppIcon-256@2x.png"
resize_icon "$tmpdir/full-trimmed.png"    512  "$APPICON/AppIcon-512.png"
resize_icon "$tmpdir/full-trimmed.png"    1024 "$APPICON/AppIcon-512@2x.png"

printf 'generated app icons from canonical tier1/2/3/4 SVGs\n'
