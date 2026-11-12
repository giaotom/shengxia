#!/usr/bin/env bash
# Probe public Bilibili and Douyin endpoints. Prints status only.
# Does not save media. BV1GJ411x7h7 was deleted; the script also checks a live popular video.
set -u
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
IPHONE='Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'

echo "== bilibili spi =="
SPI=$(curl -fsS -A "$UA" -H "Referer: https://www.bilibili.com/" "https://api.bilibili.com/x/frontend/finger/spi")
python3 - "$SPI" << 'PY'
import json, sys
data = json.loads(sys.argv[1])
b3 = data["data"]["b_3"]
b4 = data["data"]["b_4"]
open("/tmp/shengxia-bili-cookie.txt", "w").write(f"buvid3={b3}; buvid4={b4}")
print("spi", data.get("code"), "buvid3", b3[:8] + "…")
PY
COOKIE=$(cat /tmp/shengxia-bili-cookie.txt)

probe_view() {
  local bv="$1"
  local body
  body=$(curl -sS -A "$UA" -H "Cookie: $COOKIE" -H "Referer: https://www.bilibili.com/video/${bv}/" \
    "https://api.bilibili.com/x/web-interface/view?bvid=${bv}")
  python3 - "$bv" "$body" << 'PY'
import json, sys
bv, raw = sys.argv[1], sys.argv[2]
data = json.loads(raw)
payload = data.get("data") or {}
print(f"view {bv} code={data.get('code')} message={data.get('message')} title={payload.get('title')} cid={payload.get('cid')}")
if data.get("code") == 0:
    open("/tmp/shengxia-bili-cid.txt", "w").write(f"{bv} {payload.get('cid')}")
PY
}

probe_view "BV1GJ411x7h7"
probe_view "BV1xx411c7mD"

if [ -f /tmp/shengxia-bili-cid.txt ]; then
  read -r BV CID < /tmp/shengxia-bili-cid.txt
  echo "== playurl $BV cid $CID =="
  curl -sS -A "$UA" -H "Cookie: $COOKIE" -H "Referer: https://www.bilibili.com/video/${BV}/" \
    "https://api.bilibili.com/x/player/playurl?bvid=${BV}&cid=${CID}&fnval=16&qn=80" -o /tmp/shengxia-play.json
  python3 - << 'PY'
import json
from urllib.parse import urlparse
data = json.load(open("/tmp/shengxia-play.json"))
print("playurl", data.get("code"), data.get("message"))
audios = ((data.get("data") or {}).get("dash") or {}).get("audio") or []
if not audios:
    print("no dash audio")
else:
    best = max(audios, key=lambda item: item.get("bandwidth") or 0)
    url = best.get("baseUrl") or ""
    print("best", best.get("id"), best.get("codecs"), best.get("mimeType"), best.get("bandwidth"), "host", urlparse(url).netloc)
    open("/tmp/shengxia-audio-url.txt", "w").write(url)
PY
  if [ -f /tmp/shengxia-audio-url.txt ]; then
    URL=$(cat /tmp/shengxia-audio-url.txt)
    curl -sS -o /tmp/shengxia-audio.bin -D - -A "$UA" \
      -H "Referer: https://www.bilibili.com/video/${BV}/" \
      -H "Range: bytes=0-31" \
      "$URL" -w "range_http:%{http_code} type:%{content_type} size:%{size_download}\n" | head -n 8
    python3 - << 'PY'
blob = open("/tmp/shengxia-audio.bin", "rb").read(32)
print("ftyp", b"ftyp" in blob, "head", blob[:16])
PY
  fi
fi

echo "== b23 redirect =="
curl -sS -o /dev/null -D - -A "$UA" "https://b23.tv/BV1xx411c7mD" | awk 'BEGIN{IGNORECASE=1} /^HTTP|^location:/ {print}'

echo "== douyin short link =="
FINAL=$(curl -sS -o /tmp/shengxia-dy.html -A "$IPHONE" -L --max-redirs 6 \
  -w "%{url_effective} %{http_code} %{size_download}" \
  "https://v.douyin.com/J4IQiholWbo/")
python3 - "$FINAL" << 'PY'
import sys
from urllib.parse import urlparse
final, code, size = sys.argv[1].rsplit(" ", 2)
path = urlparse(final).path
print(f"final_path {path} http {code} bytes {size}")
html = open("/tmp/shengxia-dy.html", "r", encoding="utf-8", errors="replace").read()
print("router", "_ROUTER_DATA" in html, "item_list", html.count("item_list"), "play_addr", html.count("play_addr"), "bytes", len(html))
PY
rm -f /tmp/shengxia-bili-cookie.txt /tmp/shengxia-audio-url.txt /tmp/shengxia-play.json /tmp/shengxia-audio.bin /tmp/shengxia-dy.html
echo "done"
