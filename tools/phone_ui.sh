# Helpers for driving Quill on a device. Usage: QUILL_SERIAL=<serial> source tools/phone_ui.sh
# Optional: QUILL_LEASE_TOKEN=<token> runs each command through the Orbit lease wrapper
# (needs ORBIT_COORDINATION_DIR and ../orbit/tools/orbit_coord.py).
# Writes only to .local/ (git-ignored). Never prints book page text.
QUILL_OUT="${QUILL_OUT:-$(pwd)/.local}"; mkdir -p "$QUILL_OUT"
r(){ if [ -n "$QUILL_LEASE_TOKEN" ]; then python3 ../orbit/tools/orbit_coord.py run --token "$QUILL_LEASE_TOKEN" "$@"; else "$@"; fi; }
a(){ r adb -s "$QUILL_SERIAL" "$@"; }
dump(){ a shell uiautomator dump /sdcard/Download/quill-ui.xml >/dev/null; a exec-out cat /sdcard/Download/quill-ui.xml > "$QUILL_OUT/ui.xml"; a shell rm /sdcard/Download/quill-ui.xml; }
# Interface labels with bounds; the WebView subtree (book text) is skipped.
labels(){ python3 - "$QUILL_OUT/ui.xml" <<'PY'
import sys,xml.etree.ElementTree as E
def walk(n,skip):
    skip=skip or n.get('class')=='android.webkit.WebView'
    if n.get('text') and not skip: print(n.get('text')+'\t'+n.get('bounds'))
    for c in n: walk(c,skip)
walk(E.parse(sys.argv[1]).getroot(),False)
PY
}
texts(){ dump; labels | cut -f1 | tr '\n' '|'; echo; }
tap(){ dump; xy=$(labels | awk -F'\t' -v w="$1" '$1==w{gsub(/[\[\]]/," ",$2);split($2,c,/[ ,]+/);print int((c[2]+c[4])/2),int((c[3]+c[5])/2);exit}'); [ -n "$xy" ] && a shell input tap $xy || echo "no '$1' on screen"; }
shot(){ a exec-out screencap -p > "$QUILL_OUT/$1.png"; }
