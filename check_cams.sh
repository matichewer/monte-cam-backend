#!/usr/bin/env bash
set -euo pipefail

JSON_RAW="cam_raw.json"
JSON_OUT="cam_status.json"
TMP="$(mktemp)"
NOW="$(date --iso-8601=seconds)"

# Headers necesarios para que Castr no devuelva 403
REFERER="https://player.castr.com/"
UA="Mozilla/5.0"

# Validación rápida: que el raw sea JSON válido y tenga cameras
jq -e '.cameras | type=="array"' "$JSON_RAW" >/dev/null

jq -c '.cameras[]' "$JSON_RAW" | while IFS= read -r cam; do
  url="$(jq -r '.url' <<<"$cam")"

  # HEAD al m3u8 (rápido)
  code="$(
    curl -sS -o /dev/null -I \
      -H "Referer: $REFERER" \
      -H "User-Agent: $UA" \
      --connect-timeout 3 \
      --max-time 6 \
      -w "%{http_code}" \
      "$url" || echo "000"
  )"

  # ok como boolean real (no string)
  if [[ "$code" == "200" || "$code" == "206" ]]; then
    ok=true
  else
    ok=false
  fi

  jq -c \
    --arg now "$NOW" \
    --arg code "$code" \
    --argjson ok "$ok" \
    '
      .ok = $ok
      | .last_check = $now
      | .http = ($code | tonumber? // 0)
    ' <<<"$cam"
done | jq -s --arg now "$NOW" '{updated_at: $now, cameras: .}' > "$TMP"

# Escribir atómicamente el STATUS (no el raw)
install -m 0644 "$TMP" "$JSON_OUT"
rm -f "$TMP"
