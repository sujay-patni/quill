#!/bin/zsh
# Renders the Quill icon SVGs (this folder) into Android and iOS app icons.
# Needs Google Chrome (headless) and macOS sips. Run from anywhere: zsh design/icon/build_icons.sh
set -e
here=${0:A:h}; app=${here:h:h}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
out=$(mktemp -d); trap 'rm -rf $out' EXIT
render() { # svg png [transparent]
  local bg=(); [[ -n $3 ]] && bg=(--default-background-color=00000000)
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --user-data-dir=$out/chrome $bg \
    --window-size=1024,1024 --screenshot=$2 file://$here/$1 >/dev/null 2>&1
}
render icon.svg $out/icon.png
render layer-background.svg $out/bg.png
render layer-foreground.svg $out/fg.png transparent
render layer-monochrome.svg $out/mono.png transparent
cp $out/icon.png $here/icon-1024.png

# Android: legacy icons (48dp) and adaptive layers (108dp) per density.
res=$app/android/app/src/main/res
for d in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  name=${d%%:*}; scale=${d##*:}; dir=$res/mipmap-$name; mkdir -p $dir
  legacy=$(( 48 * scale )); layer=$(( 108 * scale ))
  sips -z ${legacy%.*} ${legacy%.*} $out/icon.png --out $dir/ic_launcher.png >/dev/null
  sips -z ${layer%.*} ${layer%.*} $out/fg.png --out $dir/ic_launcher_foreground.png >/dev/null
  sips -z ${layer%.*} ${layer%.*} $out/bg.png --out $dir/ic_launcher_background.png >/dev/null
  sips -z ${layer%.*} ${layer%.*} $out/mono.png --out $dir/ic_launcher_monochrome.png >/dev/null
done
mkdir -p $res/mipmap-anydpi-v26
cat > $res/mipmap-anydpi-v26/ic_launcher.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
XML

# iOS: every size in AppIcon.appiconset, opaque (the App Store rejects an alpha channel).
sips -s format jpeg -s formatOptions 100 $out/icon.png --out $out/icon.jpg >/dev/null
set_dir=$app/ios/Runner/Assets.xcassets/AppIcon.appiconset
python3 -I - $set_dir/Contents.json <<'PY' | while read file px; do
import json,sys
for i in json.load(open(sys.argv[1]))['images']:
    if 'filename' in i:
        size=float(i['size'].split('x')[0]); scale=int(i['scale'].rstrip('x'))
        print(i['filename'], round(size*scale))
PY
  sips -s format png -z $px $px $out/icon.jpg --out $set_dir/$file >/dev/null
done
echo "Icons written for Android ($res) and iOS ($set_dir)"
