#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
iconset="$project_dir/.build/AppIcon.iconset"
mkdir -p "$iconset" "$project_dir/Resources"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$project_dir/Assets/AppIcon-master.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$project_dir/Assets/AppIcon-master.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$project_dir/.build/AppIcon-original.icns"
python3 "$project_dir/scripts/optimize-icon.py" "$project_dir/.build/AppIcon-original.icns" "$project_dir/Resources/AppIcon.icns"
printf '已生成 AppIcon.icns\n'
